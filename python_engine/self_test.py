"""Engine self-test: import everything the engine needs and check the GPU.

    python self_test.py            # or: python app.py --self-test / engine.exe --self-test
    python self_test.py --json     # machine-readable result

Exit code 0 when every required check passes, 1 otherwise. Optional components
(try-on, Breeze voice) are reported but never fail the test.

Set AI_STUDIO_REQUIRE_CUDA=1 (cloud instances) to also require a CUDA GPU that
this torch build supports; that catches, for example, a card newer or older than
the architectures torch was compiled for.
"""
from __future__ import annotations

import importlib
import json
import os
import sys

ENGINE_VERSION = "0.4.1"  # same as app.py / flutter_app/lib/app_version.dart

REQUIRED = [
    ("fastapi", None),
    ("uvicorn", None),
    ("pydantic", None),
    ("PIL.Image", None),
    ("numpy", None),
    ("torch", None),
    ("safetensors", None),
    ("transformers", ["Qwen3VLForConditionalGeneration"]),
    ("diffusers", [
        "StableDiffusionXLPipeline", "AutoPipelineForImage2Image", "AutoPipelineForText2Image",
        "FluxPipeline", "FluxKontextPipeline", "FluxTransformer2DModel",
        "ZImagePipeline", "ZImageImg2ImgPipeline", "QwenImage21Pipeline",
        "WanPipeline", "WanImageToVideoPipeline", "WanAnimatePipeline", "AutoencoderKLWan",
        "MiniMaxH3Transformer3DModel", "ModularPipeline",
        "LTXImageToVideoPipeline", "LTXVideoTransformer3DModel",
    ]),
    ("soundfile", None),
    ("imageio", None),
    ("chatterbox.tts", ["ChatterboxTTS"]),
    ("chatterbox.mtl_tts", ["ChatterboxMultilingualTTS"]),
    # The engine's own modules.
    ("api.routes", ["router"]),
    ("generation.pipeline", ["get_pipeline", "peek_pipeline"]),
    ("generation.video_pipeline", None),
    ("generation.voice_pipeline", None),
    ("generation.enhancer_pipeline", None),
    ("generation.tryon_pipeline", None),
    ("generation.model_status", ["model_status_manager"]),
    ("generation.model_paths", ["load_source"]),
]

OPTIONAL = [
    ("generation.live_face_swap", ["get_live_face_swap_service"], "live face swap (deep-live-cam)"),
    ("generation.camera_service", ["get_camera_service"], "camera capture service"),
    ("fashn_vton", ["TryOnPipeline"], "virtual try-on"),
    ("breeze_infer.runtime", None, "Breeze voice"),
]


def _root_causes(e: BaseException) -> str:
    """The chained causes (lazy importers hide the real error behind them)."""
    parts, seen = [], set()
    cur = e.__cause__ or e.__context__
    while cur is not None and id(cur) not in seen and len(parts) < 4:
        seen.add(id(cur))
        parts.append(f"{type(cur).__name__}: {str(cur)[:300]}")
        cur = cur.__cause__ or cur.__context__
    return "".join(f" <- caused by {p}" for p in parts)


def _check(module: str, names) -> str | None:
    try:
        mod = importlib.import_module(module)
        for name in names or []:
            getattr(mod, name)
    except Exception as e:  # noqa: BLE001 - report every kind of failure
        return f"{module}: {type(e).__name__}: {e}{_root_causes(e)}"
    return None


def _check_cuda() -> str | None:
    try:
        import torch
    except Exception as e:  # noqa: BLE001
        return f"torch: {e}"
    if not torch.cuda.is_available():
        return "CUDA is not available (no GPU, or the driver is too old for this torch build)."
    major, minor = torch.cuda.get_device_capability(0)
    arch = f"sm_{major}{minor}"
    supported = torch.cuda.get_arch_list()
    if supported and arch not in supported:
        name = torch.cuda.get_device_name(0)
        return f"GPU {name} ({arch}) is not supported by this torch build (built for {', '.join(supported)})."
    return None


def run() -> dict:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    failures = [f for f in (_check(m, n) for m, n in REQUIRED) if f]
    if os.environ.get("AI_STUDIO_REQUIRE_CUDA") == "1":
        cuda = _check_cuda()
        if cuda:
            failures.append(cuda)
    unavailable = [f"{label} ({err})" for m, n, label in OPTIONAL if (err := _check(m, n))]
    return {"ok": not failures, "failures": failures, "optional_unavailable": unavailable}


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    result = run()
    if "--json" in argv:
        print(json.dumps(result))
    else:
        for f in result["failures"]:
            print(f"[FAIL] {f}")
        for u in result["optional_unavailable"]:
            print(f"[optional, unavailable] {u}")
        print("[OK] self-test passed" if result["ok"] else "[FAILED] self-test failed")
        print(f"engine {ENGINE_VERSION}")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
