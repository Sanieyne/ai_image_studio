#!/usr/bin/env python3
"""Migrate the 12 catalog model weight repos from HuggingFace to Cloudflare R2.

One model at a time: snapshot-download from HF to a temp dir -> upload every
file to R2 under models/{modelId}/{repo-relative-path} -> verify size match ->
delete the temp dir -> next model.

Resumable: files already present in R2 with a matching size are skipped, so
re-running after a failure continues where it left off instead of restarting.
snapshot_download itself also resumes partial downloads.

Usage:
    cloud_backend/.venv/bin/python scripts/migrate_models_to_r2.py [--only MODEL_ID] [...]
    HF_TOKEN=hf_...  # required only for gated repos (FLUX.1-Kontext-dev)

R2 credentials come from cloud_backend/.env (R2_ENDPOINT, R2_ACCESS_KEY_ID,
R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME).
"""

import argparse
import os
import shutil
import sys
import tempfile
import time

import boto3
import botocore.config
import botocore.exceptions
import fnmatch
from huggingface_hub import list_repo_files, snapshot_download
from huggingface_hub.utils import GatedRepoError, RepositoryNotFoundError

# Catalog mirror of Mongo `modelcatalogs` (modelId, HF repo, documented GB),
# ordered smallest-first so the pipeline validates itself on cheap models
# before the multi-hour 28-33GB transfers.
MODELS = [
    {"id": "realesrgan-x4plus", "repo": "amd/realesrgan-x4plus", "gb": 0.15},
    {"id": "fashn-vton-1.5", "repo": "fashn-ai/fashn-vton-1.5", "gb": 1.9},
    {"id": "breeze-tts-2", "repo": "BreezeBlue/Breeze-TTS-2", "gb": 7.7},
    {"id": "sdxl-base-1.0", "repo": "stabilityai/stable-diffusion-xl-base-1.0", "gb": 6.9},
    {"id": "chatterbox-tts", "repo": "ResembleAI/chatterbox", "gb": 13.9},
    {"id": "wan-2.1-t2v-1.3b", "repo": "Wan-AI/Wan2.1-T2V-1.3B-Diffusers", "gb": 28.9},
    {"id": "z-image-turbo", "repo": "Tongyi-MAI/Z-Image-Turbo", "gb": 32.9},
    {"id": "qwen-image-2.1", "repo": "Qwen/Qwen-Image-2.1", "gb": 33.1},
    {"id": "flux-kontext-dev", "repo": "black-forest-labs/FLUX.1-Kontext-dev", "gb": 33.8},
    {"id": "wan-2.2-animate-14b", "repo": "Wan-AI/Wan2.2-Animate-14B", "gb": 60.5},
    {"id": "wan-2.1-i2v-14b", "repo": "Wan-AI/Wan2.1-I2V-14B-480P-Diffusers", "gb": 90.1},
    {"id": "minimax-h3", "repo": "MiniMaxAI/MiniMax-H3", "gb": 498.0},
]

PART_SIZE = 100 * 1024 * 1024  # 100MB multipart chunks for multi-GB shards
SKIP_DIRS = {".git", ".cache"}
SKIP_FILES = {".DS_Store"}

# Weight formats the diffusers/torch engine never loads. Full HF snapshots
# bundle these alongside the production weights (SDXL's raw snapshot is 62GB
# vs 6.9GB of used weights) — mirroring them wastes disk, bandwidth, and R2.
ALWAYS_IGNORE = [
    "*.bin", "*.onnx", "*.pb", "*.tflite", "*.h5", "*.ot", "*.msgpack",
    "*.ckpt", "*.opus", "*.flac", "*.mp3", "*.wav",
    "onnx/*", "openvino/*", "*_openvino/*", "*_onnx/*", "onnx_data/*",
    "*onnx_data*",
]


def compute_ignores(repo_files):
    """Ignore patterns pruning an HF snapshot down to production weights.

    1. ALWAYS_IGNORE formats (other runtimes' exports, audio samples, ...).
    2. fp32 duplicate shards when an fp16 twin exists in the same folder
       (engine loads variant="fp16").
    3. Root-level single-file checkpoints in diffusers repos (model_index.json
       present): from_pretrained loads the subfolder shards, never these.
    """
    ignores = list(ALWAYS_IGNORE)
    files = set(repo_files)
    for f in repo_files:
        base = f.rsplit(".", 1)[0]
        if f.endswith(".fp16.safetensors"):
            twin = base[: -len(".fp16")] + ".safetensors"
            if twin in files:
                ignores.append(twin)
    if "model_index.json" in files:
        for f in repo_files:
            if "/" not in f and f.endswith(".safetensors"):
                ignores.append(f)
    return ignores


