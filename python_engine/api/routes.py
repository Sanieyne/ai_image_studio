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
    VideoRequest,
    VideoResponse,
    AnimateRequest,
    VoiceRequest,
    VoiceResponse,
    MiniMaxRequest,
    TryOnRequest,
    TryOnResponse,
    Wan2_1Request,
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
    from generation.device import get_device_name
    return HealthResponse(
        status="ok" if pipe.model_loaded else "ok-mock",
        device=pipe.device,
        device_name=get_device_name(),
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
    engine = getattr(pipeline, "engine", None)
    if (engine is not None
            and not getattr(engine, "mock_mode", False)
            and getattr(engine, "pipe", None) is None):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Engine has no model loaded (a previous model switch "
                   "failed). Pick a model such as RealVisXL and try again.",
        )
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
        log.exception("Generation failed: %s", e)
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
        log.exception("LoRA load failed for %s", req.path_or_id)
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
        msg = str(e)
        # Gated/private HF repos (e.g. FLUX.1-schnell) need login, not a
        # retry: answer 403 with a human message instead of a bare 500.
        if ("gated" in msg.lower() or "401" in msg
                or "must have access" in msg.lower()
                or "restricted" in msg.lower()):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Model '{req.model_id}' is gated on HuggingFace and "
                       f"needs login (HF_TOKEN). The previous model is still "
                       f"loaded. Details: {e}",
            )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to switch model (previous model still loaded): {e}",
        )



@router.post("/video", response_model=VideoResponse)
def generate_video(req: VideoRequest) -> VideoResponse:
    """Image-to-video (or text-to-video) via local LTX 2B distilled."""
    from generation.video_pipeline import get_video_engine

    raw = None
    if req.image_base64:
        b64 = req.image_base64
        if "," in b64:
            b64 = b64.split(",", 1)[1]
        try:
            raw = base64.b64decode(b64)
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid image_base64: {e}",
            )
    try:
        mp4, seed_used = get_video_engine().generate_mp4(
            prompt=req.prompt,
            init_image=raw,
            num_frames=req.num_frames,
            num_inference_steps=req.steps,
            seed=req.seed if req.seed is not None else -1,
            width=req.width,
            height=req.height,
            fps=req.fps,
        )
    except FileNotFoundError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except Exception as e:
        log.exception("Video generate failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Video generate failed: {e}",
        )
    return VideoResponse(
        success=True,
        video_base64=base64.b64encode(mp4).decode(),
        seed=seed_used,
        num_frames=req.num_frames,
        fps=req.fps,
    )


@router.post("/animate", response_model=VideoResponse)
def animate_character(req: AnimateRequest) -> VideoResponse:
    """Wan 2.2 Animate 14B Character Motion Animation endpoint."""
    from generation.video_pipeline import get_wan_engine

    ref_b64 = req.image_base64
    if "," in ref_b64:
        ref_b64 = ref_b64.split(",", 1)[1]
    try:
        ref_bytes = base64.b64decode(ref_b64)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid image_base64: {e}",
        )

    tpl_bytes = None
    if req.template_video_base64:
        tpl_b64 = req.template_video_base64
        if "," in tpl_b64:
            tpl_b64 = tpl_b64.split(",", 1)[1]
        try:
            tpl_bytes = base64.b64decode(tpl_b64)
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid template_video_base64: {e}",
            )

    try:
        engine = get_wan_engine()
        mp4, seed_used = engine.animate(
            refer_image_bytes=ref_bytes,
            template_video_bytes=tpl_bytes,
            prompt=req.prompt or "",
            width=req.width,
            height=req.height,
            clip_len=17,
            num_frames=req.num_frames,
            steps=req.steps,
            sample_guide_scale=req.sample_guide_scale,
            seed=req.seed if req.seed is not None else -1,
            fps=req.fps,
        )
    except Exception as e:
        log.exception("Wan Animate failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Wan Animate failed: {e}",
        )

    return VideoResponse(
        success=True,
        video_base64=base64.b64encode(mp4).decode(),
        seed=seed_used,
        num_frames=req.num_frames,
        fps=req.fps,
    )


@router.post("/wan2_1", response_model=VideoResponse)
def generate_wan2_1(req: Wan2_1Request) -> VideoResponse:
    """Wan 2.1 Foundation Video Generation (T2V 1.3B/14B, I2V 14B, FLF2V)."""
    from generation.video_pipeline import get_wan2_1_engine

    init_bytes = None
    if req.image_base64:
        raw_b64 = req.image_base64
        if "," in raw_b64:
            raw_b64 = raw_b64.split(",", 1)[1]
        try:
            init_bytes = base64.b64decode(raw_b64)
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid image_base64: {e}",
            )

    end_bytes = None
    if req.end_image_base64:
        raw_b64 = req.end_image_base64
        if "," in raw_b64:
            raw_b64 = raw_b64.split(",", 1)[1]
        try:
            end_bytes = base64.b64decode(raw_b64)
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid end_image_base64: {e}",
            )

    try:
        engine = get_wan2_1_engine()
        mp4_bytes, seed_used = engine.generate(
            prompt=req.prompt,
            negative_prompt=req.negative_prompt or "",
            init_image_bytes=init_bytes,
            end_image_bytes=end_bytes,
            task=req.task,
            width=req.width,
            height=req.height,
            num_frames=req.num_frames,
            fps=req.fps,
            steps=req.steps,
            guidance_scale=req.guidance_scale,
            flow_shift=req.flow_shift,
            seed=req.seed if req.seed is not None else -1,
        )
    except Exception as e:
        log.exception("Wan 2.1 generation failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Wan 2.1 generation failed: {e}",
        )

    return VideoResponse(
        success=True,
        video_base64=base64.b64encode(mp4_bytes).decode(),
        seed=seed_used,
        num_frames=req.num_frames,
        fps=req.fps,
    )


