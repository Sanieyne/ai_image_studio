"""Pydantic schemas for the AI Image Studio engine (Part 3/5)."""
from __future__ import annotations

from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field


class LoraConfig(BaseModel):
    path_or_id: str
    adapter_name: Optional[str] = None
    weight: float = Field(default=0.8, ge=0.0, le=2.0)


class LoraScaleRequest(BaseModel):
    adapter_name: str
    weight: float = Field(..., ge=0.0, le=2.0)


class GenerateRequest(BaseModel):
    prompt: str = Field(..., min_length=1)
    negative_prompt: Optional[str] = (
        "low quality, bad anatomy, worst quality, blurry"
    )
    # None = not provided -> snap from width/height, else fall back to 9:16.
    aspect_ratio: Optional[str] = None
    width: Optional[int] = Field(default=None, ge=256, le=2048)
    height: Optional[int] = Field(default=None, ge=256, le=2048)
    steps: int = Field(default=30, ge=1, le=150)
    guidance_scale: float = Field(default=7.0, ge=0.0, le=20.0)
    seed: Optional[int] = -1
    loras: Optional[List[LoraConfig]] = None
    image_base64: Optional[str] = None
    strength: float = Field(default=0.65, ge=0.05, le=1.0)


class LoraInfo(BaseModel):
    path: str = ""
    weight: float = 0.0


class GenerateResponse(BaseModel):
    success: bool
    image_base64: str
    seed: int
    inference_time_ms: int
    width: int
    height: int
    aspect_ratio: str
    active_loras: Dict[str, LoraInfo]


class ModelStatusItem(BaseModel):
    modelId: str
    status: str  # queued | downloading | loading | ready | failed
    progressPercent: Optional[float] = None
    error: Optional[str] = None
    loadedInVram: Optional[bool] = None


class HealthResponse(BaseModel):
    status: str
    device: str
    device_name: Optional[str] = None
    model_loaded: bool
    current_model: Optional[str] = None
    models: List[ModelStatusItem] = []


class ModelSwitchRequest(BaseModel):
    model_id: str = Field(..., min_length=1)


class ModelItem(BaseModel):
    id: str
    label: str
    family: str
    mode: str = "image"
    is_active: bool = False
    is_downloaded: bool = False
    default_steps: int = 30
    default_guidance: float = 7.0
    gated: bool = False
    note: str = ""


class AvailableModelsResponse(BaseModel):
    active_model: Optional[str] = None
    device: str = "cuda"
    models: List[ModelItem] = []



class VideoRequest(BaseModel):
    prompt: str = Field(..., min_length=1)
    image_base64: Optional[str] = None
    num_frames: int = Field(default=49, ge=9, le=257)
    steps: int = Field(default=30, ge=1, le=100)
    seed: Optional[int] = -1
    width: int = Field(default=704, ge=256, le=1280)
    height: int = Field(default=480, ge=256, le=1280)
    fps: int = Field(default=24, ge=8, le=60)


class VideoResponse(BaseModel):
    success: bool
    video_base64: str
    seed: int
    num_frames: int
    fps: int


class AnimateRequest(BaseModel):
    image_base64: str = Field(..., min_length=1, description="Character reference image")
    template_video_base64: Optional[str] = Field(None, description="Optional driving motion video")
    prompt: Optional[str] = "人物动作的参考视频"
    num_frames: int = Field(default=17, ge=9, le=257)
    steps: int = Field(default=4, ge=1, le=40)
    sample_guide_scale: float = Field(default=1.0, ge=0.0, le=10.0)
    seed: Optional[int] = -1
    width: int = Field(default=480, ge=256, le=1280)
    height: int = Field(default=640, ge=256, le=1280)
    fps: int = Field(default=24, ge=8, le=60)


class VoiceRequest(BaseModel):
    prompt: str = Field(..., min_length=1, description="Text to synthesize as voice/speech")
    model_name: Optional[str] = Field(default="ResembleAI/chatterbox", description="Voice model identifier")
    language: str = Field(default="en", description="Language code for synthesis (en, es, fr, de, zh, ja, etc.)")
    audio_prompt_base64: Optional[str] = Field(None, description="Audio reference clip for zero-shot voice cloning")
    instruction: Optional[str] = Field(None, description="Voice design instruction or direction for Breeze TTS 2")
    ref_text: Optional[str] = Field(None, description="Transcript of the reference audio for voice cloning/direction")
    exaggeration: float = Field(default=0.5, ge=0.0, le=2.0, description="Emotion expressiveness (0.0 to 1.0+)")
    cfg_weight: float = Field(default=0.5, ge=0.0, le=10.0, description="Classifier-Free Guidance weight")
    seed: Optional[int] = -1


