"""Generate test_camera_feed.mp4 for camera testing and verification.

Generates a realistic camera stream sequence with genuine face frames:
1. Seconds 0-3: Empty scene (no face) -> "No face detected"
2. Seconds 3-6: Face off-center (left) -> "Center your face in the frame"
3. Seconds 6-9: Face far away (small) -> "Move closer to the camera"
4. Seconds 9-13: Face well-framed & centered -> "Face detected, good framing"
5. Seconds 13-15: Face too close (large) -> "Move back slightly"
"""
import math
from pathlib import Path
import cv2
import numpy as np

def create_office_background(width=640, height=480):
    """Create a soft office/interior room background gradient."""
    bg = np.zeros((height, width, 3), dtype=np.uint8)
    for y in range(height):
        val = int(180 + 35 * (y / height))
        bg[y, :] = (val - 15, val, val - 10)
    # Add subtle shelf/wall lines
    cv2.line(bg, (0, 320), (width, 320), (140, 150, 140), 2)
    cv2.rectangle(bg, (40, 100), (160, 260), (160, 170, 165), -1)
    cv2.rectangle(bg, (40, 100), (160, 260), (120, 130, 125), 2)
    return bg

def overlay_face(bg, face_img, center_x, center_y, target_face_w):
    """Scale and blend face image into background at (center_x, center_y)."""
    h_bg, w_bg = bg.shape[:2]
    fh, fw = face_img.shape[:2]
    scale = target_face_w / float(fw)
    target_face_h = int(fh * scale)

    resized_face = cv2.resize(face_img, (target_face_w, target_face_h), interpolation=cv2.INTER_AREA)

    x1 = int(center_x - target_face_w / 2)
    y1 = int(center_y - target_face_h / 2)
    x2 = x1 + target_face_w
    y2 = y1 + target_face_h

    # Clip coordinates to background
    src_x1 = max(0, -x1)
    src_y1 = max(0, -y1)
    src_x2 = target_face_w - max(0, x2 - w_bg)
    src_y2 = target_face_h - max(0, y2 - h_bg)

    dst_x1 = max(0, x1)
    dst_y1 = max(0, y1)
    dst_x2 = min(w_bg, x2)
    dst_y2 = min(h_bg, y2)

    frame = bg.copy()
    if dst_x2 > dst_x1 and dst_y2 > dst_y1:
        face_crop = resized_face[src_y1:src_y2, src_x1:src_x2]
        frame[dst_y1:dst_y2, dst_x1:dst_x2] = face_crop

    return frame

def main():
    root = Path(__file__).resolve().parent.parent
    head_path = root / "examples" / "musk_head.jpg"
    if not head_path.exists():
        raw_path = root / "examples" / "musk_resize.jpeg"
        raw_img = cv2.imread(str(raw_path))
        crop = raw_img[150:900, 380:1020]
        cv2.imwrite(str(head_path), crop)

    face_img = cv2.imread(str(head_path))
    output_path = root / "examples" / "test_camera_feed.mp4"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    w, h = 640, 480
    fps = 10
    total_frames = 150 # 15 seconds

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(str(output_path), fourcc, fps, (w, h))

    bg = create_office_background(w, h)

    print(f"Generating test feed to {output_path} ({total_frames} frames @ {fps}fps)...")

    for idx in range(total_frames):
        # 0s to 3s (frames 0..29): No face
        if idx < 30:
            frame = bg.copy()

        # 3s to 6s (frames 30..59): Face off-center left (center_x = 130)
        elif idx < 60:
            cx = 130
            cy = 240
            target_w = 220
            frame = overlay_face(bg, face_img, cx, cy, target_w)

        # 6s to 9s (frames 60..89): Face too far (small face, target_w = 85)
        elif idx < 90:
            cx = 320
            cy = 240
            target_w = 85
            frame = overlay_face(bg, face_img, cx, cy, target_w)

        # 9s to 13s (frames 90..129): Face good framing (centered, target_w = 260)
        elif idx < 130:
            cx = 320
            cy = 240
            target_w = 260
            frame = overlay_face(bg, face_img, cx, cy, target_w)

        # 13s to 15s (frames 130..149): Face too close (large face, target_w = 390)
        else:
            cx = 320
            cy = 240
            target_w = 390
            frame = overlay_face(bg, face_img, cx, cy, target_w)

        out.write(frame)

    out.release()
    print(f"Done! Test feed created at {output_path} ({output_path.stat().st_size} bytes)")

if __name__ == "__main__":
    main()
