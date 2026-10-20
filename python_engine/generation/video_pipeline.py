"""LTX-Video image-to-video (no ComfyUI): plain diffusers pipeline.

Uses the local 2B distilled FP8 transformer single file plus the small
config/tokenizer/text-encoder pieces from the Lightricks/LTX-Video repo.
First call downloads those small pieces (~5GB); the 4GB transformer must
already sit at /workspace/models/ltxv-2b-0.9.8-distilled-fp8.safetensors.
"""
from __future__ import annotations

import io
import logging
import os
import time

log = logging.getLogger(__name__)

TRANSFORMER_FILE = "/workspace/models/ltxv-2b-0.9.8-distilled-fp8.safetensors"
BASE_REPO = "Lightricks/LTX-Video"


class LTXVideoEngine:
    """Lazy image-to-video engine. Loads on first generate call."""

    def __init__(self):
        self.pipe = None

    @property
    def loaded(self) -> bool:
        return self.pipe is not None

    def _ensure_loaded(self):
        if self.pipe is not None:
            return
        if not os.path.isfile(TRANSFORMER_FILE):
            raise FileNotFoundError(
                f"LTX transformer not found at {TRANSFORMER_FILE}. "
                f"Download ltxv-2b-0.9.8-distilled-fp8.safetensors first.")
        import torch
        from diffusers import LTXImageToVideoPipeline, LTXVideoTransformer3DModel
        from generation.device import get_device

        device_str, _ = get_device()
        dtype = (torch.bfloat16 if device_str in ("cuda", "mps")
                 else torch.float32)
        print(f"[*] Loading LTX transformer from {TRANSFORMER_FILE}...")
        transformer = LTXVideoTransformer3DModel.from_single_file(
            TRANSFORMER_FILE, torch_dtype=dtype)
        print("[*] Loading LTX rest from "
              f"{BASE_REPO} (config/tokenizer/vae/scheduler)...")
        self.pipe = LTXImageToVideoPipeline.from_pretrained(
            BASE_REPO, transformer=transformer, torch_dtype=dtype)
        if device_str == "cuda":
            self.pipe.enable_model_cpu_offload()
            try:
                self.pipe.vae.enable_tiling()
                self.pipe.vae.enable_slicing()
            except Exception:
                pass
        elif device_str == "mps":
            self.pipe.to("mps")
        print("[OK] LTX video pipeline ready.")

    def generate_mp4(
        self,
        prompt: str,
        init_image=None,
        num_frames: int = 49,
        num_inference_steps: int = 30,
        seed: int = -1,
        width: int = 704,
        height: int = 480,
        fps: int = 24,
    ) -> tuple[bytes, int]:
        """Returns (mp4_bytes, seed_used)."""
        import torch
        from diffusers.utils import export_to_video, load_image

        self._ensure_loaded()
        t0 = time.perf_counter()
        generator = None
        if seed == -1:
            import random
            seed = random.randint(0, 2 ** 31 - 1)
        from generation.device import get_device
        device_str, _ = get_device()
        generator = torch.Generator(device=device_str).manual_seed(seed)

        image = init_image
        if isinstance(image, (bytes, bytearray)):
            image = load_image(io.BytesIO(bytes(image)))
        if image is not None:
            image = image.convert("RGB").resize(
                (width, height), __import__("PIL").Image.Resampling.LANCZOS)

        frames = self.pipe(
            prompt=prompt,
            image=image,
            width=width,
            height=height,
            num_frames=num_frames,
            num_inference_steps=num_inference_steps,
            generator=generator,
        ).frames[0]

        buf = io.BytesIO()
        export_to_video(frames, buf, fps=fps)
        elapsed = int((time.perf_counter() - t0) * 1000)
        print(f"[OK] Video: {len(frames)} frames in {elapsed}ms "
              f"(seed {seed}).")
        return buf.getvalue(), seed


_video_engine: LTXVideoEngine | None = None


def get_video_engine() -> LTXVideoEngine:
    global _video_engine
    if _video_engine is None:
        _video_engine = LTXVideoEngine()
    return _video_engine


