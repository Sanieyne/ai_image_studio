"""HTTP routes: generation + LoRA management (Part 3/5)."""
from __future__ import annotations

import base64
import io
import logging
import time
from typing import Dict

from fastapi import APIRouter, HTTPException, status
from PIL import Image

from api.schemas import (
    GenerateRequest,
    GenerateResponse,
    HealthResponse,
    LoraConfig,
    LoraScaleRequest,
    ModelSwitchRequest,
)
from generation.pipeline import (
    ASPECT_RATIO_BUCKETS,
    get_pipeline,
    nearest_bucket,
)

log = logging.getLogger(__name__)
router = APIRouter()


@router.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    pipe = get_pipeline()
    return HealthResponse(
        status="ok" if pipe.model_loaded else "ok-mock",
        device=pipe.device,
        model_loaded=pipe.model_loaded,
        current_model=pipe.current_model,
    )



def _resolve_aspect(req: GenerateRequest) -> str:
    """Explicit aspect wins; else snap width/height; else 9:16 default."""
    if req.aspect_ratio:
        if req.aspect_ratio not in ASPECT_RATIO_BUCKETS:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Unknown aspect_ratio '{req.aspect_ratio}'. "
                f"Valid: {sorted(ASPECT_RATIO_BUCKETS)}",
            )
        return req.aspect_ratio
    if req.width and req.height:
        return nearest_bucket(req.width, req.height)
    return "9:16"


@router.post("/generate", response_model=GenerateResponse)
def generate_image(req: GenerateRequest) -> GenerateResponse:
    pipeline = get_pipeline()
    start_time = time.perf_counter()
    transient_loras = bool(req.loras)
    # Snapshot persistent adapters so transient cleanup restores them.
    prior_loras: Dict[str, dict] = dict(pipeline.active_loras)

    try:
        if req.loras:
            for lora in req.loras:
                pipeline.load_lora(
                    lora_path_or_id=lora.path_or_id,
                    adapter_name=lora.adapter_name,
                    weight=lora.weight,
                )

        aspect_ratio = _resolve_aspect(req)
        width, height = ASPECT_RATIO_BUCKETS[aspect_ratio]
        log.info(
            "generate aspect=%s size=%dx%d steps=%d scale=%.1f seed=%s "
            "loras=%d prompt=%.60s",
            aspect_ratio, width, height, req.steps,
            req.guidance_scale, req.seed,
            len(req.loras or []), req.prompt,
        )

        init_image = None
        if req.image_base64:
            raw_b64 = req.image_base64
            if "," in raw_b64:
                raw_b64 = raw_b64.split(",", 1)[1]
            try:
                img_data = base64.b64decode(raw_b64)
                init_image = Image.open(io.BytesIO(img_data)).convert("RGB")
            except Exception as e:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Invalid image_base64 attachment: {e}",
                )

        b64, seed_used, _ = pipeline.generate(
            prompt=req.prompt,
            negative_prompt=req.negative_prompt or "",
            steps=req.steps,
            cfg_scale=req.guidance_scale,
            aspect_ratio=aspect_ratio,
            seed=req.seed if req.seed is not None else -1,
            init_image=init_image,
            strength=req.strength,
        )
        elapsed_ms = int((time.perf_counter() - start_time) * 1000)

        img_b64 = b64
        if not img_b64.startswith("data:image"):
            img_b64 = f"data:image/jpeg;base64,{img_b64}"

        return GenerateResponse(
            success=True,
            image_base64=img_b64,
            seed=seed_used,
            inference_time_ms=elapsed_ms,
            width=width,
            height=height,
            aspect_ratio=aspect_ratio,
            active_loras={
                k: {"path": str(v.get("path", "")),
                    "weight": float(v.get("weight", 0.0))}
                for k, v in pipeline.active_loras.items()
            },
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Generation failed: {e}",
        )
    finally:
        if transient_loras:
            pipeline.unload_loras()
            for name, data in prior_loras.items():
                pipeline.load_lora(
                    str(data.get("path", name)),
                    adapter_name=name,
                    weight=float(data.get("weight", 0.8)),
                )


@router.get("/loras")
def list_active_loras():
    return {"active_loras": get_pipeline().active_loras}


@router.post("/loras/load")
def load_lora_endpoint(req: LoraConfig):
    pipeline = get_pipeline()
    try:
        adapter_name = pipeline.load_lora(
            lora_path_or_id=req.path_or_id,
            adapter_name=req.adapter_name,
            weight=req.weight,
        )
        return {
            "success": True,
            "adapter_name": adapter_name,
            "active_loras": pipeline.active_loras,
        }
    except FileNotFoundError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e),
        )


@router.post("/loras/unload")
def unload_loras_endpoint():
    get_pipeline().unload_loras()
    return {"success": True, "active_loras": {}}


@router.post("/loras/scale")
def scale_lora_endpoint(req: LoraScaleRequest):
    pipeline = get_pipeline()
    try:
        pipeline.set_lora_scale(req.adapter_name, req.weight)
        return {
            "success": True,
            "adapter_name": req.adapter_name,
            "weight": req.weight,
            "active_loras": pipeline.active_loras,
        }
    except KeyError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Adapter '{req.adapter_name}' is not loaded",
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e),
        )


@router.get("/models/current")
def get_current_model():
    pipe = get_pipeline()
    return {
        "model_id": pipe.current_model,
        "device": pipe.device,
        "model_loaded": pipe.model_loaded,
    }


@router.post("/models/switch")
def switch_model_endpoint(req: ModelSwitchRequest):
    pipeline = get_pipeline()
    try:
        loaded = pipeline.switch_model(req.model_id)
        return {
            "success": True,
            "model_id": loaded,
            "message": f"Successfully loaded model: {loaded}",
        }
    except Exception as e:
        log.exception("Failed to switch model: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to switch model: {e}",
        )

