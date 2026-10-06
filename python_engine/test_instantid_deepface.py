#!/usr/bin/env python3
"""Standalone Proof-of-Mechanism: InstantID (face-locked generation) + DeepFace (verification scoring).

Loads:
- SDXL base (stabilityai/stable-diffusion-xl-base-1.0)
- InstantID ControlNet + IP-Adapter face conditioning
- InsightFace AntelopeV2 face detector / embedder
- DeepFace verification model (VGG-Face / Facenet)

Executes test generation runs and reports honest similarity verification scores,
timing, and VRAM utilization.
"""

import os
import sys
import time
import json
import argparse
from pathlib import Path

import cv2
import torch
import numpy as np
from PIL import Image

# Ensure local engine directory is on path
ENGINE_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ENGINE_ROOT))

from diffusers.models import ControlNetModel
from insightface.app import FaceAnalysis
from pipeline_stable_diffusion_xl_instantid import StableDiffusionXLInstantIDPipeline, draw_kps


def get_vram_gb() -> float:
    if torch.cuda.is_available():
        return round(torch.cuda.memory_allocated() / (1024 ** 3), 2)
    return 0.0


def get_vram_reserved_gb() -> float:
    if torch.cuda.is_available():
        return round(torch.cuda.memory_reserved() / (1024 ** 3), 2)
    return 0.0


