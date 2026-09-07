"""SDXL image pipeline: real weights on CUDA/CPU + mock fallback.

Part 1/5 core engine:
- CUDA autodetect: torch.float16 on GPU, torch.float32 on CPU.
- StableDiffusionXLPipeline with use_safetensors (+ fp16 variant on CUDA).
- VRAM savers on CUDA: enable_model_cpu_offload() + enable_vae_tiling().
- Native 1MP aspect-ratio buckets; generate() returns a PIL Image.
- AI_STUDIO_MOCK=1 skips weights and draws a labeled placeholder.

The serving adapter (ImagePipeline) preserves the existing
generate(...) -> (base64, seed, elapsed) contract used by api/routes.py
and the Flutter app: it snaps requested dimensions to the nearest
bucket and base64-encodes the PIL result.
"""
from __future__ import annotations

import base64
import io
import logging
import os
import random
import time
from typing import Dict, List, Optional

try:
    import torch
except ImportError:  # mock mode works without torch installed
    torch = None  # type: ignore[assignment]
from PIL import Image, ImageDraw

from config.config import settings
from generation.model_registry import defaults_for, family_for

log = logging.getLogger(__name__)

MODEL_ID = "stabilityai/stable-diffusion-xl-base-1.0"

# SDXL native 1-megapixel training resolutions.
ASPECT_RATIO_BUCKETS = {
    "1:1": (1024, 1024),
    "16:9": (1344, 768),
    "9:16": (768, 1344),
    "4:5": (896, 1152),
    "21:9": (1536, 640),
}


