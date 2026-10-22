"""HTTP routes: generation + LoRA management (Part 3/5)."""
from __future__ import annotations

import base64
import io
import logging
import os
import time
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import StreamingResponse
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
    EnhanceRequest,
    EnhanceResponse,
    AvailableModelsResponse,
    ModelItem,
    CameraFaceMetrics,
    CameraFrameResponse,
    CameraCaptureResponse,
    CameraReleaseResponse,
    CameraStatusResponse,
    LiveCamStartRequest,
    LiveCamSetSourceRequest,
    LiveCamResponse,
    LiveCamFrameResponse,
    LiveCamPresetItem,
    LiveCamPresetsResponse,
    LiveCamProcessFrameRequest,
    LiveCamProcessFrameResponse,
    FaceSwapImageRequest,
    FaceSwapImageResponse,
    FaceSwapVideoRequest,
    FaceSwapVideoResponse,
    FaceExtractRequest,
    FaceExtractResponse,
    FaceVerifyRequest,
    FaceVerifyResponse,
)

from generation.pipeline import (
    ASPECT_RATIO_BUCKETS,
    get_pipeline,
    nearest_bucket,
    peek_pipeline,
)

log = logging.getLogger(__name__)
router = APIRouter()


@router.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    from generation.device import get_device, get_device_name
    from generation.model_status import model_status_manager
    dev, _ = get_device()
    models_status = model_status_manager.get_all_statuses()
    has_any_ready = any(m.get("status") == "ready" for m in models_status)
    current_model = None
    pipe_loaded = False

    # Never create or load a pipeline here: /health must answer at once.
    pipe = peek_pipeline()
    if pipe is not None:
        pipe_loaded = getattr(pipe, "model_loaded", False)
        if pipe_loaded:
            current_model = pipe.current_model

    if not current_model and models_status:
        current_model = model_status_manager.get_first_ready_model_id()

    is_loaded = has_any_ready or pipe_loaded
    status_str = "ok" if is_loaded else ("ok-mock" if os.environ.get("AI_STUDIO_MOCK", "0") == "1" else "ok-standby")

    return HealthResponse(
        status=status_str,
        device=dev,
        device_name=get_device_name(),
        model_loaded=is_loaded,
        current_model=current_model,
        models=models_status,
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


@router.get("/models/available", response_model=AvailableModelsResponse)
@router.get("/models", response_model=AvailableModelsResponse)
def get_available_models_endpoint() -> AvailableModelsResponse:
    from generation.model_registry import get_available_models
    pipe = get_pipeline()
    active_id = getattr(pipe, "current_model", None)
    models_list = get_available_models(active_model_id=active_id)
    return AvailableModelsResponse(
        active_model=active_id,
        device=getattr(pipe, "device", "cuda"),
        models=[ModelItem(**m) for m in models_list],
    )



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


@router.post("/enhance", response_model=EnhanceResponse)
def enhance_image(req: EnhanceRequest) -> EnhanceResponse:
    """Real-ESRGAN x4plus AI Image Enhancement & Super-Resolution endpoint."""
    from generation.enhancer_pipeline import get_enhancer_engine

    raw_img = req.image_base64
    if "," in raw_img:
        raw_img = raw_img.split(",", 1)[1]
    try:
        img_bytes = base64.b64decode(raw_img)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid image_base64 attachment: {e}",
        )

    t0 = time.perf_counter()
    try:
        engine = get_enhancer_engine()
        png_bytes, w, h, orig_w, orig_h = engine.enhance(
            image_bytes=img_bytes,
            scale=req.scale,
            model_name=req.model_name,
            face_enhance=req.face_enhance,
            denoise_strength=req.denoise_strength,
        )
        elapsed_ms = int((time.perf_counter() - t0) * 1000)

        img_b64 = base64.b64encode(png_bytes).decode("utf-8")
        if not img_b64.startswith("data:image"):
            img_b64 = f"data:image/png;base64,{img_b64}"

        return EnhanceResponse(
            success=True,
            image_base64=img_b64,
            width=w,
            height=h,
            original_width=orig_w,
            original_height=orig_h,
            scale=req.scale,
            model_name=req.model_name,
            inference_time_ms=elapsed_ms,
        )
    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    except Exception as e:
        log.exception("Image enhancement failed: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Image enhancement failed: {e}",
        )