def matches_any(path, patterns):
    return any(fnmatch.fnmatch(path, p) or fnmatch.fnmatch(os.path.basename(path), p)
               for p in patterns)


def free_gb(path):
    st = os.statvfs(path)
    return st.f_bavail * st.f_frsize / 1e9


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def load_dotenv(path):
    """Minimal .env loader (KEY=VALUE, ignores comments/blanks/quotes)."""
    values = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                values[key.strip()] = val.strip().strip("'\"")
    except FileNotFoundError:
        pass
    return values


def r2_client(dotenv):
    endpoint = os.environ.get("R2_ENDPOINT") or dotenv.get("R2_ENDPOINT", "")
    key = os.environ.get("R2_ACCESS_KEY_ID") or dotenv.get("R2_ACCESS_KEY_ID", "")
    secret = os.environ.get("R2_SECRET_ACCESS_KEY") or dotenv.get("R2_SECRET_ACCESS_KEY", "")
    bucket = os.environ.get("R2_BUCKET_NAME") or dotenv.get("R2_BUCKET_NAME", "")
    if not (endpoint and key and secret and bucket):
        sys.exit("[FATAL] R2 credentials missing. Set R2_ENDPOINT, R2_ACCESS_KEY_ID, "
                 "R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME in cloud_backend/.env")
    s3 = boto3.client(
        "s3",
        endpoint_url=endpoint.rstrip("/"),
        aws_access_key_id=key,
        aws_secret_access_key=secret,
        region_name="auto",
        config=botocore.config.Config(signature_version="s3v4", retries={"max_attempts": 5}),
    )
    return s3, bucket


def r2_existing(s3, bucket, model_id):
    """Map of repo-relative path -> size for files already stored for a model."""
    existing = {}
    token = None
    prefix = f"models/{model_id}/"
    while True:
        kwargs = {"Bucket": bucket, "Prefix": prefix, "MaxKeys": 1000}
        if token:
            kwargs["ContinuationToken"] = token
        res = s3.list_objects_v2(**kwargs)
        for obj in res.get("Contents", []):
            existing[obj["Key"][len(prefix):]] = obj["Size"]
        if not res.get("IsTruncated"):
            break
        token = res.get("NextContinuationToken")
    return existing


def local_files(root):
    """All repo files under root as (relative_path, absolute_path, size)."""
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in sorted(filenames):
            if name in SKIP_FILES:
                continue
            abs_path = os.path.join(dirpath, name)
            rel = os.path.relpath(abs_path, root)
            out.append((rel, abs_path, os.path.getsize(abs_path)))
    return out


def upload_verified(s3, bucket, key, abs_path, size):
    from boto3.s3.transfer import TransferConfig
    s3.upload_file(
        abs_path, bucket, key,
        Config=TransferConfig(multipart_threshold=PART_SIZE, multipart_chunksize=PART_SIZE,
                              max_concurrency=4, use_threads=True),
    )
    head = s3.head_object(Bucket=bucket, Key=key)
    if head["ContentLength"] != size:
        raise RuntimeError(f"size mismatch after upload for {key}: "
                           f"local={size} remote={head['ContentLength']}")


