"""Pydantic schemas for the AI Image Studio engine (Part 3/5)."""
from __future__ import annotations

from typing import Dict, List, Optional
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
    guidance_scale: float = Field(default=7.0, ge=1.0, le=20.0)
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


class HealthResponse(BaseModel):
    status: str
    device: str
    model_loaded: bool
    current_model: Optional[str] = None


class ModelSwitchRequest(BaseModel):
    model_id: str = Field(..., min_length=1)