# =========================================================================
# Camera Capture & Live Framing Endpoints
# =========================================================================

@router.get("/api/camera/frame", response_model=CameraFrameResponse)
def get_camera_frame(seek_frame: Optional[int] = None) -> CameraFrameResponse:
    """Acquire the latest camera frame and return InsightFace framing evaluation."""
    try:
        from generation.camera_service import get_camera_service
        service = get_camera_service()
        data = service.get_frame_and_eval(seek_frame=seek_frame)
        return CameraFrameResponse(**data)
    except Exception as e:
        log.exception("Camera frame evaluation error: %s", e)
        return CameraFrameResponse(
            success=False,
            feedback_code="camera_error",
            feedback_text=f"Camera error: {e}",
            can_capture=False,
            error=str(e),
        )


@router.post("/api/camera/capture", response_model=CameraCaptureResponse)
def capture_camera_frame(seek_frame: Optional[int] = None) -> CameraCaptureResponse:
    """Capture a confirmed high-quality frame and save it to staging directory."""
    try:
        from generation.camera_service import get_camera_service
        service = get_camera_service()
        data = service.capture_confirmed_frame(seek_frame=seek_frame)
        return CameraCaptureResponse(**data)
    except Exception as e:
        log.exception("Camera capture error: %s", e)
        return CameraCaptureResponse(
            success=False,
            file_path="",
            file_name="",
            timestamp="",
            width=0,
            height=0,
            feedback_code="camera_error",
            feedback_text=f"Failed to capture frame: {e}",
            can_capture=False,
            error=str(e),
        )


@router.post("/api/camera/release", response_model=CameraReleaseResponse)
def release_camera() -> CameraReleaseResponse:
    """Explicitly release the camera hardware handle."""
    try:
        from generation.camera_service import get_camera_service
        service = get_camera_service()
        data = service.release()
        return CameraReleaseResponse(**data)
    except Exception as e:
        return CameraReleaseResponse(released=False, message=str(e))


@router.get("/api/camera/status", response_model=CameraStatusResponse)
def get_camera_status() -> CameraStatusResponse:
    """Check the current camera hardware capture and watchdog status."""
    try:
        from generation.camera_service import get_camera_service
        service = get_camera_service()
        data = service.get_status()
        return CameraStatusResponse(**data)
    except Exception as e:
        return CameraStatusResponse(active=False, source=None, is_mock_feed=False, idle_seconds=None)


# =========================================================================
# Live Video Call DeepFace (Deep-Live-Cam clone) API Endpoints
# =========================================================================

@router.post("/api/live-cam/start", response_model=LiveCamResponse)
def start_live_cam(req: LiveCamStartRequest) -> LiveCamResponse:
    """Start real-time face cloning stream from webcam feed."""
    try:
        from generation.live_face_swap import get_live_face_swap_service
        service = get_live_face_swap_service()
        res = service.start(
            camera_index=req.camera_index,
            source_image_path=req.source_image_path,
            enhance=req.enhance,
            mirror=req.mirror,
        )
        return LiveCamResponse(
            success=res.get("success", True),
            message=res.get("message", "Live webcam deepface engine started."),
            active=service.is_running,
            source_name=service.source_name,
            stream_url="/api/live-cam/stream.mjpg",
        )
    except Exception as e:
        log.exception(f"Error starting live cam: {e}")
        return LiveCamResponse(
            success=False,
            message=f"Failed to start live cam: {e}",
            active=False,
            source_name=None,
            stream_url=None,
        )


