"""Universal Hardware Acceleration Manager for Windows, Mac, and Linux.

Detects and selects optimal GPU acceleration:
- NVIDIA GPUs (CUDA): GeForce GTX/RTX, Tesla, A100/H100
- Apple Silicon (MPS / Metal): M1, M2, M3, M4 (Base/Pro/Max/Ultra)
- AMD & Intel GPUs on Windows (DirectML): Radeon RX 6000/7000, Intel Arc, Iris Xe
- Universal Fallback: CPU
"""
from __future__ import annotations

import gc
import logging
import os
import platform
from typing import List, Optional, Tuple

log = logging.getLogger(__name__)

try:
    import torch
except ImportError:
    torch = None


def get_device() -> Tuple[str, Optional[object]]:
    """Determine best available compute device and return (device_str, torch_device).
    
    Returns:
        tuple: (device_type: str, device_obj: torch.device or None)
        Possible device_type values: 'cuda', 'mps', 'directml', 'cpu'.
    """
    forced = os.environ.get("AI_STUDIO_DEVICE", "").strip().lower()
    if forced:
        if forced in ("cuda", "mps", "cpu", "directml"):
            log.info("Using user-forced device: %s", forced)
            if torch is not None:
                if forced == "directml":
                    try:
                        import torch_directml
                        return "directml", torch_directml.device()
                    except ImportError:
                        log.warning("torch-directml not installed, falling back to CPU")
                        return "cpu", torch.device("cpu")
                return forced, torch.device(forced)
            return forced, None

    # 1. NVIDIA CUDA (Windows / Linux)
    if torch is not None and torch.cuda.is_available():
        return "cuda", torch.device("cuda")

    # 2. Apple Silicon Metal Performance Shaders (macOS)
    if torch is not None and hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return "mps", torch.device("mps")

    # 3. Microsoft DirectML (Windows - AMD Radeon & Intel Arc)
    if torch is not None:
        try:
            import torch_directml
            if torch_directml.is_available():
                return "directml", torch_directml.device()
        except ImportError:
            pass

    # 4. Fallback CPU
    if torch is not None:
        return "cpu", torch.device("cpu")
    return "cpu", None


def get_device_name() -> str:
    """Return a clean human-readable name of the active compute hardware."""
    device_type, _ = get_device()
    if device_type == "cuda" and torch is not None and torch.cuda.is_available():
        try:
            return torch.cuda.get_device_name(0)
        except Exception:
            return "NVIDIA GPU (CUDA)"

    if device_type == "mps":
        proc = platform.processor() or "Apple Silicon"
        return f"Apple {proc} (Metal MPS)"

    if device_type == "directml":
        try:
            import torch_directml
            return f"{torch_directml.device_name(0)} (DirectML)"
        except Exception:
            return "DirectML GPU (AMD/Intel)"

    sys_proc = platform.processor() or platform.machine() or "Generic"
    return f"CPU ({sys_proc})"


def get_optimal_dtype(device_type: Optional[str] = None):
    """Return optimal torch dtype for the given device architecture."""
    if torch is None:
        return None

    if device_type is None:
        device_type, _ = get_device()

    if device_type == "cuda":
        # bfloat16 on Ampere/Ada/Hopper (RTX 3000/4000+), fp16 on older Turing/Pascal
        if torch.cuda.is_bf16_supported():
            return torch.bfloat16
        return torch.float16

    if device_type == "mps":
        # Apple Silicon Metal executes float16 with high throughput
        return torch.float16

    if device_type == "directml":
        # DirectML currently supports float16 natively
        return torch.float16

    return torch.float32


def empty_device_cache():
    """Clear hardware memory cache across CUDA, MPS, DirectML, and CPU."""
    device_type, _ = get_device()

    if device_type == "cuda" and torch is not None and torch.cuda.is_available():
        try:
            torch.cuda.empty_cache()
            torch.cuda.ipc_collect()
        except Exception:
            pass

    elif device_type == "mps" and torch is not None and hasattr(torch, "mps"):
        try:
            if hasattr(torch.mps, "empty_cache"):
                torch.mps.empty_cache()
        except Exception:
            pass

    gc.collect()


def get_onnx_providers() -> List[str]:
    """Return prioritized ONNX execution providers based on detected hardware."""
    try:
        import onnxruntime as ort
        available = set(ort.get_available_providers())
    except ImportError:
        return ["CPUExecutionProvider"]

    providers = []
    # Priority 1: Apple Silicon CoreML (NPU + GPU)
    if "CoreMLExecutionProvider" in available:
        providers.append("CoreMLExecutionProvider")

    # Priority 2: NVIDIA CUDA
    if "CUDAExecutionProvider" in available:
        providers.append("CUDAExecutionProvider")

    # Priority 3: Microsoft DirectML (AMD Radeon & Intel Arc)
    if "DmlExecutionProvider" in available:
        providers.append("DmlExecutionProvider")

    # Priority 4: CPU fallback
    if "CPUExecutionProvider" in available:
        providers.append("CPUExecutionProvider")

    return providers or ["CPUExecutionProvider"]
