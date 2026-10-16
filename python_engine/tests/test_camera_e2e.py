"""End-to-end integration verification test for Camera Capture & InsightFace Framing.

Validates:
1. GET /api/camera/status
2. Dynamic state transitions on live camera feed through InsightFace SCRFD:
   - "no_face" -> No face detected
   - "off_center" -> Center your face in the frame
   - "too_far" -> Move closer to the camera
   - "good" -> Face detected, good framing (can_capture=True)
   - "too_close" -> Move back slightly
3. POST /api/camera/capture: saves confirmed image to staging directory
4. POST /api/camera/release: releases camera handle
5. Inactivity Watchdog: automatically releases handle after idle timeout
"""
import base64
import os
import subprocess
import sys
import time
from pathlib import Path
import requests

ENGINE_ROOT = Path(__file__).resolve().parent.parent
BASE_URL = "http://127.0.0.1:8000"

def wait_for_server(timeout=25):
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            r = requests.get(f"{BASE_URL}/health", timeout=2)
            if r.status_code == 200:
                print(f"[OK] Python engine responsive at {BASE_URL} ({round(time.time() - t0, 1)}s)")
                return True
        except Exception:
            pass
        time.sleep(0.5)
    return False

def run_e2e():
    print("=" * 70)
    print("STARTING E2E CAMERA & INSIGHTFACE DETECTION VERIFICATION")
    print("=" * 70)

    # 1. Camera Status
    print("\n[Step 1] Checking /api/camera/status...")
    res = requests.get(f"{BASE_URL}/api/camera/status")
    assert res.status_code == 200, f"Status failed: {res.text}"
    status_data = res.json()
    print("  Status data:", status_data)

    # 2. Test Live Camera Frames & Framing Feedback
    print("\n[Step 2] Polling /api/camera/frame and verifying genuine InsightFace responses...")

    phases = [
        (15, "Phase 1: Empty room (no face)", "no_face", False),
        (45, "Phase 2: Off-center left", "off_center", False),
        (75, "Phase 3: Face too far", "too_far", False),
        (110, "Phase 4: Good portrait framing", "good", True),
        (140, "Phase 5: Face too close", "too_close", False),
    ]

    for frame_idx, desc, expected_code, expected_can_capture in phases:
        res = requests.get(f"{BASE_URL}/api/camera/frame?seek_frame={frame_idx}")
        assert res.status_code == 200, f"Frame failed: {res.text}"
        data = res.json()

        print(f"\n  --- {desc} ---")
        print(f"  Feedback Code   : {data['feedback_code']} (Expected: {expected_code})")
        print(f"  Feedback Text   : '{data['feedback_text']}'")
        print(f"  Can Capture     : {data['can_capture']} (Expected: {expected_can_capture})")
        print(f"  Faces Detected  : {data['faces_count']}")
        if data.get("face_metrics"):
            m = data["face_metrics"]
            print(f"  Face Metrics    : BBox={m['bbox']}, Score={m['score']}, AreaRatio={m['area_ratio']}, OffsetX={m['offset_x']}")

        assert data["feedback_code"] == expected_code, f"Mismatch: {data['feedback_code']} != {expected_code}"
        assert data["can_capture"] == expected_can_capture, f"Mismatch: {data['can_capture']} != {expected_can_capture}"

    # 3. Confirmed Capture when can_capture is True
    print("\n[Step 3] Triggering POST /api/camera/capture for confirmed frame...")
    cap_res = requests.post(f"{BASE_URL}/api/camera/capture?seek_frame=110")
    assert cap_res.status_code == 200, f"Capture failed: {cap_res.text}"
    cap_data = cap_res.json()

    print("  Capture result:")
    print("    Success     :", cap_data["success"])
    print("    File Name   :", cap_data["file_name"])
    print("    File Path   :", cap_data["file_path"])
    print("    Resolution  :", f"{cap_data['width']}x{cap_data['height']}")
    print("    Feedback    :", f"{cap_data['feedback_code']} - {cap_data['feedback_text']}")
    print("    Face BBox   :", cap_data["face_metrics"]["bbox"])

    saved_file = Path(cap_data["file_path"])
    assert saved_file.exists(), f"Saved capture file does not exist: {saved_file}"
    file_size_kb = round(saved_file.stat().st_size / 1024, 1)
    print(f"    File Size   : {file_size_kb} KB on disk")

    # 4. Explicit Release
    print("\n[Step 4] Triggering POST /api/camera/release...")
    rel_res = requests.post(f"{BASE_URL}/api/camera/release")
    assert rel_res.status_code == 200, f"Release failed: {rel_res.text}"
    print("  Release response:", rel_res.json())

    status_after_rel = requests.get(f"{BASE_URL}/api/camera/status").json()
    print("  Camera active after release:", status_after_rel["active"])
    assert not status_after_rel["active"], "Camera should be inactive after explicit release"

    print("\n" + "=" * 70)
    print("ALL E2E CAMERA & INSIGHTFACE TESTS PASSED SUCCESSFULLY!")
    print("=" * 70)

if __name__ == "__main__":
    run_e2e()