@router.post("/api/live-cam/stop", response_model=LiveCamResponse)
def stop_live_cam() -> LiveCamResponse:
    """Stop real-time face cloning stream and release camera."""
    try:
        from generation.live_face_swap import get_live_face_swap_service
        service = get_live_face_swap_service()
        res = service.stop()
        return LiveCamResponse(
            success=res.get("success", True),
            message=res.get("message", "Live face swap stopped."),
            active=False,
            source_name=service.source_name,
        )
    except Exception as e:
        log.exception(f"Error stopping live cam: {e}")
        return LiveCamResponse(
            success=False,
            message=f"Failed to stop live cam: {e}",
            active=False,
        )


@router.get("/api/live-cam/status", response_model=LiveCamResponse)
def get_live_cam_status() -> LiveCamResponse:
    """Check current live cam streaming status."""
    try:
        from generation.live_face_swap import get_live_face_swap_service
        service = get_live_face_swap_service()
        return LiveCamResponse(
            success=True,
            message="Live cam active" if service.is_running else "Live cam standby",
            active=service.is_running,
            source_name=service.source_name,
            stream_url="/api/live-cam/stream.mjpg" if service.is_running else None,
        )
    except Exception as e:
        return LiveCamResponse(success=False, message=str(e), active=False)


@router.post("/api/live-cam/set-source", response_model=LiveCamResponse)
def set_live_cam_source(req: LiveCamSetSourceRequest) -> LiveCamResponse:
    """Switch active clone target on the fly during a live call."""
    try:
        from generation.live_face_swap import get_live_face_swap_service
        service = get_live_face_swap_service()

        if req.preset_name:
            presets = service.get_available_presets()
            match = next((p for p in presets if req.preset_name.lower() in p["name"].lower()), None)
            if match:
                service.set_source_image(match["path"], name=match["name"])
                return LiveCamResponse(
                    success=True,
                    message=f"Switched clone target to {match['name']}",
                    active=service.is_running,
                    source_name=service.source_name,
                )

        if req.source_image_path:
            ok = service.set_source_image(req.source_image_path)
            return LiveCamResponse(
                success=ok,
                message=f"Switched clone target to {service.source_name}" if ok else "Failed to find face in image",
                active=service.is_running,
                source_name=service.source_name,
            )

        if req.image_base64:
            clean_b64 = req.image_base64
            if "," in clean_b64:
                clean_b64 = clean_b64.split(",", 1)[1]
            raw_bytes = base64.b64decode(clean_b64)
            name = req.name or req.preset_name or "Custom Upload"
            ok = service.set_source_image(raw_bytes, name=name)
            return LiveCamResponse(
                success=ok,
                message=f"Switched clone target to '{service.source_name}'" if ok else "No face detected in upload",
                active=service.is_running,
                source_name=service.source_name,
            )

        return LiveCamResponse(success=False, message="No source image or preset provided.", active=service.is_running)
    except Exception as e:
        log.exception(f"Error setting live cam source: {e}")
        return LiveCamResponse(success=False, message=str(e), active=False)


@router.get("/api/live-cam/frame", response_model=LiveCamFrameResponse)
def get_live_cam_frame() -> LiveCamFrameResponse:
    """Acquire latest swapped live video frame with telemetry for UI preview."""
    try:
        from generation.live_face_swap import get_live_face_swap_service
        service = get_live_face_swap_service()
        data = service.get_latest_frame()
        return LiveCamFrameResponse(**data)
    except Exception as e:
        log.exception(f"Error fetching live frame: {e}")
        return LiveCamFrameResponse(
            active=False,
            fps=0.0,
            source_name="None",
            enhance_face=False,
            mirror=True,
            frame_base64=None,
            message=str(e),
        )


@router.get("/api/live-cam/presets", response_model=LiveCamPresetsResponse)
def get_live_cam_presets() -> LiveCamPresetsResponse:
    """List celebrity and preloaded clone target face presets."""
    try:
        from generation.live_face_swap import get_live_face_swap_service
        service = get_live_face_swap_service()
        presets = service.get_available_presets()
        items = [LiveCamPresetItem(**p) for p in presets]
        return LiveCamPresetsResponse(presets=items)
    except Exception as e:
        return LiveCamPresetsResponse(presets=[])