class VoiceResponse(BaseModel):
    success: bool = True
    audio_base64: str
    sample_rate: int = 24000
    seed: int = -1
    inference_time_ms: int = 0
    language: str = "en"
    model_name: Optional[str] = None
    duration_seconds: Optional[float] = None


class MiniMaxRequest(BaseModel):
    prompt: str = Field(..., min_length=1, description="Prompt describing scene, motion, dialogue, and sound effects")
    image_base64: Optional[str] = Field(None, description="Optional starting keyframe image for Image-to-Video generation")
    duration_seconds: int = Field(default=5, ge=4, le=15, description="Video duration in seconds (4-15s)")
    fps: int = Field(default=24, ge=12, le=30)
    aspect_ratio: str = Field(default="16:9")
    steps: int = Field(default=30, ge=10, le=50)
    seed: Optional[int] = -1


class TryOnRequest(BaseModel):
    person_image_base64: str = Field(..., description="Base64 encoded image of the person")
    garment_image_base64: str = Field(..., description="Base64 encoded image of the garment/clothing")
    category: str = Field(default="tops", description="'tops' | 'bottoms' | 'one-pieces'")
    garment_photo_type: str = Field(default="model", description="'model' | 'flat-lay'")
    steps: int = Field(default=30, ge=10, le=50)
    guidance_scale: float = Field(default=1.5, ge=1.0, le=5.0)
    seed: Optional[int] = -1
    segmentation_free: bool = Field(default=True, description="Maskless try-on for natural drape")


class TryOnResponse(BaseModel):
    success: bool = True
    image_base64: str
    seed: int = -1
    inference_time_ms: int = 0
    width: int = 576
    height: int = 864
    category: str = "tops"


class Wan2_1Request(BaseModel):
    prompt: str = Field(..., min_length=1, description="Prompt describing the scene and motion")
    negative_prompt: Optional[str] = Field(
        default="Bright tones, overexposed, static, blurred details, subtitles, style, works, paintings, images, static, overall gray, worst quality, low quality, JPEG compression residue, ugly, incomplete, extra fingers, poorly drawn hands, poorly drawn faces, deformed, disfigured, misshapen limbs, fused fingers, still picture, messy background, three legs, many people in the background, walking backwards",
        description="Negative prompt to guide generation away from artifacts",
    )
    image_base64: Optional[str] = Field(None, description="Input starting image for I2V or first frame for FLF2V")
    end_image_base64: Optional[str] = Field(None, description="Optional last frame image for FLF2V transition")
    task: str = Field(default="t2v-1.3B", description="'t2v-1.3B' | 't2v-14B' | 'i2v-14B' | 'flf2v-14B'")
    width: int = Field(default=832, ge=256, le=1280)
    height: int = Field(default=480, ge=256, le=1280)
    num_frames: int = Field(default=81, ge=9, le=257)
    fps: int = Field(default=16, ge=8, le=30)
    steps: int = Field(default=30, ge=10, le=50)
    guidance_scale: float = Field(default=5.0, ge=1.0, le=12.0)
    flow_shift: float = Field(default=3.0, ge=1.0, le=12.0)
    seed: Optional[int] = -1


class EnhanceRequest(BaseModel):
    image_base64: str = Field(..., description="Base64-encoded source image to enhance/upscale")
    model_name: str = Field(default="amd/realesrgan-x4plus", description="Model identifier: amd/realesrgan-x4plus or anime-6b")
    scale: int = Field(default=4, ge=2, le=4, description="Target upscale factor: 2 or 4")
    face_enhance: bool = Field(default=False, description="Enable GFPGAN facial restoration")
    denoise_strength: float = Field(default=0.5, ge=0.0, le=1.0, description="Denoise strength for cleaning artifacts")


class EnhanceResponse(BaseModel):
    success: bool = True
    image_base64: str
    width: int
    height: int
    original_width: int
    original_height: int
    scale: int = 4
    model_name: str = "amd/realesrgan-x4plus"
    inference_time_ms: int = 0


class CameraFaceMetrics(BaseModel):
    bbox: List[int]
    score: float
    area_ratio: float
    offset_x: float
    offset_y: float
    width: int
    height: int


class CameraFrameResponse(BaseModel):
    success: bool
    image_base64: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    faces_count: int = 0
    feedback_code: str
    feedback_text: str
    can_capture: bool
    face_metrics: Optional[CameraFaceMetrics] = None
    error: Optional[str] = None