class SDXLEngine:
    """Core SDXL engine (Part 1/5). Loads weights, renders PIL images."""

    def __init__(self, model_id: str = MODEL_ID):
        self.mock_mode = os.getenv("AI_STUDIO_MOCK", "0") == "1"
        cuda = torch is not None and torch.cuda.is_available()
        self.device = "cuda" if cuda else "cpu"
        self.torch_dtype = (
            torch.float16
            if (torch is not None and self.device == "cuda")
            else (torch.float32 if torch is not None else None)
        )
        self.pipe = None
        self.img2img_pipe = None
        self.family = family_for(model_id)
        # State tracking: {adapter_name: {"path": str, "weight": float}}
        self.active_loras: Dict[str, dict] = {}
        self.current_model_id = model_id

        if model_id == MODEL_ID and settings.model_id != MODEL_ID:
            model_id = settings.model_id
            self.current_model_id = model_id

        if self.mock_mode:
            print("[*] Running in MOCK MODE (AI_STUDIO_MOCK=1). "
                  "No weights loaded.")
            return

        self._load_pipeline(model_id)

    def _load_pipeline(self, model_id: str) -> None:
        self.family = family_for(model_id)
        hf_token = os.environ.get("HF_TOKEN") or None
        if self.family == "flux":
            self._load_flux_pipeline(model_id, hf_token)
        else:
            self._load_sdxl_pipeline(model_id, hf_token)
        self.current_model_id = model_id

    def _load_sdxl_pipeline(self, model_id: str, hf_token=None) -> None:
        from diffusers import StableDiffusionXLPipeline

        print(f"[*] Loading SDXL model '{model_id}' onto "
              f"{self.device} ({self.torch_dtype})...")

        if os.path.isfile(model_id):
            print(f"[*] Loading single-file checkpoint from disk: {model_id}")
            self.pipe = StableDiffusionXLPipeline.from_single_file(
                model_id,
                torch_dtype=self.torch_dtype,
                use_safetensors=True,
            )
        else:
            self.pipe = StableDiffusionXLPipeline.from_pretrained(
                model_id,
                torch_dtype=self.torch_dtype,
                use_safetensors=True,
                variant="fp16" if self.device == "cuda" else None,
                token=hf_token,
            )

        if self.device == "cuda":
            total_vram_gb = (
                torch.cuda.get_device_properties(0).total_memory / (1024**3)
            )
            # Full GPU speed on >=16GB VRAM (e.g. RTX 3090/4090); offload on <=12GB.
            if total_vram_gb < 16 or os.environ.get("FORCE_CPU_OFFLOAD") == "1":
                print(f"[*] VRAM ({total_vram_gb:.1f} GB) < 16GB: enabling CPU offload.")
                self.pipe.enable_model_cpu_offload()
            else:
                print(f"[*] High VRAM ({total_vram_gb:.1f} GB): loading directly into CUDA.")
                self.pipe.to("cuda")

            if hasattr(self.pipe, "enable_vae_tiling"):
                self.pipe.enable_vae_tiling()
            elif hasattr(self.pipe, "vae") and hasattr(self.pipe.vae, "enable_tiling"):
                self.pipe.vae.enable_tiling()
        else:
            self.pipe.to("cpu")

        print(f"[OK] SDXL pipeline ready with '{model_id}'.")

    def _load_flux_pipeline(self, model_id: str, hf_token=None) -> None:
        """FLUX.1 (12B) needs bfloat16 + CPU offload to fit 24GB VRAM."""
        from diffusers import FluxPipeline

        dtype = torch.bfloat16 if self.device == "cuda" else torch.float32
        print(f"[*] Loading FLUX model '{model_id}' ({dtype})...")
        if os.path.isfile(model_id):
            self.pipe = FluxPipeline.from_single_file(
                model_id, torch_dtype=dtype, use_safetensors=True)
        else:
            self.pipe = FluxPipeline.from_pretrained(
                model_id, torch_dtype=dtype, token=hf_token)
        if self.device == "cuda":
            # 12B params: offload is mandatory on 24GB, tiling for 4K.
            self.pipe.enable_model_cpu_offload()
            try:
                self.pipe.vae.enable_tiling()
                self.pipe.vae.enable_slicing()
            except Exception:
                pass
        print(f"[OK] FLUX pipeline ready with '{model_id}'.")

    def switch_model(self, model_id: str) -> str:
        """Dynamically unload current model and load a new one."""
        model_id = model_id.strip()
        if not model_id:
            raise ValueError("Model ID or path cannot be empty.")

        if self.mock_mode:
            print(f"[*] [MOCK] Model switched to: {model_id}")
            self.current_model_id = model_id
            return model_id

        import gc
        if self.img2img_pipe is not None:
            del self.img2img_pipe
            self.img2img_pipe = None
        if self.pipe is not None:
            del self.pipe
            self.pipe = None
            if torch is not None and torch.cuda.is_available():
                torch.cuda.empty_cache()
            gc.collect()

        self.active_loras.clear()
        self._load_pipeline(model_id)
        return model_id


    @property
    def model_loaded(self) -> bool:
        return self.pipe is not None and not self.mock_mode

    # -- LoRA adapters (Part 2/5) -------------------------------------
    def load_lora(
        self,
        lora_path_or_id: str,
        adapter_name: Optional[str] = None,
        weight: float = 0.8,
    ) -> str:
        """Load a LoRA from a local .safetensors file or HF repo ID.

        Returns the registered adapter_name.
        """
        if not adapter_name:
            base = os.path.basename(lora_path_or_id)
            adapter_name = os.path.splitext(base)[0].replace("-", "_").lower()
        if self.mock_mode:
            print(f"[*] [MOCK] Loading LoRA '{adapter_name}' from "
                  f"{lora_path_or_id} with weight {weight}")
            self.active_loras[adapter_name] = {
                "path": lora_path_or_id, "weight": weight}
            return adapter_name
        if torch is None or self.pipe is None:
            raise RuntimeError(
                "torch/diffusers are required for real LoRA loading. "
                "Run: pip install -r requirements.txt")
        if os.path.isfile(lora_path_or_id):
            lora_dir = os.path.dirname(lora_path_or_id) or "."
            weight_name = os.path.basename(lora_path_or_id)
            self.pipe.load_lora_weights(
                lora_dir, weight_name=weight_name,
                adapter_name=adapter_name)
        else:
            self.pipe.load_lora_weights(
                lora_path_or_id, adapter_name=adapter_name)
        self.active_loras[adapter_name] = {
            "path": lora_path_or_id, "weight": weight}
        self._apply_adapter_weights()
        print(f"[OK] LoRA '{adapter_name}' loaded (weight: {weight}).")
        return adapter_name

    def unload_loras(self) -> None:
        if self.mock_mode:
            print("[*] [MOCK] Unloading all LoRAs.")
            self.active_loras.clear()
            return
        if self.pipe is not None and self.active_loras:
            self.pipe.unload_lora_weights()
            self.active_loras.clear()
            print("[OK] All LoRAs unloaded.")

    def set_lora_scale(self, adapter_name: str, weight: float) -> None:
        if adapter_name not in self.active_loras:
            raise KeyError(
                f"LoRA adapter '{adapter_name}' is not currently loaded.")
        self.active_loras[adapter_name]["weight"] = weight
        if not self.mock_mode:
            self._apply_adapter_weights()

    def get_active_loras(self) -> Dict[str, dict]:
        return dict(self.active_loras)

    def _apply_adapter_weights(self) -> None:
        if not self.active_loras or self.mock_mode or self.pipe is None:
            return
        names: List[str] = list(self.active_loras.keys())
        weights = [self.active_loras[n]["weight"] for n in names]
        self.pipe.set_adapters(names, adapter_weights=weights)

    def generate(
        self,
        prompt: str,
        negative_prompt: str = "low quality, bad anatomy, "
                               "worst quality, blurry",
        aspect_ratio: str = "9:16",
        num_inference_steps: int = 30,
        guidance_scale: float = 7.0,
        seed: int = -1,
        init_image: Optional[Image.Image] = None,
        strength: float = 0.65,
    ) -> Image.Image:
        width, height = ASPECT_RATIO_BUCKETS.get(aspect_ratio, (1024, 1024))

        if self.mock_mode:
            return self._generate_mock_image(
                prompt, width, height, init_image=init_image
            )

        if torch is None:
            raise RuntimeError(
                "torch is required for real generation. "
                "Run: pip install -r requirements.txt")

        generator = None
        if seed != -1:
            generator = torch.Generator(device=self.device).manual_seed(seed)

        # FLUX family: pipeline takes no negative prompt; schnell ignores
        # guidance (distilled 4-step), dev uses ~3.5.
        if getattr(self, "family", "sdxl") == "flux":
            kwargs = dict(
                prompt=prompt,
                width=width,
                height=height,
                num_inference_steps=num_inference_steps,
                guidance_scale=guidance_scale,
                generator=generator,
            )
            if init_image is not None:
                if self.img2img_pipe is None:
                    from diffusers import AutoPipelineForImage2Image
                    log.info("[*] Creating img2img pipe from FLUX pipe (sharing weights)...")
                    self.img2img_pipe = AutoPipelineForImage2Image.from_pipe(
                        self.pipe)
                init_img = init_image.convert("RGB").resize(
                    (width, height), Image.Resampling.LANCZOS
                )
                result = self.img2img_pipe(
                    image=init_img, strength=strength, **kwargs)
                return result.images[0]
            result = self.pipe(**kwargs)
            return result.images[0]

        if init_image is not None:
            if self.img2img_pipe is None:
                from diffusers import AutoPipelineForImage2Image
                log.info("[*] Creating AutoPipelineForImage2Image from SDXL pipe (sharing weights)...")
                self.img2img_pipe = AutoPipelineForImage2Image.from_pipe(self.pipe)
            init_img = init_image.convert("RGB").resize(
                (width, height), Image.Resampling.LANCZOS
            )
            result = self.img2img_pipe(
                prompt=prompt,
                negative_prompt=negative_prompt,
                image=init_img,
                strength=strength,
                num_inference_steps=num_inference_steps,
                guidance_scale=guidance_scale,
                generator=generator,
            )
            return result.images[0]

        result = self.pipe(
            prompt=prompt,
            negative_prompt=negative_prompt,
            width=width,
            height=height,
            num_inference_steps=num_inference_steps,
            guidance_scale=guidance_scale,
            generator=generator,
        )
        return result.images[0]

    def _generate_mock_image(
        self,
        prompt: str,
        width: int,
        height: int,
        init_image: Optional[Image.Image] = None,
    ) -> Image.Image:
        """Draws a clean placeholder preview when no GPU is present."""
        img = Image.new("RGB", (width, height), color=(28, 32, 42))
        draw = ImageDraw.Draw(img)
        if init_image is not None:
            try:
                thumb = init_image.copy().convert("RGB")
                thumb.thumbnail((240, 240))
                img.paste(thumb, (40, 200))
                draw.text(
                    (40, 450), "Reference Image Attached", fill=(255, 180, 60)
                )
            except Exception:
                pass
        lora_lines = ""
        if self.active_loras:
            lora_lines = "\nActive LoRAs:\n" + "\n".join(
                f" - {name} (weight: {data['weight']})"
                for name, data in self.active_loras.items()
            )
        ref_text = "\n[Mode: Image Reference / Img2Img]" if init_image is not None else ""
        text = (f"MOCK SDXL PREVIEW{ref_text}\nResolution: {width}x{height}\n"
                f"Prompt: {prompt[:70]}...\n{lora_lines}")
        draw.text((40, 40), text, fill=(210, 210, 210))
        return img