@router.get("/api/live-cam/stream.mjpg")
def get_live_cam_mjpeg_stream():
    """Stream live multipart MJPEG feed for browsers, OBS, and web video calls."""
    try:
        from generation.live_face_swap import get_live_face_swap_service
        service = get_live_face_swap_service()
        if not service.is_running:
            service.start()
        return StreamingResponse(
            service.generate_mjpeg_stream(),
            media_type="multipart/x-mixed-replace; boundary=frame",
        )
    except Exception as e:
        log.exception(f"Streaming error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/live-cam/process-frame", response_model=LiveCamProcessFrameResponse)
def process_client_live_cam_frame(req: LiveCamProcessFrameRequest) -> LiveCamProcessFrameResponse:
    """Process a single incoming camera frame from a remote client (e.g. Flutter webcam over HTTP)."""
    try:
        from generation.live_face_swap import get_live_face_swap_service
        service = get_live_face_swap_service()
        res = service.process_client_frame(
            frame_data=req.frame_base64,
            source_image_or_preset=req.source_image_base64 or req.preset_name,
            enhance=req.enhance,
            mirror=req.mirror,
        )
        return LiveCamProcessFrameResponse(**res)
    except Exception as e:
        log.exception(f"Error processing client frame: {e}")
        return LiveCamProcessFrameResponse(success=False, message=str(e))


@router.post("/api/live-cam/swap-image", response_model=FaceSwapImageResponse)
def swap_face_in_image(req: FaceSwapImageRequest) -> FaceSwapImageResponse:
    """High-resolution face swap on a target image with GFPGAN restoration and verification."""
    try:
        from generation.live_face_swap import get_live_face_swap_service
        service = get_live_face_swap_service()
        res = service.swap_image(
            target_image=req.target_image_base64,
            source_image=req.source_image_base64,
            preset_name=req.preset_name,
            enhance=req.enhance,
        )
        return FaceSwapImageResponse(**res)
    except Exception as e:
        log.exception(f"Error in image face swap: {e}")
        return FaceSwapImageResponse(success=False, message=str(e))


@router.post("/api/live-cam/swap-video", response_model=FaceSwapVideoResponse)
def swap_face_in_video(req: FaceSwapVideoRequest) -> FaceSwapVideoResponse:
    """Video face swap across all frames with original audio preserved."""
    try:
        from generation.live_face_swap import get_live_face_swap_service
        service = get_live_face_swap_service()
        res = service.swap_video(
            target_video_data=req.target_video_base64,
            source_image=req.source_image_base64,
            preset_name=req.preset_name,
            enhance=req.enhance,
            max_frames=req.max_frames,
        )
        return FaceSwapVideoResponse(**res)
    except Exception as e:
        log.exception(f"Error in video face swap: {e}")
        return FaceSwapVideoResponse(success=False, message=str(e))


@router.post("/api/face/extract", response_model=FaceExtractResponse)
def extract_face_identity(req: FaceExtractRequest) -> FaceExtractResponse:
    """Extract normalized 512-dim face embedding and aligned cropped face from photo or selfie."""
    try:
        from generation.live_face_swap import get_live_face_swap_service
        service = get_live_face_swap_service()
        res = service.extract_face(req.image_base64)
        return FaceExtractResponse(**res)
    except Exception as e:
        log.exception(f"Error extracting face embedding: {e}")
        return FaceExtractResponse(success=False, message=str(e))


@router.post("/api/face/verify", response_model=FaceVerifyResponse)
def verify_face_similarity(req: FaceVerifyRequest) -> FaceVerifyResponse:
    """Verify facial similarity between two faces using ArcFace/DeepFace cosine metric."""
    try:
        from generation.live_face_swap import get_live_face_swap_service
        service = get_live_face_swap_service()
        res = service.verify_faces(req.image1_base64, req.image2_base64)
        return FaceVerifyResponse(**res)
    except Exception as e:
        log.exception(f"Error verifying faces: {e}")
        return FaceVerifyResponse(success=False, message=str(e))





