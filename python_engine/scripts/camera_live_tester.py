"""Live HTTP Camera Endpoint Tester.

Polls http://127.0.0.1:8000/api/camera/frame every 1.5s and displays
real-time face detection, framing feedback, and lets you capture confirmed photos.
"""
import time
import requests

BASE_URL = "http://127.0.0.1:8000"

def main():
    print("=" * 70)
    print("LIVE WEBCAM FRAMING CLIENT TESTER")
    print(f"Connecting to {BASE_URL}...")
    print("=" * 70)

    try:
        r = requests.get(f"{BASE_URL}/health", timeout=3)
        print("Connected to camera engine:", r.json())
    except Exception as e:
        print(f"Error: Could not connect to {BASE_URL}. Ensure standalone_camera_server.py is running!")
        return

    iteration = 0
    print("\nStarting live frame polling (every 1.5s). Move your face in front of the camera:")
    print("-" * 70)

    try:
        while True:
            iteration += 1
            t0 = time.time()
            try:
                res = requests.get(f"{BASE_URL}/api/camera/frame", timeout=4)
                data = res.json()
            except Exception as e:
                print(f"[{iteration}] Request error: {e}")
                time.sleep(1.5)
                continue

            ms = int((time.time() - t0) * 1000)
            code = data.get("feedback_code", "unknown")
            text = data.get("feedback_text", "")
            can_cap = data.get("can_capture", False)
            metrics = data.get("face_metrics")

            metric_str = ""
            if metrics:
                metric_str = f"[Area: {metrics['area_ratio']*100:.1f}%, OffsetX: {metrics['offset_x']:+.2f}, Conf: {metrics['score']:.2f}]"
            else:
                metric_str = "[No face bbox]"

            status_indicator = ">>> CAN CAPTURE <<<" if can_cap else "   ADJUSTING   "
            print(f"[{iteration:03d} | {ms:3d}ms] {code.upper():14} | {status_indicator} | {text:40} {metric_str}")

            time.sleep(1.5)
    except KeyboardInterrupt:
        print("\nStopping live polling client.")

if __name__ == "__main__":
    main()
