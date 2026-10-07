#!/usr/bin/env python3
"""AI Image Studio: Catalog-driven Model Downloader for Vast.ai GPU Instances & Local Runtimes.

Pulls model weights directly from Cloudflare R2 (S3 API) instead of HuggingFace,
validates file integrity against R2 sizes, and establishes the required local
directory layout and symlinks for the inference engines (Diffusers, WAN, Voice, TryOn, Enhancer).

Usage:
    python3 download_model.py [model_id_1] [model_id_2] ...
    # Or driven via environment variable:
    AI_STUDIO_SELECTED_MODELS="sdxl-base-1.0,realesrgan-x4plus" python3 download_model.py
"""

import argparse
import os
import sys
import time
from pathlib import Path
from typing import List, Dict, Optional

try:
    import boto3
    import botocore.config
    import botocore.exceptions
except ImportError:  # only needed for R2 downloads; importing this module must not exit the engine
    boto3 = None

# Catalog mappings & engine expectation rules
MODEL_CATALOG: Dict[str, dict] = {
    "realesrgan-x4plus": {
        "family": "enhancer",
        "mode": "enhancer",
        "aliases": ["amd/realesrgan-x4plus", "realesrgan"],
        "target_subpath": "realesrgan",
        "symlinks": [
            ("RealESRGAN_x4plus.pth", "/workspace/models/realesrgan/RealESRGAN_x4plus.pth"),
            ("RealESRGAN_x4plus.pth", "/root/models/realesrgan/RealESRGAN_x4plus.pth"),
            ("RealESRGAN_x4plus.pth", "weights/RealESRGAN_x4plus.pth"),
        ],
    },
    "fashn-vton-1.5": {
        "family": "tryon",
        "mode": "tryon",
        "aliases": ["fashn-ai/fashn-vton-1.5", "fashn-vton"],
        "target_subpath": "fashn-vton",
        "symlinks": [
            (".", "/workspace/models/fashn-vton"),
            (".", "/root/models/fashn-vton"),
        ],
    },
    "breeze-tts-2": {
        "family": "voice",
        "mode": "voice",
        "aliases": ["BreezeBlue/Breeze-TTS-2", "breeze-tts"],
        "target_subpath": "breeze-tts-2",
        "symlinks": [
            (".", "/workspace/models/breeze-tts-2"),
            (".", "/root/models/breeze-tts-2"),
        ],
    },
    "chatterbox-tts": {
        "family": "voice",
        "mode": "voice",
        "aliases": ["ResembleAI/chatterbox", "chatterbox"],
        "target_subpath": "chatterbox-tts",
        "symlinks": [
            (".", "/workspace/models/chatterbox-tts"),
            (".", "/root/models/chatterbox-tts"),
        ],
    },
    "sdxl-base-1.0": {
        "family": "sdxl",
        "mode": "image",
        "aliases": ["stabilityai/stable-diffusion-xl-base-1.0", "sdxl"],
        "target_subpath": "sdxl-base-1.0",
        "symlinks": [
            (".", "/workspace/models/sdxl-base-1.0"),
            (".", "/root/models/sdxl-base-1.0"),
        ],
    },
    "flux-kontext-dev": {
        "family": "flux",
        "mode": "image",
        "aliases": ["black-forest-labs/FLUX.1-Kontext-dev", "flux-kontext"],
        "target_subpath": "flux-kontext-dev",
        "symlinks": [
            (".", "/workspace/models/flux-kontext-dev"),
            (".", "/root/models/flux-kontext-dev"),
            ("flux1-kontext-dev.safetensors", "/root/models/flux1-kontext/flux1-kontext-dev.safetensors"),
        ],
    },
    "z-image-turbo": {
        "family": "zimage",
        "mode": "image",
        "aliases": ["Tongyi-MAI/Z-Image-Turbo", "z-image"],
        "target_subpath": "z-image-turbo",
        "symlinks": [
            (".", "/workspace/models/z-image-turbo"),
            (".", "/root/models/z-image-turbo"),
        ],
    },
    "qwen-image-2.1": {
        "family": "qwen_image",
        "mode": "image",
        "aliases": ["Qwen/Qwen-Image-2.1", "qwen-image"],
        "target_subpath": "qwen-image-2.1",
        "symlinks": [
            (".", "/workspace/models/qwen-image-2.1"),
            (".", "/root/models/qwen-image-2.1"),
        ],
    },
    "wan-2.1-t2v-1.3b": {
        "family": "wan",
        "mode": "video",
        "aliases": ["Wan-AI/Wan2.1-T2V-1.3B-Diffusers", "wan-t2v"],
        "target_subpath": "wan-2.1-t2v-1.3b",
        "symlinks": [
            (".", "/workspace/models/wan-2.1-t2v-1.3b"),
            (".", "/root/models/wan-2.1-t2v-1.3b"),
        ],
    },
    "wan-2.1-i2v-14b": {
        "family": "wan",
        "mode": "video",
        "aliases": ["Wan-AI/Wan2.1-I2V-14B-480P-Diffusers", "wan-i2v"],
        "target_subpath": "wan-2.1-i2v-14b",
        "symlinks": [
            (".", "/workspace/models/wan-2.1-i2v-14b"),
            (".", "/root/models/wan-2.1-i2v-14b"),
        ],
    },
    "wan-2.2-animate-14b": {
        "family": "wan",
        "mode": "video",
        "aliases": ["Wan-AI/Wan2.2-Animate-14B", "wan-animate"],
        "target_subpath": "wan-2.2-animate-14b",
        "symlinks": [
            (".", "/workspace/models/Wan2.2-Animate-14B"),
            (".", "/workspace/models/wan-2.2-animate-14b"),
            (".", "/root/models/wan-2.2-animate-14b"),
        ],
    },
    "minimax-h3": {
        "family": "minimax",
        "mode": "video",
        "aliases": ["MiniMaxAI/MiniMax-H3", "minimax"],
        "target_subpath": "minimax-h3",
        "symlinks": [
            (".", "/workspace/models/minimax-h3"),
            (".", "/root/models/minimax-h3"),
        ],
    },
    "instantid": {
        "family": "instantid",
        "mode": "face",
        "aliases": ["InstantX/InstantID", "instant-id", "instantid-sdxl"],
        "target_subpath": "instantid",
        "symlinks": [
            (".", "/workspace/models/instantid"),
            (".", "/root/models/instantid"),
        ],
    },
}


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def resolve_canonical_id(raw_id: str) -> str:
    """Resolve user/env model identifier or alias to canonical catalog ID."""
    clean = raw_id.strip()
    if clean in MODEL_CATALOG:
        return clean
    for cid, meta in MODEL_CATALOG.items():
        if clean.lower() in [a.lower() for a in meta.get("aliases", [])]:
            return cid
    return clean