class CameraCaptureResponse(BaseModel):
    success: bool
    file_path: Optional[str] = ""
    file_name: Optional[str] = ""
    timestamp: Optional[str] = ""
    width: Optional[int] = 0
    height: Optional[int] = 0
    feedback_code: str
    feedback_text: str
    can_capture: bool
    face_metrics: Optional[CameraFaceMetrics] = None
    image_base64: Optional[str] = None
    error: Optional[str] = None


class CameraReleaseResponse(BaseModel):
    released: bool
    message: str


class CameraStatusResponse(BaseModel):
    active: bool
    source: Optional[str] = None
    is_mock_feed: bool = False
    idle_seconds: Optional[float] = None
    inactivity_timeout: float = 5.0


class LiveCamStartRequest(BaseModel):
    camera_index: int = 0
    source_image_path: Optional[str] = None
    enhance: bool = False
    mirror: bool = True


class LiveCamSetSourceRequest(BaseModel):
    source_image_path: Optional[str] = None
    preset_name: Optional[str] = None
    image_base64: Optional[str] = None


class LiveCamResponse(BaseModel):
    success: bool
    message: str
    active: bool = False
    source_name: Optional[str] = None
    stream_url: Optional[str] = None


class LiveCamFrameResponse(BaseModel):
    active: bool
    fps: float
    source_name: str
    enhance_face: bool = False
    mirror: bool = True
    frame_base64: Optional[str] = None
    message: Optional[str] = None


class LiveCamPresetItem(BaseModel):
    name: str
    filename: str
    path: str


class LiveCamPresetsResponse(BaseModel):
    presets: List[LiveCamPresetItem]


class LiveCamProcessFrameRequest(BaseModel):
    frame_base64: str = Field(..., description="Base64 encoded JPEG/PNG camera frame from client")
    source_image_base64: Optional[str] = Field(default=None, description="Optional custom target face base64")
    preset_name: Optional[str] = Field(default=None, description="Optional preset name e.g. Elon Musk")
    enhance: bool = Field(default=False, description="Enable GFPGAN facial enhancement")
    mirror: bool = Field(default=False, description="Mirror horizontal axis")


class LiveCamProcessFrameResponse(BaseModel):
    success: bool
    frame_base64: Optional[str] = None
    fps: float = 0.0
    latency_ms: float = 0.0
    faces_detected: int = 0
    source_name: Optional[str] = None
    message: Optional[str] = None


class FaceSwapImageRequest(BaseModel):
    target_image_base64: str = Field(..., description="Base64 encoded target image to swap face onto")
    source_image_base64: Optional[str] = Field(default=None, description="Base64 encoded source face image")
    preset_name: Optional[str] = Field(default=None, description="Preset name e.g. Elon Musk")
    enhance: bool = Field(default=True, description="Apply GFPGAN facial enhancement")


class FaceSwapImageResponse(BaseModel):
    success: bool
    image_base64: Optional[str] = None
    faces_swapped: int = 0
    similarity_percent: float = 0.0
    verified: bool = False
    elapsed_seconds: float = 0.0
    message: Optional[str] = None


class FaceSwapVideoRequest(BaseModel):
    target_video_base64: str = Field(..., description="Base64 encoded target MP4 video")
    source_image_base64: Optional[str] = Field(default=None, description="Base64 encoded source face image")
    preset_name: Optional[str] = Field(default=None, description="Preset name e.g. Elon Musk")
    enhance: bool = Field(default=True, description="Apply GFPGAN facial enhancement")
    max_frames: Optional[int] = Field(default=None, description="Optional cap on frames to process")


class FaceSwapVideoResponse(BaseModel):
    success: bool
    video_base64: Optional[str] = None
    frames_processed: int = 0
    fps: float = 0.0
    elapsed_seconds: float = 0.0
    message: Optional[str] = None


class FaceExtractRequest(BaseModel):
    image_base64: str = Field(..., description="Base64 encoded face photo or selfie")


class FaceExtractResponse(BaseModel):
    success: bool
    embedding: List[float] = []
    bbox: List[int] = []
    kps: List[Any] = []
    gender: Optional[str] = None
    age: Optional[int] = None
    cropped_face_base64: Optional[str] = None
    message: Optional[str] = None


class FaceVerifyRequest(BaseModel):
    image1_base64: str = Field(..., description="Base64 encoded first face image")
    image2_base64: str = Field(..., description="Base64 encoded second face image")


class FaceVerifyResponse(BaseModel):
    success: bool
    match: bool = False
    similarity_percent: float = 0.0
    cosine_distance: float = 1.0
    threshold: float = 0.35
    message: Optional[str] = None


