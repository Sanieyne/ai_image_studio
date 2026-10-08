"""FASHN VTON v1.5 virtual try-on pipeline.

Powered by FASHN AI MMDiT pixel-space virtual try-on architecture:
- Directly generates photorealistic images in pixel space (576x864)
- Maskless / segmentation-free by default for natural garment draping
- Preserves body characteristics, tattoos, and identity
- Only ~972M parameters (~2GB weights), lightweight (~8GB VRAM)
"""
from __future__ import annotations

import base64
import io
import logging
import os
import random
import time
from typing import Optional, Tuple

try:
    import torch
except ImportError:
    torch = None

from PIL import Image, ImageDraw, ImageFont

log = logging.getLogger(__name__)

SUPPORTED_CATEGORIES = ("tops", "bottoms", "one-pieces")
GARMENT_PHOTO_TYPES = ("model", "flat-lay")


def _create_mock_tryon(
    person_img: Optional[Image.Image],
    garment_img: Optional[Image.Image],
    category: str = "tops",
    width: int = 576,
    height: int = 864,
) -> Image.Image:
    """Generate a clean visual placeholder composite for mock mode."""
    canvas = Image.new("RGB", (width, height), color=(30, 32, 40))
    draw = ImageDraw.Draw(canvas)

    # Accent header
    draw.rectangle([(0, 0), (width, 60)], fill=(45, 50, 65))
    draw.text(
        (20, 20),
        f"[MOCK] FASHN VTON v1.5 Try-On ({category.upper()})",
        fill=(120, 220, 180),
    )

    # If person image is provided, paste thumbnail
    if person_img:
        p_thumb = person_img.copy()
        p_thumb.thumbnail((width // 2 - 30, height // 2))
        canvas.paste(p_thumb, (20, 80))
        draw.text((20, 80 + p_thumb.height + 10), "Person Input", fill=(180, 180, 180))

    # If garment image is provided, paste thumbnail
    if garment_img:
        g_thumb = garment_img.copy()
        g_thumb.thumbnail((width // 2 - 30, height // 2))
        canvas.paste(g_thumb, (width // 2 + 10, 80))
        draw.text((width // 2 + 10, 80 + g_thumb.height + 10), "Garment Input", fill=(180, 180, 180))

    # Simulated result box
    box_top = height // 2 + 80
    draw.rounded_rectangle(
        [(20, box_top), (width - 20, height - 30)],
        radius=12,
        fill=(40, 44, 56),
        outline=(80, 90, 120),
        width=2,
    )
    draw.text(
        (width // 2 - 120, box_top + 40),
        f"Simulated Virtual Try-On ({category})\nResolution: {width}x{height}\nFASHN VTON 1.5 Pixel Space",
        fill=(220, 220, 220),
    )
    return canvas


class TryOnEngine:
    """FASHN VTON v1.5 TryOn Engine."""

    def __init__(self, weights_dir: Optional[str] = None):
        self.mock_mode = os.getenv("AI_STUDIO_MOCK", "0") == "1"
        self.pipeline = None
        from generation.model_paths import model_dir

        downloaded = model_dir("fashn-vton-1.5")
        self.weights_dir = weights_dir or os.getenv("FASHN_WEIGHTS_DIR") or (
            str(downloaded) if downloaded else "/root/models/fashn-vton"
        )
        if not os.path.exists(self.weights_dir):
            # Also check workspace or fallback path
            alt_path = "/workspace/models/fashn-vton"
            if os.path.exists(alt_path):
                self.weights_dir = alt_path

        if self.mock_mode:
            print("[*] TryOnEngine running in MOCK mode (AI_STUDIO_MOCK=1).")
            return

        self._ensure_loaded()

    def _ensure_loaded(self) -> None:
        if self.pipeline is not None or self.mock_mode:
            return

        try:
            from fashn_vton import TryOnPipeline
            from generation.device import get_device
            device_type, _ = get_device()
            target_device = device_type if device_type in ("cuda", "mps") else "cpu"
            print(f"[*] Loading FASHN VTON v1.5 from '{self.weights_dir}' on {target_device}...")
            self.pipeline = TryOnPipeline(weights_dir=self.weights_dir, device=target_device)
            print(f"[OK] FASHN VTON v1.5 pipeline ready on {target_device}.")
        except Exception as e:
            log.warning("[!] Could not load real FASHN VTON v1.5 pipeline: %s. Falling back to mock mode.", e)
            self.mock_mode = True

    def generate(
        self,
        person_image_bytes: bytes,
        garment_image_bytes: bytes,
        category: str = "tops",
        garment_photo_type: str = "model",
        steps: int = 30,
        guidance_scale: float = 1.5,
        seed: int = -1,
        segmentation_free: bool = True,
    ) -> Tuple[bytes, int]:
        """Run virtual try-on given person and garment image bytes."""
        if category not in SUPPORTED_CATEGORIES:
            category = "tops"
        if garment_photo_type not in GARMENT_PHOTO_TYPES:
            garment_photo_type = "model"

        if seed == -1:
            seed = random.randint(1, 2**31 - 1)

        person_pil = None
        if person_image_bytes:
            try:
                person_pil = Image.open(io.BytesIO(person_image_bytes)).convert("RGB")
            except Exception as e:
                raise ValueError(f"Invalid person image: {e}")

        garment_pil = None
        if garment_image_bytes:
            try:
                garment_pil = Image.open(io.BytesIO(garment_image_bytes)).convert("RGB")
            except Exception as e:
                raise ValueError(f"Invalid garment image: {e}")

        if not person_pil or not garment_pil:
            raise ValueError("Both person_image and garment_image are required for virtual try-on.")

        if self.mock_mode or self.pipeline is None:
            mock_img = _create_mock_tryon(
                person_img=person_pil,
                garment_img=garment_pil,
                category=category,
                width=576,
                height=864,
            )
            buf = io.BytesIO()
            mock_img.save(buf, format="PNG")
            return buf.getvalue(), seed

        # Real GPU inference
        kwargs = {
            "person_image": person_pil,
            "garment_image": garment_pil,
            "category": category,
            "garment_photo_type": garment_photo_type,
            "num_timesteps": steps,
            "guidance_scale": guidance_scale,
            "seed": seed,
            "segmentation_free": segmentation_free,
        }
        result = self.pipeline(**kwargs)
        output_image = result.images[0]

        buf = io.BytesIO()
        output_image.save(buf, format="PNG")
        return buf.getvalue(), seed


_engine: Optional[TryOnEngine] = None


def get_tryon_engine() -> TryOnEngine:
    global _engine
    if _engine is None:
        _engine = TryOnEngine()
    return _engine