def get_r2_client():
    if boto3 is None:
        raise RuntimeError("boto3 is required for R2 downloads. Install via: pip install boto3")
    endpoint = os.environ.get("R2_ENDPOINT")
    access_key = os.environ.get("R2_ACCESS_KEY_ID")
    secret_key = os.environ.get("R2_SECRET_ACCESS_KEY")
    bucket = os.environ.get("R2_BUCKET_NAME", "cosmic-gen")

    if not (endpoint and access_key and secret_key):
        # Check cloud_backend/.env if running in development tree
        # Check for local backend .env if running on local dev host
        possible_envs = [
            Path(__file__).resolve().parent.parent / "cloud_backend" / ".env",
            Path.cwd() / "cloud_backend" / ".env",
            Path.cwd() / ".env",
        ]
        for dev_env in possible_envs:
            if dev_env.exists():
                with open(dev_env) as f:
                    for line in f:
                        line = line.strip()
                        if not line or line.startswith("#") or "=" not in line:
                            continue
                        k, _, v = line.partition("=")
                        k, v = k.strip(), v.strip().strip("'\"")
                        if k == "R2_ENDPOINT" and not endpoint:
                            endpoint = v
                        elif k == "R2_ACCESS_KEY_ID" and not access_key:
                            access_key = v
                        elif k == "R2_SECRET_ACCESS_KEY" and not secret_key:
                            secret_key = v
                        elif k == "R2_BUCKET_NAME" and not bucket:
                            bucket = v
                if endpoint and access_key and secret_key:
                    break

    if not (endpoint and access_key and secret_key):
        raise RuntimeError(
            "R2 credentials missing. Ensure R2_ENDPOINT, R2_ACCESS_KEY_ID, and "
            "R2_SECRET_ACCESS_KEY are set in environment."
        )

    s3 = boto3.client(
        "s3",
        endpoint_url=endpoint.rstrip("/"),
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        region_name="auto",
        config=botocore.config.Config(signature_version="s3v4", retries={"max_attempts": 5}),
    )
    return s3, bucket


def get_default_models_root() -> Path:
    candidates = [
        Path("/workspace/models"),
        Path("/root/models"),
        Path.home() / "models",
        Path("./models"),
    ]
    for p in candidates:
        if p.exists() or p.parent.exists():
            p.mkdir(parents=True, exist_ok=True)
            return p
    default = Path("/workspace/models")
    default.mkdir(parents=True, exist_ok=True)
    return default


def list_r2_model_files(s3, bucket: str, model_id: str) -> List[Dict]:
    prefix = f"models/{model_id}/"
    files = []
    token = None
    while True:
        kwargs = {"Bucket": bucket, "Prefix": prefix, "MaxKeys": 1000}
        if token:
            kwargs["ContinuationToken"] = token
        res = s3.list_objects_v2(**kwargs)
        for obj in res.get("Contents", []):
            rel_name = obj["Key"][len(prefix):]
            if rel_name:
                files.append({
                    "key": obj["Key"],
                    "rel_path": rel_name,
                    "size": obj["Size"],
                    "etag": obj["ETag"].strip('"'),
                })
        if not res.get("IsTruncated"):
            break
        token = res.get("NextContinuationToken")
    return files