def nearest_bucket(width: int, height: int) -> str:
    """Snap arbitrary dimensions to the closest SDXL bucket key.

    Matches aspect ratio first, then total pixel count, so e.g.
    1024x576 lands on 16:9 instead of 1:1.
    """
    target_ratio = width / max(height, 1)
    target_px = width * height

    def score(key: str) -> tuple[float, float]:
        bw, bh = ASPECT_RATIO_BUCKETS[key]
        ratio_err = abs(bw / bh - target_ratio)
        px_err = abs(bw * bh - target_px) / 1_000_000
        return (ratio_err, px_err)

    return min(ASPECT_RATIO_BUCKETS, key=score)


class ImagePipeline:
    """Serving adapter: same interface the API routes already use.

    generate(...) snaps to the nearest aspect bucket, renders via
    SDXLEngine, and returns (base64_png, seed_used, elapsed_sec).
    """

    def __init__(self) -> None:
        self.engine = SDXLEngine()
        self.device = self.engine.device
        self.mock_mode = self.engine.mock_mode
        self.model_loaded = self.engine.model_loaded

    def generate(
        self,
        prompt: str,
        negative_prompt: str = "",
        steps: int = 30,
        cfg_scale: float = 7.0,
        width: int = 1024,
        height: int = 1024,
        seed: int = -1,
        aspect_ratio: Optional[str] = None,
        init_image: Optional[Image.Image] = None,
        strength: float = 0.65,
    ) -> tuple[str, int, float]:
        seed_used = (
            seed if seed is not None and seed >= 0
            else random.randint(0, 2**31 - 1)
        )
        if aspect_ratio in ASPECT_RATIO_BUCKETS:
            bucket = aspect_ratio
        else:
            bucket = nearest_bucket(width, height)
        started = time.perf_counter()
        image = self.engine.generate(
            prompt=prompt,
            negative_prompt=negative_prompt
            or "low quality, bad anatomy, worst quality, blurry",
            aspect_ratio=bucket,
            num_inference_steps=steps,
            guidance_scale=cfg_scale,
            seed=seed_used,
            init_image=init_image,
            strength=strength,
        )
        buf = io.BytesIO()
        image.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode("utf-8")
        return b64, seed_used, time.perf_counter() - started

    # -- LoRA passthroughs (Part 2/5) ----------------------------------
    def load_lora(
        self,
        lora_path_or_id: str,
        adapter_name: Optional[str] = None,
        weight: float = 0.8,
    ) -> str:
        """Load a LoRA adapter; returns the registered name."""
        return self.engine.load_lora(
            lora_path_or_id, adapter_name=adapter_name, weight=weight)

    def unload_loras(self) -> None:
        """Remove all LoRA adapters."""
        self.engine.unload_loras()

    def set_lora_scale(self, adapter_name: str, weight: float) -> None:
        """Re-weight a loaded adapter without disk I/O."""
        self.engine.set_lora_scale(adapter_name, weight)

    @property
    def active_loras(self) -> Dict[str, dict]:
        """Currently loaded adapters and their weights."""
        return self.engine.get_active_loras()

    def switch_model(self, model_id: str) -> str:
        """Switch base SDXL model without restarting the process."""
        return self.engine.switch_model(model_id)

    @property
    def current_model(self) -> str:
        """The currently active model ID or checkpoint path."""
        return self.engine.current_model_id



_singleton: ImagePipeline | None = None


def get_pipeline() -> ImagePipeline:
    global _singleton
    if _singleton is None:
        _singleton = ImagePipeline()
    return _singleton
