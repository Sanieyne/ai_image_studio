import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from generation.device import (
    get_device,
    get_device_name,
    get_optimal_dtype,
    empty_device_cache,
    get_onnx_providers,
)


def test_device_detection_returns_valid_device():
    device_type, dev_obj = get_device()
    assert device_type in ("cuda", "mps", "directml", "cpu")
    assert isinstance(device_type, str)


def test_device_name_returns_string():
    name = get_device_name()
    assert isinstance(name, str)
    assert len(name) > 0


def test_optimal_dtype():
    # If torch is not installed or in mock mode, get_optimal_dtype handles it gracefully
    dtype = get_optimal_dtype("cpu")
    if dtype is not None:
        assert str(dtype) in ("torch.float32", "torch.float16", "torch.bfloat16")


def test_empty_device_cache_does_not_throw():
    empty_device_cache()


def test_onnx_providers_includes_cpu():
    providers = get_onnx_providers()
    assert isinstance(providers, list)
    assert "CPUExecutionProvider" in providers