def download_single_model(
    s3,
    bucket: str,
    model_id: str,
    models_root: Path,
    progress_callback: Optional[callable] = None,
) -> bool:
    canonical = resolve_canonical_id(model_id)
    log(f"--- Processing model: '{canonical}' (raw: '{model_id}') ---")

    dest_dir = models_root / canonical
    dest_dir.mkdir(parents=True, exist_ok=True)

    r2_files = list_r2_model_files(s3, bucket, canonical)
    if not r2_files:
        log(f"[!] Warning: No objects found under models/{canonical}/ in R2 bucket '{bucket}'.")
        return False

    total_bytes = sum(f["size"] for f in r2_files)
    log(f"Found {len(r2_files)} files in R2 ({total_bytes / 1e9:.2f} GB total).")

    downloaded = 0
    skipped = 0
    bytes_so_far = 0
    t0 = time.time()

    from boto3.s3.transfer import TransferConfig
    transfer_config = TransferConfig(
        multipart_threshold=50 * 1024 * 1024,
        multipart_chunksize=50 * 1024 * 1024,
        max_concurrency=4,
        use_threads=True,
    )

    for item in r2_files:
        rel = item["rel_path"]
        expected_size = item["size"]
        local_path = dest_dir / rel
        local_path.parent.mkdir(parents=True, exist_ok=True)

        if local_path.exists() and local_path.stat().st_size == expected_size:
            skipped += 1
            bytes_so_far += expected_size
            if progress_callback:
                progress_callback(bytes_so_far, total_bytes)
            continue

        log(f"  -> downloading {rel} ({expected_size / 1e6:.1f} MB)...")

        def _chunk_cb(n_bytes):
            nonlocal bytes_so_far
            bytes_so_far += n_bytes
            if progress_callback:
                progress_callback(bytes_so_far, total_bytes)

        s3.download_file(
            bucket,
            item["key"],
            str(local_path),
            Config=transfer_config,
            Callback=_chunk_cb,
        )

        if local_path.stat().st_size != expected_size:
            raise RuntimeError(
                f"Size mismatch on {rel}: expected {expected_size} bytes, got {local_path.stat().st_size} bytes"
            )
        downloaded += 1

    if progress_callback:
        progress_callback(total_bytes, total_bytes)

    dt = time.time() - t0
    log(f"[OK] Model '{canonical}' ready: {downloaded} downloaded, {skipped} cached, {total_bytes / 1e9:.2f} GB in {dt:.1f}s.")

    # Establish backward compatibility symlinks
    catalog_info = MODEL_CATALOG.get(canonical, {})
    for src_rel, target_link_str in catalog_info.get("symlinks", []):
        try:
            target_path = Path(target_link_str)
            target_path.parent.mkdir(parents=True, exist_ok=True)
            if src_rel == ".":
                src_path = dest_dir
            else:
                src_path = dest_dir / src_rel

            if src_path.exists():
                if target_path.is_symlink() or target_path.exists():
                    if target_path.is_symlink() and target_path.resolve() == src_path.resolve():
                        continue
                    if target_path.is_dir():
                        continue
                    try:
                        target_path.unlink()
                    except Exception:
                        pass
                try:
                    os.symlink(str(src_path), str(target_path))
                    log(f"     Linked: {target_path} -> {src_path}")
                except Exception as e:
                    log(f"     [Note] Could not create symlink {target_path}: {e}")
        except Exception as e:
            log(f"     [Note] Symlink setup error for {target_link_str}: {e}")

    return True


def main():
    parser = argparse.ArgumentParser(description="AI Image Studio Model Downloader (R2-backed)")
    parser.add_argument("models", nargs="*", help="Model IDs to download")
    parser.add_argument("--dest-dir", default=None, help="Root directory for models")
    args = parser.parse_args()

    # Determine model list
    model_ids = []
    if args.models:
        model_ids = args.models
    else:
        env_models = os.environ.get("AI_STUDIO_SELECTED_MODELS", "")
        if env_models:
            model_ids = [m.strip() for m in env_models.replace(",", " ").split() if m.strip()]

    if not model_ids:
        log("[*] No models specified on CLI or via AI_STUDIO_SELECTED_MODELS.")
        log("    Usage: python3 download_model.py [model_id_1] [model_id_2] ...")
        sys.exit(0)

    log(f"[*] AI Studio Downloader starting for {len(model_ids)} requested model(s): {model_ids}")

    models_root = Path(args.dest_dir) if args.dest_dir else get_default_models_root()
    log(f"[*] Target models directory: {models_root}")

    try:
        s3, bucket = get_r2_client()
        log(f"[*] Connected to Cloudflare R2 bucket '{bucket}'.")
    except Exception as e:
        log(f"[FATAL] R2 client setup failed: {e}")
        sys.exit(1)

    successful = 0
    for idx, mid in enumerate(model_ids, 1):
        log(f"\n[{idx}/{len(model_ids)}] Preparing: {mid}")
        try:
            ok = download_single_model(s3, bucket, mid, models_root)
            if ok:
                successful += 1
        except Exception as e:
            log(f"[ERROR] Failed downloading '{mid}': {e}")

    log(f"\n===== DOWNLOAD SUMMARY: {successful}/{len(model_ids)} models ready =====")
    if successful < len(model_ids):
        sys.exit(1)


if __name__ == "__main__":
    main()