@router.post("/minimax", response_model=VideoResponse)
def generate_minimax(req: MiniMaxRequest) -> VideoResponse:
    """MiniMax-H3 Omni Video+Audio generation endpoint."""
    from generation.video_pipeline import get_minimax_engine

    init_bytes = None
    if req.image_base64:
        raw_b64 = req.image_base64
        if "," in raw_b64:
            raw_b64 = raw_b64.split(",", 1)[1]
        try:
            init_bytes = base64.b64decode(raw_b64)
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid image_base64: {e}",
            )

    try:
        engine = get_minimax_engine()
        mp4_bytes, seed_used = engine.generate(
            prompt=req.prompt,
            init_image_bytes=init_bytes,
            duration_seconds=req.duration_seconds,
            fps=req.fps,
            steps=req.steps,
            aspect_ratio=req.aspect_ratio,
            seed=req.seed if req.seed is not None else -1,
        )
    except Exception as e:
        log.exception("MiniMax generation failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"MiniMax-H3 generation failed: {e}",
        )

    num_frames = int(req.duration_seconds * req.fps)
    return VideoResponse(
        success=True,
        video_base64=base64.b64encode(mp4_bytes).decode(),
        seed=seed_used,
        num_frames=num_frames,
        fps=req.fps,
    )


@router.post("/voice", response_model=VoiceResponse)
def generate_voice(req: VoiceRequest) -> VoiceResponse:
    """Chatterbox TTS voice generation and zero-shot voice cloning endpoint."""
    from generation.voice_pipeline import get_voice_engine

    ref_audio_bytes = None
    if req.audio_prompt_base64:
        raw_b64 = req.audio_prompt_base64
        if "," in raw_b64:
            raw_b64 = raw_b64.split(",", 1)[1]
        try:
            ref_audio_bytes = base64.b64decode(raw_b64)
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid audio_prompt_base64: {e}",
            )

    t0 = time.perf_counter()
    try:
        engine = get_voice_engine()
        wav_bytes, sample_rate, seed_used = engine.generate_audio(
            prompt=req.prompt,
            language=req.language,
            model_name=req.model_name,
            audio_prompt_bytes=ref_audio_bytes,
            exaggeration=req.exaggeration,
            cfg_weight=req.cfg_weight,
            seed=req.seed if req.seed is not None else -1,
            instruction=req.instruction,
            ref_text=req.ref_text,
        )
        elapsed_ms = int((time.perf_counter() - t0) * 1000)

        # Estimate duration from bytes (16-bit mono PCM in standard WAV: ~sample_rate * 2 bytes/sec)
        est_duration = None
        if len(wav_bytes) > 44 and sample_rate > 0:
            data_bytes = len(wav_bytes) - 44
            est_duration = round(data_bytes / (sample_rate * 2), 2)

        return VoiceResponse(
            success=True,
            audio_base64=base64.b64encode(wav_bytes).decode(),
            sample_rate=sample_rate,
            seed=seed_used,
            inference_time_ms=elapsed_ms,
            language=req.language,
            model_name=req.model_name,
            duration_seconds=est_duration,
        )
    except HTTPException:
        raise
    except Exception as e:
        log.exception("Voice generation failed: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Voice generation failed: {e}",
        )


@router.post("/tryon", response_model=TryOnResponse)
def virtual_tryon(req: TryOnRequest) -> TryOnResponse:
    """FASHN VTON v1.5 virtual try-on endpoint."""
    from generation.tryon_pipeline import get_tryon_engine

    # Parse person image
    raw_person = req.person_image_base64
    if "," in raw_person:
        raw_person = raw_person.split(",", 1)[1]
    try:
        person_bytes = base64.b64decode(raw_person)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid person_image_base64 attachment: {e}",
        )

    # Parse garment image
    raw_garment = req.garment_image_base64
    if "," in raw_garment:
        raw_garment = raw_garment.split(",", 1)[1]
    try:
        garment_bytes = base64.b64decode(raw_garment)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid garment_image_base64 attachment: {e}",
        )

    t0 = time.perf_counter()
    try:
        engine = get_tryon_engine()
        png_bytes, seed_used = engine.generate(
            person_image_bytes=person_bytes,
            garment_image_bytes=garment_bytes,
            category=req.category,
            garment_photo_type=req.garment_photo_type,
            steps=req.steps,
            guidance_scale=req.guidance_scale,
            seed=req.seed if req.seed is not None else -1,
            segmentation_free=req.segmentation_free,
        )
        elapsed_ms = int((time.perf_counter() - t0) * 1000)

        img_b64 = base64.b64encode(png_bytes).decode("utf-8")
        if not img_b64.startswith("data:image"):
            img_b64 = f"data:image/png;base64,{img_b64}"

        return TryOnResponse(
            success=True,
            image_base64=img_b64,
            seed=seed_used,
            inference_time_ms=elapsed_ms,
            width=576,
            height=864,
            category=req.category,
        )
    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    except Exception as e:
        log.exception("Virtual try-on failed: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Virtual try-on failed: {e}",
        )