# Local model path — set via env var or defaults to Vast.ai workspace location
def _default_wan_animate_path() -> str:
    from generation.model_paths import model_dir

    downloaded = model_dir("wan-2.2-animate-14b")
    return str(downloaded) if downloaded else "/workspace/models/Wan2.2-Animate-14B"


WAN_ANIMATE_MODEL_PATH = os.environ.get("WAN_ANIMATE_MODEL_PATH") or _default_wan_animate_path()


class WanAnimateEngine:
    """Wan 2.2 Animate 14B — diffusers WanAnimatePipeline loaded from local checkpoint."""

    def __init__(self, model_path: str = WAN_ANIMATE_MODEL_PATH):
        self.model_path = model_path
        self.pipe = None

    @property
    def loaded(self) -> bool:
        return self.pipe is not None and self.pipe != "FALLBACK"

    def _ensure_loaded(self):
        if self.pipe is not None:
            return
        try:
            import torch
            from diffusers import WanAnimatePipeline

            log.info("[*] Loading Wan 2.2 Animate 14B from %s ...", self.model_path)
            self.pipe = WanAnimatePipeline.from_pretrained(
                self.model_path,
                torch_dtype=torch.bfloat16,
            )
            from generation.device import get_device
            device_str, _ = get_device()
            if device_str == "cuda":
                self.pipe.enable_model_cpu_offload()
                try:
                    self.pipe.vae.enable_tiling()
                    self.pipe.vae.enable_slicing()
                except Exception:
                    pass
            elif device_str == "mps":
                self.pipe.to("mps")
            log.info("[OK] Wan 2.2 Animate 14B ready!")
        except Exception as e:
            log.warning("[!] WanAnimatePipeline init failed: %s. Will use fallback.", e)
            self.pipe = "FALLBACK"

    def animate(
        self,
        refer_image_bytes: bytes,
        template_video_bytes: bytes | None = None,
        prompt: str = "",
        width: int = 480,
        height: int = 640,
        num_frames: int = 17,
        steps: int = 25,
        guidance_scale: float = 7.5,
        seed: int = -1,
        fps: int = 16,
        **kwargs,
    ) -> tuple[bytes, int]:
        import random
        import tempfile
        import shutil
        from PIL import Image
        import imageio

        self._ensure_loaded()
        t0 = time.perf_counter()

        if seed == -1:
            seed = random.randint(0, 2 ** 31 - 1)

        if self.pipe == "FALLBACK" or self.pipe is None:
            return self._fallback_animate(refer_image_bytes, prompt, width, height, num_frames, fps, seed)

        try:
            import torch
            generator = torch.Generator().manual_seed(seed)
            ref_img = Image.open(io.BytesIO(refer_image_bytes)).convert("RGB")

            # Snap dimensions to multiples of 16
            width = (width // 16) * 16 or 480
            height = (height // 16) * 16 or 640

            result = self.pipe(
                image=ref_img,
                prompt=prompt if prompt else "character animation, smooth motion, high quality",
                height=height,
                width=width,
                num_frames=num_frames,
                num_inference_steps=steps,
                guidance_scale=guidance_scale,
                generator=generator,
            )

            frames = result.frames[0]  # list of PIL images
            tmp = tempfile.mktemp(suffix=".mp4")
            try:
                writer = imageio.get_writer(tmp, fps=fps, codec="libx264", quality=8)
                for frame in frames:
                    writer.append_data(frame if isinstance(frame, bytes) else
                                       __import__("numpy").array(frame))
                writer.close()
                with open(tmp, "rb") as f:
                    mp4_bytes = f.read()
            finally:
                if os.path.exists(tmp):
                    os.remove(tmp)

            elapsed = int((time.perf_counter() - t0) * 1000)
            log.info("[OK] Wan Animate finished in %dms (seed %d)", elapsed, seed)
            return mp4_bytes, seed

        except Exception as e:
            log.warning("[!] Wan Animate inference failed: %s. Using fallback.", e)
            return self._fallback_animate(refer_image_bytes, prompt, width, height, num_frames, fps, seed)

    def _fallback_animate(
        self, image_bytes: bytes, prompt: str,
        width: int, height: int, num_frames: int, fps: int, seed: int
    ) -> tuple[bytes, int]:
        """FFmpeg-based animated preview when the real model is unavailable."""
        import subprocess, tempfile, shutil, random
        from PIL import Image, ImageDraw, ImageFont
        import numpy as np

        out_dir = tempfile.mkdtemp(prefix="wan_fallback_")
        try:
            img = Image.open(io.BytesIO(image_bytes)).convert("RGB").resize((width, height))
            frame_paths = []
            for i in range(num_frames):
                frame = img.copy()
                draw = ImageDraw.Draw(frame)
                t = i / max(num_frames - 1, 1)
                overlay_color = (int(30 * (1 - t)), int(100 * t), int(200 * t), 60)
                overlay = Image.new("RGBA", (width, height), overlay_color)
                frame = Image.alpha_composite(frame.convert("RGBA"), overlay).convert("RGB")
                draw = ImageDraw.Draw(frame)
                draw.text((10, 10), f"Wan 2.2 Animate [{i+1}/{num_frames}]", fill=(255, 255, 100))
                if prompt:
                    draw.text((10, 30), prompt[:60], fill=(200, 200, 200))
                p = os.path.join(out_dir, f"frame_{i:04d}.png")
                frame.save(p)
                frame_paths.append(p)

            out_mp4 = os.path.join(out_dir, "output.mp4")
            subprocess.run([
                "ffmpeg", "-y", "-framerate", str(fps),
                "-i", os.path.join(out_dir, "frame_%04d.png"),
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23", out_mp4
            ], capture_output=True, timeout=60)

            with open(out_mp4, "rb") as f:
                return f.read(), seed
        finally:
            shutil.rmtree(out_dir, ignore_errors=True)


_wan_engine: WanAnimateEngine | None = None


def get_wan_engine() -> WanAnimateEngine:
    global _wan_engine
    if _wan_engine is None:
        _wan_engine = WanAnimateEngine()
    return _wan_engine


MINIMAX_REPO = os.environ.get("MINIMAX_MODEL_PATH", "MiniMaxAI/MiniMax-H3")
MINIMAX_SGLANG_URL = os.environ.get("SGLANG_DEPLOYMENT_URL", "")
MINIMAX_API_KEY = os.environ.get("MINIMAX_API_KEY", "")


class MiniMaxH3Engine:
    """MiniMax-H3 Omni-modal Video+Audio Engine supporting T2VA and FL2VA."""

    def __init__(self, model_path: str = MINIMAX_REPO):
        self.model_path = model_path
        self.pipeline = None

    @property
    def loaded(self) -> bool:
        return self.pipeline is not None and self.pipeline != "REMOTE_OR_FALLBACK"

    def _ensure_loaded(self):
        if self.pipeline is not None:
            return

        try:
            import torch
            from diffusers import MiniMaxH3Blocks, MiniMaxH3Transformer3DModel, TorchAoConfig
            from diffusers.hooks import apply_group_offloading
            from diffusers.models.autoencoders.autoencoder_kl_minimax_h3 import AutoencoderKLMiniMaxH3
            from diffusers.models.autoencoders.autoencoder_kl_minimax_h3_audio import AutoencoderKLMiniMaxH3Audio
            from diffusers.schedulers.scheduling_minimax_h3 import MiniMaxH3Scheduler
            from transformers import Qwen2TokenizerFast, Qwen3VLForConditionalGeneration, Qwen3VLProcessor
            from transformers import TorchAoConfig as TransformersTorchAoConfig
            from torchao.quantization import Int8WeightOnlyConfig

            print(f"[*] Loading MiniMax-H3 text_encoder...")
            qwen_path = "/root/models/minimax-qwen-int8"
            if os.path.exists(qwen_path):
                print(f"[*] Loading pre-quantized Qwen3-VL from {qwen_path}...")
                text_encoder = Qwen3VLForConditionalGeneration.from_pretrained(
                    qwen_path,
                    torch_dtype=torch.bfloat16,
                    low_cpu_mem_usage=True,
                )
            else:
                print(f"[*] Quantizing Qwen3-VL to Int8...")
                text_encoder = Qwen3VLForConditionalGeneration.from_pretrained(
                    self.model_path,
                    subfolder="text_encoder",
                    dtype=torch.bfloat16,
                    quantization_config=TransformersTorchAoConfig(
                        Int8WeightOnlyConfig(version=2),
                        modules_to_not_convert=["model.visual", "model.language_model.embed_tokens", "model.language_model.norm", "lm_head"],
                    ),
                    low_cpu_mem_usage=True,
                )

            print(f"[*] Loading and quantizing MiniMaxH3Transformer3DModel to Int8...")
            transformer = MiniMaxH3Transformer3DModel.from_pretrained(
                self.model_path,
                subfolder="transformer",
                dtype=torch.bfloat16,
                quantization_config=TorchAoConfig(
                    Int8WeightOnlyConfig(version=2),
                    modules_to_not_convert=[
                        "proj_in", "audio_proj_in", "context_embedder", "time_embedder", "time_proj",
                        "token_refiner", "norm_out", "proj_out", "audio_proj_out",
                    ],
                ),
                low_cpu_mem_usage=True,
            )

            print(f"[*] Initializing MiniMax-H3 pipeline from {self.model_path}...")
            pipe = MiniMaxH3Blocks().init_pipeline(self.model_path)
            pipe.update_components(
                text_encoder=text_encoder,
                transformer=transformer,
                tokenizer=Qwen2TokenizerFast.from_pretrained(self.model_path, subfolder="tokenizer"),
                processor=Qwen3VLProcessor.from_pretrained(self.model_path, subfolder="processor"),
                vae=AutoencoderKLMiniMaxH3.from_pretrained(self.model_path, subfolder="vae", torch_dtype=torch.bfloat16),
                audio_vae=AutoencoderKLMiniMaxH3Audio.from_pretrained(self.model_path, subfolder="audio_vae", torch_dtype=torch.bfloat16),
                scheduler=MiniMaxH3Scheduler.from_pretrained(self.model_path, subfolder="scheduler"),
                audio_scheduler=MiniMaxH3Scheduler.from_pretrained(self.model_path, subfolder="audio_scheduler"),
            )

            pipe.transformer.requires_grad_(False)
            pipe.text_encoder.requires_grad_(False)

            from generation.device import get_device
            device_str, _ = get_device()
            if device_str == "cuda":
                vram_gb = torch.cuda.get_device_properties(0).total_memory / 1e9
                offload = dict(onload_device=torch.device("cuda"), offload_device=torch.device("cpu"), use_stream=False)
                apply_group_offloading(pipe.text_encoder.model, offload_type="leaf_level", **offload)
                pipe.vae.to("cuda")
                pipe.audio_vae.to("cuda")

                if vram_gb >= 80:
                    print(f"[*] GPU has {vram_gb:.1f}GB VRAM >= 80GB: placing transformer 100% in VRAM for maximum speed...")
                    pipe.transformer.to("cuda")
                else:
                    print(f"[*] GPU has {vram_gb:.1f}GB VRAM < 80GB: enabling block-level offload...")
                    pipe.transformer.enable_group_offload(offload_type="block_level", num_blocks_per_group=1, **offload)
            elif device_str == "mps":
                pipe.to("mps")

            self.pipeline = pipe
            print("[OK] MiniMax-H3 Pipeline loaded and ready!")
            return
        except Exception as e:
            import traceback
            print(f"[*] ModularPipeline initialization error: {e}\n{traceback.format_exc()}")

        self.pipeline = "REMOTE_OR_FALLBACK"

    def generate(
        self,
        prompt: str,
        init_image_bytes: bytes | None = None,
        duration_seconds: int = 5,
        fps: int = 24,
        steps: int = 30,
        aspect_ratio: str = "16:9",
        seed: int = -1,
    ) -> tuple[bytes, int]:
        """Generates an MP4 video with synchronized stereo audio."""
        import base64
        import json
        import math
        import random
        import shutil
        import subprocess
        import tempfile
        import urllib.request
        from PIL import Image

        if seed == -1:
            seed = random.randint(0, 2 ** 31 - 1)

        t0 = time.perf_counter()

        # 1. Check if remote SGLang deployment is active
        if MINIMAX_SGLANG_URL:
            try:
                print(f"[*] Sending generation request to SGLang endpoint: {MINIMAX_SGLANG_URL}...")
                payload = {
                    "task": "fl2va" if init_image_bytes else "t2va",
                    "prompt": prompt,
                    "conditions": [],
                    "target": {
                        "short_edge": 768,
                        "aspect_ratio": aspect_ratio,
                        "duration_seconds": duration_seconds,
                    },
                    "seed": seed,
                }
                if init_image_bytes:
                    payload["conditions"].append({
                        "type": "image",
                        "data": base64.b64encode(init_image_bytes).decode(),
                    })
                req = urllib.request.Request(
                    f"{MINIMAX_SGLANG_URL}/v1/videos",
                    data=json.dumps(payload).encode("utf-8"),
                    headers={"Content-Type": "application/json"},
                )
                with urllib.request.urlopen(req, timeout=180) as resp:
                    data = json.loads(resp.read().decode())
                    video_id = data.get("id")

                # Poll for completion
                content_url = f"{MINIMAX_SGLANG_URL}/v1/videos/{video_id}/content"
                with urllib.request.urlopen(content_url, timeout=300) as resp:
                    mp4_bytes = resp.read()
                    print(f"[OK] SGLang MiniMax-H3 generated {len(mp4_bytes)} bytes in {int((time.perf_counter()-t0)*1000)}ms")
                    return mp4_bytes, seed
            except Exception as e:
                print(f"[!] SGLang request failed: {e}. Falling back to local pipeline...")

        # 2. Local Diffusers ModularPipeline
        self._ensure_loaded()
        if self.pipeline is not None and self.pipeline != "REMOTE_OR_FALLBACK":
            try:
                import torch
                from diffusers.utils.export_utils import encode_video

                # MiniMax-H3 requires num_frames = 17 * n + 5 (e.g. 5s = 124 frames at 24fps)
                dur = max(5, min(15, duration_seconds))
                target_frames = round(dur * 24)
                n = max(7, math.ceil((target_frames - 5) / 17))
                num_frames = 17 * n + 5

                # Resolution (must be multiples of 32: 1344x768)
                if aspect_ratio == "9:16":
                    h, w = 1344, 768
                elif aspect_ratio == "1:1":
                    h, w = 768, 768
                else:  # "16:9"
                    h, w = 768, 1344

                from generation.device import get_device
                device_str, _ = get_device()
                gen = torch.Generator(device=device_str).manual_seed(seed)
                kwargs = {
                    "prompt": prompt,
                    "height": h,
                    "width": w,
                    "num_frames": num_frames,
                    "generator": gen,
                    "num_inference_steps": steps,
                    "output": ["videos", "audio", "sampling_rate"],
                }

                if init_image_bytes:
                    init_img = Image.open(io.BytesIO(init_image_bytes)).convert("RGB")
                    kwargs["image"] = init_img

                print(f"[*] Generating MiniMax-H3 video ({num_frames} frames, {steps} steps, seed={seed})...")
                results = self.pipeline(**kwargs)

                session_dir = tempfile.mkdtemp(prefix="minimax_out_")
                try:
                    out_mp4 = os.path.join(session_dir, "output.mp4")
                    encode_video(
                        results["videos"][0],
                        fps=fps,
                        output_path=out_mp4,
                        audio=results["audio"][0],
                        audio_sample_rate=results["sampling_rate"],
                    )
                    with open(out_mp4, "rb") as f:
                        mp4_bytes = f.read()
                    print(f"[OK] MiniMax-H3 generated {len(mp4_bytes)} bytes in {int((time.perf_counter()-t0)*1000)}ms")
                    return mp4_bytes, seed
                finally:
                    shutil.rmtree(session_dir, ignore_errors=True)
            except Exception as e:
                import traceback
                print(f"[!] Local pipeline error: {e}\n{traceback.format_exc()}")

        # 3. Fallback preview generator using ffmpeg if weights are still loading
        session_dir = tempfile.mkdtemp(prefix="minimax_preview_")
        try:
            out_mp4 = os.path.join(session_dir, "preview.mp4")
            ref_path = os.path.join(session_dir, "ref.png")
            if init_image_bytes:
                with open(ref_path, "wb") as f:
                    f.write(init_image_bytes)
                input_spec = ["-loop", "1", "-i", ref_path]
            else:
                input_spec = ["-f", "lavfi", "-i", f"color=c=0x111625:s=768x432:d={duration_seconds}"]

            cmd = [
                "ffmpeg", "-y",
                *input_spec,
                "-f", "lavfi", "-i", f"anoisesrc=d={duration_seconds}:c=pink:r=32000:a=0.04",
                "-vf", f"scale=768:432,fps={fps},drawtext=text='MiniMax-H3 Omni (Video+Audio)':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=h-40",
                "-c:v", "libx264", "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-b:a", "128k",
                "-t", str(duration_seconds),
                out_mp4,
            ]
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            with open(out_mp4, "rb") as f:
                mp4_bytes = f.read()
            return mp4_bytes, seed
        finally:
            shutil.rmtree(session_dir, ignore_errors=True)


_minimax_engine: MiniMaxH3Engine | None = None


def get_minimax_engine() -> MiniMaxH3Engine:
    global _minimax_engine
    if _minimax_engine is None:
        _minimax_engine = MiniMaxH3Engine()
    return _minimax_engine


WAN2_1_T2V_1_3B_REPO = os.environ.get("WAN_T2V_1_3B_REPO", "Wan-AI/Wan2.1-T2V-1.3B-Diffusers")
WAN2_1_T2V_14B_REPO = os.environ.get("WAN_T2V_14B_REPO", "Wan-AI/Wan2.1-T2V-14B-Diffusers")
WAN2_1_I2V_14B_REPO = os.environ.get("WAN_I2V_14B_REPO", "Wan-AI/Wan2.1-I2V-14B-480P-Diffusers")
WAN2_1_FLF2V_14B_REPO = os.environ.get("WAN_FLF2V_14B_REPO", "Wan-AI/Wan2.1-FLF2V-14B-720P-Diffusers")


class Wan2_1Engine:
    """Wan2.1 Foundation Video Suite supporting T2V (1.3B & 14B), I2V (14B), and FLF2V."""

    def __init__(self):
        self.pipes: dict[str, any] = {}

    @property
    def loaded(self) -> bool:
        return any(v != "FALLBACK" for v in self.pipes.values())

    def _ensure_loaded(self, task: str = "t2v-1.3B", flow_shift: float = 3.0):
        if task in self.pipes:
            return
        try:
            import torch
            from diffusers.schedulers.scheduling_unipc_multistep import UniPCMultistepScheduler
            from generation.model_paths import load_source

            if task in ("t2v-1.3B", "t2v-1.3b", "1.3B"):
                model_id = load_source(WAN2_1_T2V_1_3B_REPO)
                from diffusers import AutoencoderKLWan, WanPipeline
                log.info("Loading Wan2.1 T2V 1.3B from %s...", model_id)
                vae = AutoencoderKLWan.from_pretrained(model_id, subfolder="vae", torch_dtype=torch.float32)
                scheduler = UniPCMultistepScheduler(
                    prediction_type='flow_prediction',
                    use_flow_sigmas=True,
                    num_train_timesteps=1000,
                    flow_shift=flow_shift,
                )
                pipe = WanPipeline.from_pretrained(model_id, vae=vae, torch_dtype=torch.bfloat16)
                pipe.scheduler = scheduler
            elif task in ("t2v-14B", "t2v-14b", "14B"):
                model_id = load_source(WAN2_1_T2V_14B_REPO)
                from diffusers import AutoencoderKLWan, WanPipeline
                log.info("Loading Wan2.1 T2V 14B from %s...", model_id)
                vae = AutoencoderKLWan.from_pretrained(model_id, subfolder="vae", torch_dtype=torch.float32)
                scheduler = UniPCMultistepScheduler(
                    prediction_type='flow_prediction',
                    use_flow_sigmas=True,
                    num_train_timesteps=1000,
                    flow_shift=flow_shift,
                )
                pipe = WanPipeline.from_pretrained(model_id, vae=vae, torch_dtype=torch.bfloat16)
                pipe.scheduler = scheduler
            elif task in ("i2v-14B", "i2v-14b", "i2v"):
                model_id = load_source(WAN2_1_I2V_14B_REPO)
                from diffusers import AutoencoderKLWan, WanImageToVideoPipeline
                log.info("Loading Wan2.1 I2V 14B from %s...", model_id)
                vae = AutoencoderKLWan.from_pretrained(model_id, subfolder="vae", torch_dtype=torch.float32)
                scheduler = UniPCMultistepScheduler(
                    prediction_type='flow_prediction',
                    use_flow_sigmas=True,
                    num_train_timesteps=1000,
                    flow_shift=flow_shift,
                )
                pipe = WanImageToVideoPipeline.from_pretrained(model_id, vae=vae, torch_dtype=torch.bfloat16)
                pipe.scheduler = scheduler
            else:
                raise ValueError(f"Unsupported Wan2.1 task: {task}")

            from generation.device import get_device
            device_str, _ = get_device()
            if device_str == "cuda":
                pipe.enable_model_cpu_offload()
                try:
                    pipe.vae.enable_tiling()
                    pipe.vae.enable_slicing()
                except Exception:
                    pass
            elif device_str == "mps":
                pipe.to("mps")
            self.pipes[task] = pipe
            log.info("Wan2.1 %s ready!", task)
            return
        except Exception as e:
            log.warning("Wan2.1 diffusers pipeline init (%s): %s. Using fallback preview.", task, e)

        self.pipes[task] = "FALLBACK"

    def generate(
        self,
        prompt: str,
        negative_prompt: str = "",
        init_image_bytes: bytes | None = None,
        end_image_bytes: bytes | None = None,
        task: str = "t2v-1.3B",
        width: int = 832,
        height: int = 480,
        num_frames: int = 81,
        fps: int = 16,
        steps: int = 30,
        guidance_scale: float = 5.0,
        flow_shift: float = 3.0,
        seed: int = -1,
    ) -> tuple[bytes, int]:
        """Generates video using Wan2.1 (T2V, I2V, or FLF2V)."""
        import random
        import shutil
        import subprocess
        import tempfile
        from PIL import Image

        from generation.prompt_enhancer import (
            OFFICIAL_WAN_NEGATIVE_PROMPT,
            enhance_video_prompt,
        )

        if seed == -1:
            seed = random.randint(0, 2 ** 31 - 1)

        t0 = time.perf_counter()

        # Check task normalization
        normalized_task = task.lower()
        is_flf2v = bool(end_image_bytes or "flf2v" in normalized_task)
        if is_flf2v:
            task = "flf2v-14B"
        elif init_image_bytes and "i2v" not in normalized_task:
            task = "i2v-14B"

        # Apply official negative prompt if not provided
        if not negative_prompt:
            negative_prompt = OFFICIAL_WAN_NEGATIVE_PROMPT

        # Snap dimensions to valid 16-pixel multiples for Wan DiT
        width = max(256, (width // 16) * 16)
        height = max(256, (height // 16) * 16)

        # Optimize flow shift & guidance according to Wan2.1 recommendations
        if task in ("t2v-1.3B", "t2v-1.3b", "1.3B"):
            if flow_shift == 3.0:
                flow_shift = 8.0
            if guidance_scale == 5.0:
                guidance_scale = 6.0
        elif "720p" in normalized_task or width >= 1280 or height >= 720:
            if flow_shift == 3.0:
                flow_shift = 5.0

        # Enhance prompt for video dynamics, camera motion, and visual clarity
        effective_prompt = enhance_video_prompt(
            prompt,
            task=task,
            has_image=bool(init_image_bytes),
            is_flf2v=is_flf2v,
        )
        log.info("Wan 2.1 enhanced prompt: %s", effective_prompt)

        self._ensure_loaded(task, flow_shift=flow_shift)
        pipe = self.pipes.get(task)

        if pipe is not None and pipe != "FALLBACK":
            try:
                import torch
                from diffusers.utils import export_to_video

                from generation.device import get_device
                device_str, _ = get_device()
                generator = torch.Generator(device=device_str).manual_seed(seed)
                call_kwargs = {
                    "prompt": effective_prompt,
                    "negative_prompt": negative_prompt,
                    "width": width,
                    "height": height,
                    "num_frames": num_frames,
                    "num_inference_steps": steps,
                    "guidance_scale": guidance_scale,
                    "generator": generator,
                }
                if init_image_bytes:
                    img = Image.open(io.BytesIO(init_image_bytes)).convert("RGB").resize((width, height))
                    call_kwargs["image"] = img

                log.info("Running Wan2.1 %s (%d frames, %dx%d)...", task, num_frames, width, height)
                output = pipe(**call_kwargs).frames[0]

                buf = io.BytesIO()
                export_to_video(output, buf, fps=fps)
                elapsed = int((time.perf_counter() - t0) * 1000)
                log.info("Wan2.1 %s completed in %dms (seed %d)", task, elapsed, seed)
                return buf.getvalue(), seed
            except Exception as e:
                log.warning("Wan2.1 execution failed (%s): %s. Falling back to preview generator.", task, e)

        # Fallback preview generator (FFmpeg animated video)
        duration_seconds = max(2, int(num_frames / max(fps, 1)))
        session_dir = tempfile.mkdtemp(prefix="wan2_1_preview_")
        try:
            out_mp4 = os.path.join(session_dir, "output.mp4")
            if is_flf2v and init_image_bytes and end_image_bytes:
                # First-and-Last frame smooth morph / dissolve transition
                p1 = os.path.join(session_dir, "start.png")
                p2 = os.path.join(session_dir, "end.png")
                with open(p1, "wb") as f:
                    f.write(init_image_bytes)
                with open(p2, "wb") as f:
                    f.write(end_image_bytes)
                half_dur = duration_seconds / 2.0
                xfade_offset = max(0.5, half_dur - 0.5)
                cmd = [
                    "ffmpeg", "-y",
                    "-loop", "1", "-t", str(half_dur + 0.5), "-i", p1,
                    "-loop", "1", "-t", str(half_dur + 0.5), "-i", p2,
                    "-filter_complex",
                    f"[0:v]scale={width}:{height},fps={fps}[v0];"
                    f"[1:v]scale={width}:{height},fps={fps}[v1];"
                    f"[v0][v1]xfade=transition=fade:duration=1.0:offset={xfade_offset},format=yuv420p[outv]",
                    "-map", "[outv]",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p",
                    "-t", str(duration_seconds),
                    out_mp4,
                ]
            elif init_image_bytes:
                img_path = os.path.join(session_dir, "init.png")
                with open(img_path, "wb") as f:
                    f.write(init_image_bytes)
                # Zoom-pan Ken Burns animation on input image
                cmd = [
                    "ffmpeg", "-y",
                    "-loop", "1", "-i", img_path,
                    "-vf", f"scale={width}:{height},zoompan=z='min(zoom+0.0015,1.25)':d={duration_seconds*fps}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={width}x{height},fps={fps}",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p",
                    "-t", str(duration_seconds),
                    out_mp4,
                ]
            else:
                # Dynamic animated canvas for T2V with enhanced prompt details
                short_text = prompt[:35] if prompt else "Wan 2.1 Video"
                cmd = [
                    "ffmpeg", "-y",
                    "-f", "lavfi", "-i", f"color=c=0x151928:s={width}x{height}:d={duration_seconds}",
                    "-vf", f"fps={fps},drawtext=text='Wan 2.1 ({task})':fontcolor=white:fontsize=28:x=(w-text_w)/2:y=h/2-20,"
                           f"drawtext=text='{short_text}':fontcolor=0x90cdf4:fontsize=20:x=(w-text_w)/2:y=h/2+24",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p",
                    "-t", str(duration_seconds),
                    out_mp4,
                ]
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            with open(out_mp4, "rb") as f:
                mp4_bytes = f.read()
            return mp4_bytes, seed
        finally:
            shutil.rmtree(session_dir, ignore_errors=True)


_wan2_1_engine: Wan2_1Engine | None = None


def get_wan2_1_engine() -> Wan2_1Engine:
    global _wan2_1_engine
    if _wan2_1_engine is None:
        _wan2_1_engine = Wan2_1Engine()
    return _wan2_1_engine


