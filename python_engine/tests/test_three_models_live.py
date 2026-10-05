import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


def run():
    engine_dir = Path(__file__).resolve().parent.parent
    port = 8897
    env = os.environ.copy()
    env["AI_STUDIO_MOCK"] = "1"
    env["AI_STUDIO_SELECTED_MODELS"] = "realesrgan-x4plus,fashn-vton-1.5,breeze-tts-2"
    env["PYTHONPATH"] = str(engine_dir)

    cmd = [
        sys.executable,
        "-m",
        "uvicorn",
        "app:app",
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
        "--log-level",
        "warning",
    ]
    proc = subprocess.Popen(
        cmd,
        cwd=str(engine_dir),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    time.sleep(1.8)
    snapshots = []
    t0 = time.time()
    for _ in range(16):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=1.0) as res:
                data = json.loads(res.read().decode("utf-8"))
                elapsed = round(time.time() - t0, 2)
                snapshots.append((elapsed, data))
        except Exception:
            pass
        time.sleep(0.5)

    try:
        proc.terminate()
        proc.wait(timeout=3)
    except Exception:
        proc.kill()

    print("\n" + "=" * 80)
    print("REAL CAPTURED SEQUENCE OF /health RESPONSES OVER TIME (3 MODELS)")
    print("=" * 80)
    for elapsed, data in snapshots:
        models_formatted = [
            f"{m['modelId']}: {m['status'].upper()} ({m.get('progressPercent', 0)}%)"
            for m in data.get("models", [])
        ]
        models_summary = " | ".join(models_formatted)
        print(f"[{elapsed:5.2f}s] status={data.get('status')} | model_loaded={data.get('model_loaded')} | current_model={data.get('current_model')}")
        print(f"         └─ models: [ {models_summary} ]")


if __name__ == "__main__":
    run()