def resize_img(input_image: Image.Image, max_side: int = 1280, min_side: int = 1024, base_pixel_number: int = 64) -> Image.Image:
    w, h = input_image.size
    ratio = min_side / min(h, w)
    w, h = round(ratio * w), round(ratio * h)
    ratio = max_side / max(h, w)
    input_image = input_image.resize([round(ratio * w), round(ratio * h)], Image.BILINEAR)
    w_new = (round(ratio * w) // base_pixel_number) * base_pixel_number
    h_new = (round(ratio * h) // base_pixel_number) * base_pixel_number
    return input_image.resize([w_new, h_new], Image.BILINEAR)


def run_standalone_test(output_dir: Path):
    output_dir.mkdir(parents=True, exist_ok=True)
    results_log = []

    print("==================================================================", flush=True)
    print("🚀 InstantID + DeepFace Proof-of-Mechanism Standalone Test", flush=True)
    print("==================================================================", flush=True)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}", flush=True)
    if device == "cuda":
        print(f"GPU: {torch.cuda.get_device_name(0)} (Total VRAM: {round(torch.cuda.get_device_properties(0).total_memory / (1024**3), 2)} GB)", flush=True)

    # 1. Locate models
    models_root = Path("/workspace/models")
    if not models_root.exists():
        models_root = Path("/root/models")
    if not models_root.exists():
        models_root = ENGINE_ROOT / "models"

    sdxl_path = models_root / "sdxl-base-1.0"
    if not sdxl_path.exists():
        sdxl_path = "stabilityai/stable-diffusion-xl-base-1.0"
    else:
        sdxl_path = str(sdxl_path)

    instantid_dir = models_root / "instantid"
    if not instantid_dir.exists():
        instantid_dir = ENGINE_ROOT / "models_staging" / "instantid"

    controlnet_path = instantid_dir / "ControlNetModel"
    face_adapter_path = instantid_dir / "ip-adapter.bin"
    antelopev2_root = instantid_dir # insightface looks inside root/models/antelopev2

    print(f"SDXL Path: {sdxl_path}", flush=True)
    print(f"InstantID ControlNet: {controlnet_path}", flush=True)
    print(f"InstantID Face Adapter: {face_adapter_path}", flush=True)
    print(f"AntelopeV2 Root: {antelopev2_root}", flush=True)

    # 2. Load InsightFace App
    print("\n[Step 1/4] Loading InsightFace AntelopeV2...", flush=True)
    t0 = time.time()
    providers = ['CUDAExecutionProvider', 'CPUExecutionProvider'] if device == 'cuda' else ['CPUExecutionProvider']
    app = FaceAnalysis(name='antelopev2', root=str(antelopev2_root), providers=providers)
    app.prepare(ctx_id=0 if device == 'cuda' else -1, det_size=(640, 640))
    print(f"  InsightFace ready in {round(time.time() - t0, 2)}s (VRAM: {get_vram_gb()} GB allocated / {get_vram_reserved_gb()} GB reserved)", flush=True)

    # 3. Load InstantID Diffusers Pipeline
    print("\n[Step 2/4] Loading SDXL Base + InstantID ControlNet & IP-Adapter...", flush=True)
    t0 = time.time()
    torch_dtype = torch.float16 if device == 'cuda' else torch.float32

    controlnet = ControlNetModel.from_pretrained(
        str(controlnet_path),
        torch_dtype=torch_dtype
    )

    pipe = StableDiffusionXLInstantIDPipeline.from_pretrained(
        sdxl_path,
        controlnet=controlnet,
        torch_dtype=torch_dtype,
    )
    if device == 'cuda':
        pipe.to("cuda")
    pipe.load_ip_adapter_instantid(str(face_adapter_path))

    # Enable memory-efficient optimizations
    if device == 'cuda':
        try:
            pipe.enable_vae_tiling()
        except Exception:
            pass

    load_time = round(time.time() - t0, 2)
    pipeline_vram = get_vram_gb()
    pipeline_vram_res = get_vram_reserved_gb()
    print(f"  Pipeline loaded in {load_time}s | VRAM: {pipeline_vram} GB allocated ({pipeline_vram_res} GB reserved)", flush=True)

    # 4. Prepare test cases
    examples_dir = ENGINE_ROOT / "examples"
    test_cases = [
        {
            "id": "run_1_musk_cyberpunk",
            "ref_name": "Elon Musk",
            "ref_image": str(examples_dir / "musk_resize.jpeg"),
            "prompt": "portrait of a cybernetic engineer in high-tech glowing lab, neon lighting, highly detailed 8k photography, cinematic realism, 35mm lens",
            "negative_prompt": "blurry, low quality, deformed, disfigured, cartoon, 3d render, watermark, extra limbs",
        },
        {
            "id": "run_2_yann_astronaut",
            "ref_name": "Yann LeCun",
            "ref_image": str(examples_dir / "yann-lecun_resize.jpg"),
            "prompt": "photo of an astronaut commander floating inside a space station cupola with Earth visible outside, dramatic natural sunlight, hyperrealistic portrait, award winning",
            "negative_prompt": "blurry, low quality, deformed, disfigured, painting, lowres, text, watermark",
        },
        {
            "id": "run_3_musk_historical",
            "ref_name": "Elon Musk",
            "ref_image": str(examples_dir / "musk_resize.jpeg"),
            "prompt": "vintage 1920s classic portrait of a gentleman in a bespoke tweed suit, black and white archival silver gelatin print, moody chiaroscuro lighting, masterpiece",
            "negative_prompt": "blurry, modern, digital, color, deformed, glitch, cartoon",
        },
        {
            "id": "run_4_kaifu_warrior",
            "ref_name": "Kai-Fu Lee",
            "ref_image": str(examples_dir / "kaifu_resize.png"),
            "prompt": "epic cinematic film still of a wise ancient warrior general in ornate armor, mist and atmospheric smoke, realistic texture, dramatic rim lighting",
            "negative_prompt": "blurry, oversaturated, cartoon, bad anatomy, deformed eyes, watermark",
        },
    ]

    # Import DeepFace
    print("\n[Step 3/4] Initializing DeepFace for face verification...", flush=True)
    from deepface import DeepFace
    print("  DeepFace module successfully imported.", flush=True)

    # 5. Run Generation & Verification
    print("\n[Step 4/4] Executing test generations and verification runs...", flush=True)

    generated_paths = {}

    for idx, tc in enumerate(test_cases, 1):
        print(f"\n--- [Test Run {idx}/{len(test_cases)}] {tc['ref_name']} -> '{tc['prompt'][:45]}...' ---", flush=True)

        ref_img_pil = Image.open(tc["ref_image"]).convert("RGB")
        ref_img_pil = resize_img(ref_img_pil)

        # Detect face
        face_info = app.get(cv2.cvtColor(np.array(ref_img_pil), cv2.COLOR_RGB2BGR))
        if len(face_info) == 0:
            print(f"  [ERROR] No face detected in reference image: {tc['ref_image']}")
            continue
        face_info = sorted(face_info, key=lambda x: (x['bbox'][2]-x['bbox'][0]) * (x['bbox'][3]-x['bbox'][1]))[-1]
        face_emb = face_info['embedding']
        face_kps = draw_kps(ref_img_pil, face_info['kps'])

        gen_start = time.time()
        with torch.inference_mode():
            out_img = pipe(
                prompt=tc["prompt"],
                negative_prompt=tc["negative_prompt"],
                image_embeds=face_emb,
                image=face_kps,
                controlnet_conditioning_scale=0.8,
                ip_adapter_scale=0.8,
                num_inference_steps=30,
                guidance_scale=5.0,
            ).images[0]
        gen_time = round(time.time() - gen_start, 2)
        vram_peak = get_vram_gb()

        # Save output
        out_filename = f"{tc['id']}.jpg"
        out_path = output_dir / out_filename
        out_img.save(str(out_path), quality=95)
        generated_paths[tc['id']] = str(out_path)

        print(f"  Generated in {gen_time}s | Output: {out_path} | VRAM: {vram_peak} GB", flush=True)

            # Measure InsightFace AntelopeV2 Cosine Similarity directly
            insight_sim = None
            try:
                gen_img_cv = cv2.imread(str(out_path))
                if gen_img_cv is not None:
                    gen_faces = app.get(gen_img_cv)
                    if len(gen_faces) > 0:
                        gen_face = sorted(gen_faces, key=lambda x: (x['bbox'][2]-x['bbox'][0]) * (x['bbox'][3]-x['bbox'][1]))[-1]
                        gen_emb = gen_face['embedding']
                        norm_ref = np.linalg.norm(face_emb)
                        norm_gen = np.linalg.norm(gen_emb)
                        if norm_ref > 0 and norm_gen > 0:
                            insight_sim = round(float(np.dot(face_emb, gen_emb) / (norm_ref * norm_gen)), 4)
                            print(f"    [InsightFace Cosine Sim]: {insight_sim} (Threshold: ~0.40)", flush=True)
            except Exception as e:
                print(f"    [InsightFace Sim Warning]: {e}", flush=True)

            # Verification: DeepFace
            print("  Running DeepFace verification (True pair)...", flush=True)
            v_start = time.time()
            try:
                # Try VGG-Face first; if backend unavailable, try Facenet512
                model_to_use = "VGG-Face"
                try:
                    verif_res = DeepFace.verify(
                        img1_path=tc["ref_image"],
                        img2_path=str(out_path),
                        model_name="VGG-Face",
                        detector_backend="opencv",
                        enforce_detection=False,
                    )
                except Exception as df_err:
                    print(f"    [DeepFace VGG-Face fallback trigger]: {df_err}. Retrying with Facenet...", flush=True)
                    model_to_use = "Facenet"
                    verif_res = DeepFace.verify(
                        img1_path=tc["ref_image"],
                        img2_path=str(out_path),
                        model_name="Facenet",
                        detector_backend="opencv",
                        enforce_detection=False,
                    )

                v_time = round(time.time() - v_start, 2)
                verified = verif_res.get("verified", False)
                distance = round(verif_res.get("distance", 1.0), 4)
                threshold = verif_res.get("threshold", 0.4)
                model_used = verif_res.get("model", model_to_use)
                metric = verif_res.get("similarity_metric", "cosine")
                # Calculate a confidence/similarity score (1 - distance/threshold scaled)
                similarity = round(max(0.0, 1.0 - (distance / threshold) * 0.5) if verified else max(0.0, 0.5 - (distance - threshold)), 3)

                print(f"    [DeepFace {model_used}] Match: {verified} | Distance: {distance} (Threshold: {threshold}) | Metric: {metric} | Similarity: {similarity} | Eval Time: {v_time}s", flush=True)

                log_entry = {
                    "test_id": tc["id"],
                    "subject": tc["ref_name"],
                    "prompt": tc["prompt"],
                    "ref_image": tc["ref_image"],
                    "gen_image": str(out_path),
                    "gen_time_sec": gen_time,
                    "vram_gb": vram_peak,
                    "insightface_cosine_sim": insight_sim,
                    "deepface_match": bool(verified),
                    "deepface_distance": float(distance),
                    "deepface_threshold": float(threshold),
                    "deepface_similarity_score": float(similarity),
                    "deepface_model": model_used,
                }
                results_log.append(log_entry)
            except Exception as e:
                print(f"    [DeepFace ERROR] {e}", flush=True)
                results_log.append({
                    "test_id": tc["id"],
                    "subject": tc["ref_name"],
                    "gen_time_sec": gen_time,
                    "vram_gb": vram_peak,
                    "insightface_cosine_sim": insight_sim,
                    "error": str(e),
                })


    # Sanity-check 2: Cross-Subject Mismatch Test (Control group)
    # Compare Yann LeCun reference against Elon Musk generated image
    print("\n--- [Sanity Check: Deliberate Mismatched Pair] ---", flush=True)
    if "run_1_musk_cyberpunk" in generated_paths:
        yann_ref = str(examples_dir / "yann-lecun_resize.jpg")
        musk_gen = generated_paths["run_1_musk_cyberpunk"]
        print(f"  Comparing Yann LeCun reference vs Elon Musk generation: {musk_gen}", flush=True)
        # InsightFace similarity on mismatch pair
        mismatch_insight_sim = None
        try:
            yann_cv = cv2.imread(yann_ref)
            musk_cv = cv2.imread(musk_gen)
            if yann_cv is not None and musk_cv is not None:
                f1 = app.get(yann_cv)
                f2 = app.get(musk_cv)
                if len(f1) > 0 and len(f2) > 0:
                    e1 = sorted(f1, key=lambda x: (x['bbox'][2]-x['bbox'][0]) * (x['bbox'][3]-x['bbox'][1]))[-1]['embedding']
                    e2 = sorted(f2, key=lambda x: (x['bbox'][2]-x['bbox'][0]) * (x['bbox'][3]-x['bbox'][1]))[-1]['embedding']
                    mismatch_insight_sim = round(float(np.dot(e1, e2) / (np.linalg.norm(e1) * np.linalg.norm(e2))), 4)
                    print(f"    [InsightFace Mismatch Sim]: {mismatch_insight_sim} (Expected: <0.25)", flush=True)
        except Exception as e:
            print(f"    [InsightFace Mismatch Sim Warning]: {e}", flush=True)

        try:
            ctrl_model = "VGG-Face"
            try:
                mismatch_res = DeepFace.verify(
                    img1_path=yann_ref,
                    img2_path=musk_gen,
                    model_name="VGG-Face",
                    detector_backend="opencv",
                    enforce_detection=False,
                )
            except Exception as e_df:
                ctrl_model = "Facenet"
                mismatch_res = DeepFace.verify(
                    img1_path=yann_ref,
                    img2_path=musk_gen,
                    model_name="Facenet",
                    detector_backend="opencv",
                    enforce_detection=False,
                )
            m_verified = mismatch_res.get("verified", False)
            m_distance = round(mismatch_res.get("distance", 1.0), 4)
            m_threshold = mismatch_res.get("threshold", 0.4)
            print(f"    [DeepFace {ctrl_model} Control Result] Match: {m_verified} (Expected: False) | Distance: {m_distance} (Threshold: {m_threshold})", flush=True)
            results_log.append({
                "test_id": "control_cross_subject_mismatch",
                "subject_1": "Yann LeCun (Ref)",
                "subject_2": "Elon Musk (Gen)",
                "insightface_cosine_sim": mismatch_insight_sim,
                "deepface_match": bool(m_verified),
                "deepface_distance": float(m_distance),
                "deepface_threshold": float(m_threshold),
                "deepface_model": ctrl_model,
                "expected_match": False,
            })
        except Exception as e:
            print(f"    [DeepFace Control ERROR] {e}", flush=True)

    # Save summary report JSON
    summary_path = output_dir / "instantid_deepface_results.json"
    with open(summary_path, "w") as f:
        json.dump({
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime()),
            "device": device,
            "pipeline_load_time_sec": load_time,
            "pipeline_vram_gb": pipeline_vram,
            "pipeline_vram_reserved_gb": pipeline_vram_res,
            "results": results_log,
        }, f, indent=2)

    print("\n==================================================================", flush=True)
    print(f"✅ Standalone Test Suite Finished. Summary saved to {summary_path}", flush=True)
    print("==================================================================", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output_dir", default="/root/instantid_test_outputs", help="Output directory for generated images and scores")
    args = parser.parse_args()
    run_standalone_test(Path(args.output_dir))