def migrate_model(s3, bucket, model, tmp_root, hf_token, idx, total):
    model_id, repo, doc_gb = model["id"], model["repo"], model["gb"]
    log(f"===== [{idx}/{total}] {model_id} ({repo}, ~{doc_gb}GB) =====")
    t0 = time.time()
    target = os.path.join(tmp_root, model_id)

    try:
        repo_files = list_repo_files(repo, token=hf_token)
    except GatedRepoError:
        log(f"GATED: '{repo}' requires license acceptance on huggingface.co "
            f"plus a HF_TOKEN with access. Skipping {model_id} (re-run later).")
        return "gated"
    except RepositoryNotFoundError:
        log(f"NOT FOUND: '{repo}' does not exist or token lacks access. Skipping.")
        return "missing"
    ignores = compute_ignores(repo_files)
    kept = [f for f in repo_files if not matches_any(f, ignores)]
    log(f"Repo has {len(repo_files)} files; mirroring {len(kept)} production files "
        f"({len(repo_files) - len(kept)} pruned: other-runtimes/fp32-dupes/single-file-dupes)")

    need_gb = max(5.0, doc_gb * 1.1 + 1.0)
    have_gb = free_gb(tmp_root)
    if have_gb < need_gb:
        log(f"DISK GUARD: {have_gb:.1f}GB free, need ~{need_gb:.0f}GB for {model_id}. "
            f"Free space and re-run.")
        return "disk-full"

    log(f"Downloading snapshot from HuggingFace -> {target}")
    try:
        snapshot_download(repo_id=repo, local_dir=target, token=hf_token,
                          max_workers=4, ignore_patterns=ignores)
    except Exception:
        shutil.rmtree(target, ignore_errors=True)
        raise

    try:
        files = local_files(target)
        total_bytes = sum(s for _, _, s in files)
        log(f"Snapshot complete: {len(files)} files, {total_bytes / 1e9:.2f}GB")

        existing = r2_existing(s3, bucket, model_id)
        log(f"Already in R2: {len([f for f in files if existing.get(f[0]) == f[2]])}/{len(files)} "
            f"(skip-on-size-match)")
        uploaded, skipped = 0, 0
        for rel, abs_path, size in files:
            key = f"models/{model_id}/{rel}"
            if existing.get(rel) == size:
                skipped += 1
                continue
            log(f"  up {rel} ({size / 1e6:.1f}MB)")
            upload_verified(s3, bucket, key, abs_path, size)
            uploaded += 1
    finally:
        shutil.rmtree(target, ignore_errors=True)

    dt = time.time() - t0
    log(f"DONE [{idx}/{total}] {model_id}: {uploaded} uploaded, {skipped} skipped, "
        f"{total_bytes / 1e9:.2f}GB in {dt / 60:.1f}min. Temp deleted.")
    return "ok"


def main():
    ap = argparse.ArgumentParser(description="Migrate HF model weights to R2")
    ap.add_argument("--only", action="append", default=[],
                    help="Only migrate these model ids (repeatable)")
    ap.add_argument("--tmp-root", default=None,
                    help="Temp download dir (default: system temp)")
    ap.add_argument("--hf-token", default=None, help="HF token (or HF_TOKEN env)")
    args = ap.parse_args()

    backend_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dotenv = load_dotenv(os.path.join(backend_root, ".env"))
    hf_token = args.hf_token or os.environ.get("HF_TOKEN") or dotenv.get("HF_TOKEN")
    s3, bucket = r2_client(dotenv)
    log(f"R2 bucket: {bucket}")

    wanted = [m for m in MODELS if not args.only or m["id"] in args.only]
    if args.only:
        unknown = set(args.only) - {m["id"] for m in MODELS}
        if unknown:
            sys.exit(f"[FATAL] Unknown model ids: {sorted(unknown)}")
    tmp_root = args.tmp_root or tempfile.mkdtemp(prefix="r2migrate-")
    os.makedirs(tmp_root, exist_ok=True)
    log(f"Temp root: {tmp_root} | HF_TOKEN: {'set' if hf_token else 'NOT SET'}")

    results = {}
    t_start = time.time()
    try:
        for i, model in enumerate(wanted, 1):
            try:
                results[model["id"]] = migrate_model(s3, bucket, model, tmp_root,
                                                     hf_token, i, len(wanted))
            except (KeyboardInterrupt, SystemExit):
                raise
            except Exception as e:
                log(f"FAILED {model['id']}: {type(e).__name__}: {e}")
                results[model["id"]] = "failed"
    finally:
        dt = time.time() - t_start
        log(f"===== SUMMARY ({dt / 60:.1f}min total) =====")
        for m in wanted:
            log(f"  {m['id']}: {results.get(m['id'], 'not-run')}")
        if not args.tmp_root and os.path.exists(tmp_root):
            shutil.rmtree(tmp_root, ignore_errors=True)

    bad = {k: v for k, v in results.items() if v != "ok"}
    if bad:
        log(f"{len(bad)} model(s) need attention: {bad}. Re-run to resume.")
        sys.exit(2)


if __name__ == "__main__":
    main()
