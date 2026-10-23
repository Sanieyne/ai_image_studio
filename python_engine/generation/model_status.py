"""Shared in-memory status store and sequential model lifecycle manager.

Tracks per-model status (queued | downloading | loading | ready | failed)
and download progress for models requested via AI_STUDIO_SELECTED_MODELS.
"""
from __future__ import annotations

import logging
import os
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional

log = logging.getLogger(__name__)

# Catalog VRAM requirements (in GB) matching recommendation.service.js
MODEL_VRAM_REQUIREMENTS_GB: Dict[str, float] = {
    "sdxl-base-1.0": 12.0,
    "flux-kontext-dev": 24.0,
    "z-image-turbo": 12.0,
    "qwen-image-2.1": 16.0,
    "wan-2.1-t2v-1.3b": 12.0,
    "wan-2.1-i2v-14b": 24.0,
    "wan-2.2-animate-14b": 24.0,
    "minimax-h3": 32.0,
    "chatterbox-tts": 4.0,
    "breeze-tts-2": 8.0,
    "fashn-vton-1.5": 16.0,
    "realesrgan-x4plus": 6.0,
}


class ModelStatusManager:
    """Thread-safe store and sequential processor for model lifecycle states."""

    def __init__(self):
        self._lock = threading.Lock()
        self._models: Dict[str, dict] = {}
        self._worker_thread: Optional[threading.Thread] = None
        self._is_running = False

    def initialize_models(self, model_ids: List[str]) -> None:
        """Register requested models in 'queued' state."""
        with self._lock:
            for raw_id in model_ids:
                clean_id = raw_id.strip()
                if not clean_id:
                    continue
                # Canonicalize if downloader is available
                try:
                    from download_model import resolve_canonical_id
                    canonical_id = resolve_canonical_id(clean_id)
                except Exception:
                    canonical_id = clean_id

                if canonical_id not in self._models:
                    self._models[canonical_id] = {
                        "modelId": canonical_id,
                        "status": "queued",
                        "progressPercent": 0.0,
                        "error": None,
                        "loadedInVram": False,
                    }

    def update_status(
        self,
        model_id: str,
        status: str,
        progress_percent: Optional[float] = None,
        error: Optional[str] = None,
        loaded_in_vram: Optional[bool] = None,
    ) -> None:
        """Thread-safe update of a single model's lifecycle status."""
        with self._lock:
            if model_id not in self._models:
                self._models[model_id] = {
                    "modelId": model_id,
                    "status": status,
                    "progressPercent": progress_percent or 0.0,
                    "error": error,
                    "loadedInVram": bool(loaded_in_vram),
                }
            else:
                self._models[model_id]["status"] = status
                if progress_percent is not None:
                    self._models[model_id]["progressPercent"] = round(float(progress_percent), 1)
                if error is not None:
                    self._models[model_id]["error"] = str(error)
                if loaded_in_vram is not None:
                    self._models[model_id]["loadedInVram"] = bool(loaded_in_vram)

    def get_status(self, model_id: str) -> Optional[dict]:
        """Retrieve status dict for a specific model."""
        with self._lock:
            item = self._models.get(model_id)
            return dict(item) if item else None

    def get_all_statuses(self) -> List[dict]:
        """Return snapshot of all registered model statuses."""
        with self._lock:
            return [dict(v) for v in self._models.values()]

    def is_model_ready(self, model_id: str) -> bool:
        """Check if a specific model is in ready state."""
        with self._lock:
            item = self._models.get(model_id)
            return bool(item and item.get("status") == "ready")

    def has_any_ready_model(self) -> bool:
        """True if at least one model has reached 'ready'."""
        with self._lock:
            return any(m.get("status") == "ready" for m in self._models.values())

    def get_first_ready_model_id(self) -> Optional[str]:
        """Return the ID of the first ready model, or None."""
        with self._lock:
            for mid, m in self._models.items():
                if m.get("status") == "ready":
                    return mid
            return None

    def start_lifecycle_worker(self, model_ids: Optional[List[str]] = None) -> None:
        """Launch background worker to sequentially download & load models."""
        with self._lock:
            if self._is_running:
                return
            self._is_running = True

        if model_ids:
            self.initialize_models(model_ids)

        worker = threading.Thread(
            target=self._run_sequential_lifecycle,
            args=(model_ids,),
            daemon=True,
            name="ModelLifecycleWorker",
        )
        self._worker_thread = worker
        worker.start()

    def _can_fit_in_vram(self, model_id: str) -> bool:
        """Evaluate whether the model can safely fit into available GPU VRAM.

        Matches sizing logic: If available physical VRAM exceeds requiredVramGB + 1GB safety margin,
        keep it loaded simultaneously. Otherwise, download/verify and load on demand.
        """
        try:
            import torch
            if not torch.cuda.is_available():
                return True  # Mock / CPU mode
            free_bytes, total_bytes = torch.cuda.mem_get_info()
            free_gb = free_bytes / (1024 ** 3)
            req_gb = MODEL_VRAM_REQUIREMENTS_GB.get(model_id, 8.0)
            # Require at least required GB + 1.0 GB headroom for runtime tensors
            fits = free_gb >= (req_gb + 1.0)
            log.info(
                "[vram-check] Model %s: required %.1fGB, free VRAM %.1fGB / %.1fGB total -> fits: %s",
                model_id,
                req_gb,
                free_gb,
                total_bytes / (1024 ** 3),
                fits,
            )
            return fits
        except Exception as e:
            log.warning("[vram-check] Could not inspect CUDA VRAM: %s. Assuming fitting.", e)
            return True

    def _run_sequential_lifecycle(self, model_ids: Optional[List[str]] = None) -> None:
        """Sequentially process each model: queued -> downloading -> loading -> ready."""
        try:
            # Determine models to process
            with self._lock:
                queue = list(self._models.keys())

            if not queue and model_ids:
                queue = list(model_ids)

            log.info("[*] ModelLifecycleWorker started for queue: %s", queue)

            # S3 client and storage root setup
            s3, bucket = None, None
            models_root = None
            try:
                from download_model import get_r2_client, get_default_models_root
                s3, bucket = get_r2_client()
                models_root = get_default_models_root()
                log.info("[*] ModelLifecycleWorker connected to R2 bucket '%s'.", bucket)
            except Exception as e:
                log.warning("[!] ModelLifecycleWorker R2 setup skipped or failed: %s", e)

            for mid in queue:
                log.info("[*] Starting sequential lifecycle for model '%s'", mid)

                # 1. DOWNLOADING
                self.update_status(mid, "downloading", progress_percent=0.0)

                download_ok = True
                if s3 and bucket and models_root:
                    try:
                        from download_model import download_single_model

                        def on_progress(bytes_done: int, total_bytes: int):
                            if total_bytes > 0:
                                pct = min(100.0, (bytes_done / total_bytes) * 100.0)
                            else:
                                pct = 100.0
                            self.update_status(mid, "downloading", progress_percent=pct)

                        download_ok = download_single_model(
                            s3=s3,
                            bucket=bucket,
                            model_id=mid,
                            models_root=models_root,
                            progress_callback=on_progress,
                        )
                    except Exception as dl_err:
                        log.warning("[!] Download error for model '%s': %s", mid, dl_err)
                        # Check if local weights exist anyway
                        download_ok = False

                # 2. LOADING
                self.update_status(mid, "loading", progress_percent=100.0)
                loaded_in_vram = False

                try:
                    loaded_in_vram = self._load_model_engine(mid)
                except Exception as load_err:
                    log.warning("[!] Loading failed for model '%s': %s", mid, load_err)
                    if os.environ.get("AI_STUDIO_MOCK", "0") == "1":
                        loaded_in_vram = True
                    else:
                        # Reported through /health, so the backend can tell the user why.
                        reason = str(load_err) if download_ok else f"download failed; {load_err}"
                        self.update_status(mid, "failed", error=reason)
                        continue

                # 3. READY
                self.update_status(
                    mid,
                    "ready",
                    progress_percent=100.0,
                    loaded_in_vram=loaded_in_vram,
                )
                log.info(
                    "[OK] Model '%s' reached READY state (loadedInVram=%s). Proceeding to next model.",
                    mid,
                    loaded_in_vram,
                )

            log.info("[*] ModelLifecycleWorker completed processing all models in queue.")
        except Exception as e:
            log.exception("[FATAL] Unhandled exception in ModelLifecycleWorker: %s", e)
        finally:
            with self._lock:
                self._is_running = False

    def _load_model_engine(self, model_id: str) -> bool:
        """Attempt to load or warm up the pipeline corresponding to model_id.

        Respects VRAM constraints: fitting models stay loaded simultaneously,
        while models exceeding VRAM stay validated and load on demand.
        """
        can_fit = self._can_fit_in_vram(model_id)

        # 1. RealESRGAN / Enhancer
        if "realesrgan" in model_id.lower() or "esrgan" in model_id.lower():
            from generation.enhancer_pipeline import get_enhancer_engine
            engine = get_enhancer_engine()
            if can_fit:
                return engine.load_model(model_id)
            return False

        # 2. Voice (Breeze / Chatterbox)
        if "tts" in model_id.lower() or "chatterbox" in model_id.lower() or "breeze" in model_id.lower():
            from generation.voice_pipeline import get_voice_engine
            engine = get_voice_engine()
            if can_fit:
                return bool(engine.loaded)
            return False

        # 3. Try-On (FASHN VTON)
        if "fashn" in model_id.lower() or "vton" in model_id.lower() or "tryon" in model_id.lower():
            from generation.tryon_pipeline import get_tryon_engine
            engine = get_tryon_engine()
            if can_fit:
                engine._ensure_loaded()
                return True
            return False

        # 4. Video (WAN / MiniMax)
        if "wan" in model_id.lower() or "minimax" in model_id.lower():
            # Video models are heavy; keep ready on disk unless high VRAM allows residency
            return False

        # 5. Base Image diffusion pipeline (SDXL, FLUX, Z-Image, Qwen)
        if not can_fit:
            return False
        from generation.pipeline import get_pipeline, peek_pipeline
        existing = peek_pipeline()
        if existing is None:
            # Created directly with this model: nothing else is loaded first.
            pipe = get_pipeline(model_id)
        else:
            pipe = existing
            if pipe.engine.current_model_id != model_id:
                pipe.switch_model(model_id)
        if not pipe.model_loaded and not getattr(pipe, "mock_mode", False):
            raise RuntimeError(f"Model '{model_id}' did not load.")
        return True


# Singleton instance used throughout the python engine
model_status_manager = ModelStatusManager()
