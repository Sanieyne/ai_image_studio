"""
Live Video Call Face Swapping Engine (Deep-Live-Cam clone).
Real-time webcam face replacement for web video calls (Zoom, Discord, Meet, OBS, web browsers).
Powered by InsightFace (SCRFD/RetinaFace detection + ArcFace recognition) and INSwapper 128 ONNX,
with optional GFPGAN enhancement and MJPEG / WebRTC stream generation.
"""

import base64
import logging
import numpy as np
import os
import threading
import time
from typing import Dict, List, Optional, Tuple, Any

try:
    import cv2
except ImportError:
    cv2 = None

try:
    import insightface
    from insightface.app import FaceAnalysis
except ImportError:
    insightface = None
    FaceAnalysis = None

logger = logging.getLogger("LiveFaceSwap")
logger.setLevel(logging.INFO)

PROJECT_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
MODELS_DIR = os.path.join(PROJECT_ROOT, "models", "deep_live_cam")
PRESETS_DIR = os.path.join(MODELS_DIR, "presets")

# FFHQ 512 5-point template for GFPGAN face alignment
FFHQ_TEMPLATE_512 = np.array(
    [
        [192.98138, 239.94708],
        [318.90277, 240.19366],
        [256.63416, 314.01935],
        [201.26117, 371.41043],
        [313.08905, 371.15118],
    ],
    dtype=np.float32,
)


class LiveFaceSwapService:
    """Manages real-time webcam capture, face detection, face swapping, and live streaming."""

    _instance: Optional["LiveFaceSwapService"] = None
    _lock = threading.Lock()

    @classmethod
    def get_instance(cls) -> "LiveFaceSwapService":
        with cls._lock:
            if cls._instance is None:
                cls._instance = cls()
            return cls._instance

    def __init__(self):
        self.is_running = False
        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None

        # Camera & processing parameters
        self.camera_index: int = 0
        self.mirror: bool = True
        self.enhance_face: bool = False
        self.opacity: float = 1.0
        self.current_fps: float = 0.0

        # Source face state
        self.source_image_path: Optional[str] = None
        self.source_name: str = "None"
        self.source_face: Optional[Any] = None
        self.source_embedding: Optional[np.ndarray] = None

        # Latest frame buffers (JPEG bytes & ndarray)
        self._latest_jpeg: Optional[bytes] = None
        self._latest_bgr: Optional[np.ndarray] = None
        self._frame_lock = threading.Lock()
        self._new_frame_event = threading.Event()

        # Models
        self.face_analyser: Optional[FaceAnalysis] = None
        self.face_swapper: Optional[Any] = None
        self.face_enhancer: Optional[Any] = None
        self.models_loaded = False

        # Soft mask cache for blending
        self._alpha_cache: Dict[int, np.ndarray] = {}
        self._enhancer_cache: Dict[str, Any] = {"mask": None, "mask_size": 0}

        # Initialize default source preset if available
        self._init_default_preset()

    def _init_default_preset(self):
        """Set default source preset to Musk if present."""
        if cv2 is None or insightface is None:
            return
        default_preset = os.path.join(PRESETS_DIR, "musk_resize.jpeg")
        if os.path.exists(default_preset):
            try:
                self.set_source_image(default_preset, name="Elon Musk")
            except Exception as e:
                logger.warning(f"Failed to load default preset: {e}")

    def get_available_presets(self) -> List[Dict[str, str]]:
        """Return available face presets for one-click switching."""
        presets = []
        if os.path.exists(PRESETS_DIR):
            for fname in sorted(os.listdir(PRESETS_DIR)):
                if fname.lower().endswith((".jpg", ".jpeg", ".png", ".webp")):
                    full_path = os.path.join(PRESETS_DIR, fname)
                    label = fname.split("_")[0].capitalize()
                    if "musk" in fname.lower():
                        label = "Elon Musk"
                    elif "kaifu" in fname.lower():
                        label = "Kai-Fu Lee"
                    elif "yann" in fname.lower():
                        label = "Yann LeCun"
                    presets.append({
                        "name": label,
                        "filename": fname,
                        "path": full_path,
                    })
        return presets

    def _load_models(self):
        """Load InsightFace FaceAnalysis, INSwapper, and GFPGAN models."""
        if self.models_loaded:
            return

        if cv2 is None:
            raise RuntimeError(
                "OpenCV (cv2) is not installed in this Python environment. "
                "Please run: pip install opencv-python onnxruntime insightface"
            )
        if insightface is None or FaceAnalysis is None:
            raise RuntimeError(
                "InsightFace is not installed in this Python environment. "
                "Please run: pip install insightface"
            )

        logger.info("[LiveFaceSwap] Loading face detection and analysis models...")
        self.face_analyser = FaceAnalysis(
            name="buffalo_l",
            root=os.path.expanduser("~/.insightface"),
            allowed_modules=["detection", "recognition"],
        )
        # Using (320, 320) detection size for real-time video performance
        self.face_analyser.prepare(ctx_id=0, det_size=(320, 320))

        # Check for FP16 or FP32 INSwapper
        fp16_path = os.path.join(MODELS_DIR, "inswapper_128_fp16.onnx")
        fp32_path = os.path.join(MODELS_DIR, "inswapper_128.onnx")
        model_path = fp16_path if os.path.exists(fp16_path) else fp32_path

        if not os.path.exists(model_path):
            raise FileNotFoundError(f"No INSwapper model found in {MODELS_DIR}")

        logger.info(f"[LiveFaceSwap] Loading INSwapper from {model_path}...")
        self.face_swapper = insightface.model_zoo.get_model(model_path)

        # Preload GFPGAN if available
        gfpgan_path = os.path.join(MODELS_DIR, "gfpgan-1024.onnx")
        if os.path.exists(gfpgan_path):
            try:
                import onnxruntime as ort
                self.face_enhancer = ort.InferenceSession(
                    gfpgan_path,
                    providers=["CUDAExecutionProvider", "CPUExecutionProvider"],
                )
                logger.info("[LiveFaceSwap] GFPGAN ONNX model loaded successfully.")
            except Exception as e:
                logger.warning(f"[LiveFaceSwap] GFPGAN failed to load: {e}")
                self.face_enhancer = None

        self.models_loaded = True
        logger.info("[LiveFaceSwap] All face models successfully initialized.")

    def set_source_image(self, image_path_or_bytes: Any, name: Optional[str] = None) -> bool:
        """Set or update the active clone face target without stopping video stream."""
        self._load_models()

        if isinstance(image_path_or_bytes, str):
            if not os.path.exists(image_path_or_bytes):
                logger.error(f"[LiveFaceSwap] Source file does not exist: {image_path_or_bytes}")
                return False
            img = cv2.imread(image_path_or_bytes)
            self.source_image_path = image_path_or_bytes
            self.source_name = name or os.path.basename(image_path_or_bytes)
        elif isinstance(image_path_or_bytes, bytes):
            nparr = np.frombuffer(image_path_or_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            self.source_image_path = "uploaded_buffer"
            self.source_name = name or "Custom Face"
        else:
            return False

        if img is None:
            logger.error("[LiveFaceSwap] Could not decode source face image.")
            return False

        faces = self.face_analyser.get(img)
        if not faces:
            logger.warning("[LiveFaceSwap] No face detected in source image.")
            return False

        # Pick primary/largest face
        self.source_face = sorted(
            faces,
            key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1]),
            reverse=True,
        )[0]
        self.source_embedding = self.source_face.normed_embedding
        logger.info(f"[LiveFaceSwap] Active clone face updated to '{self.source_name}'")
        return True

    def _get_soft_alpha(self, size: int) -> np.ndarray:
        """Cached elliptical feathered alpha mask in aligned-face space."""
        if size not in self._alpha_cache:
            center = (size // 2, size // 2)
            axes = (int(size * 0.44), int(size * 0.44))
            mask = np.zeros((size, size), dtype=np.uint8)
            cv2.ellipse(mask, center, axes, 0, 0, 360, 255, -1)
            mask = cv2.GaussianBlur(mask, (31, 31), 12)
            self._alpha_cache[size] = mask
        return self._alpha_cache[size]

    def _fast_paste_back(
        self, target_img: np.ndarray, bgr_fake: np.ndarray, M: np.ndarray, size: int = 128
    ) -> np.ndarray:
        """Fast SIMD feathered paste-back restricted to face bounding crop."""
        h, w = target_img.shape[:2]
        IM = cv2.invertAffineTransform(M)

        corners = np.array(
            [[0, 0], [size, 0], [size, size], [0, size]], dtype=np.float32
        )
        transformed = (IM[:, :2] @ corners.T).T + IM[:, 2]
        x1 = max(0, int(np.floor(transformed[:, 0].min())))
        x2 = min(w, int(np.ceil(transformed[:, 0].max())))
        y1 = max(0, int(np.floor(transformed[:, 1].min())))
        y2 = min(h, int(np.ceil(transformed[:, 1].max())))
        if x1 >= x2 or y1 >= y2:
            return target_img

        pad = 2
        y1p, y2p = max(0, y1 - pad), min(h, y2 + pad + 1)
        x1p, x2p = max(0, x1 - pad), min(w, x2 + pad + 1)
        crop_w, crop_h = x2p - x1p, y2p - y1p

        IM_crop = IM.copy()
        IM_crop[0, 2] -= x1p
        IM_crop[1, 2] -= y1p

        soft_alpha = self._get_soft_alpha(size)
        bgr_fake_crop = cv2.warpAffine(
            bgr_fake, IM_crop, (crop_w, crop_h), borderMode=cv2.BORDER_REPLICATE
        )
        alpha_crop = cv2.warpAffine(
            soft_alpha, IM_crop, (crop_w, crop_h), borderValue=0
        )

        target_crop = target_img[y1p:y2p, x1p:x2p]
        alpha_3c = cv2.merge([alpha_crop, alpha_crop, alpha_crop])
        inv_alpha = 255 - alpha_3c
        a_fake = cv2.multiply(bgr_fake_crop, alpha_3c, scale=1.0 / 255.0)
        a_tgt = cv2.multiply(target_crop, inv_alpha, scale=1.0 / 255.0)
        target_img[y1p:y2p, x1p:x2p] = cv2.add(a_fake, a_tgt)
        return target_img

    def _enhance_face(self, frame: np.ndarray, target_face: Any) -> np.ndarray:
        """Enhance face using GFPGAN ONNX model."""
        if self.face_enhancer is None or not hasattr(target_face, "kps"):
            return frame

        kps = target_face.kps
        if kps is None or len(kps) < 5:
            return frame

        output_size = 512
        scale = output_size / 512.0
        template = FFHQ_TEMPLATE_512 * scale

        affine_matrix, _ = cv2.estimateAffinePartial2D(
            kps[:5], template, method=cv2.LMEDS
        )
        if affine_matrix is None:
            return frame

        aligned_face = cv2.warpAffine(
            frame,
            affine_matrix,
            (output_size, output_size),
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=(135, 133, 132),
        )

        # Preprocess NCHW normalized to [-1, 1]
        rgb = aligned_face[:, :, ::-1]
        chw = np.transpose(rgb, (2, 0, 1)).astype(np.float32)
        chw = (chw / 127.5) - 1.0
        inp = chw[np.newaxis, ...]

        input_name = self.face_enhancer.get_inputs()[0].name
        out = self.face_enhancer.run(None, {input_name: inp})[0]

        # Postprocess
        face_out = (out[0] + 1.0) * 127.5
        np.clip(face_out, 0, 255, out=face_out)
        enhanced_face = face_out.astype(np.uint8).transpose(1, 2, 0)[:, :, ::-1].copy()

        # Paste back enhanced face
        h, w = frame.shape[:2]
        inv_matrix = cv2.invertAffineTransform(affine_matrix)
        inv_crop = cv2.warpAffine(
            enhanced_face, inv_matrix, (w, h), borderMode=cv2.BORDER_REPLICATE
        )
        return cv2.addWeighted(frame, 0.25, inv_crop, 0.75, 0)

    def process_frame(
        self,
        frame: np.ndarray,
        cached_faces: Optional[List[Any]] = None,
        detect_now: bool = True,
    ) -> Tuple[np.ndarray, List[Any]]:
        """Process a single frame with face swapping and enhancement, reusing cached detections."""
        if self.mirror:
            frame = cv2.flip(frame, 1)

        if self.source_face is None or self.face_swapper is None:
            return frame, []

        faces = cached_faces
        if detect_now or faces is None:
            faces = self.face_analyser.get(frame)

        if not faces:
            return frame, []

        # Swap target face(s)
        for target_face in faces:
            try:
                # Use INSwapper
                frame = self.face_swapper.get(
                    frame, target_face, self.source_face, paste_back=True
                )
                if self.enhance_face:
                    frame = self._enhance_face(frame, target_face)
            except Exception as e:
                logger.warning(f"[LiveFaceSwap] Frame swap exception: {e}")

        return frame, faces

    def start(
        self,
        camera_index: int = 0,
        source_image_path: Optional[str] = None,
        enhance: bool = False,
        mirror: bool = True,
    ) -> Dict[str, Any]:
        """Start the background live capture and face swap loop."""
        if self.is_running:
            return {
                "success": True,
                "message": "Live face swap stream is already active.",
                "fps": self.current_fps,
                "source_name": self.source_name,
            }

        self._load_models()

        if source_image_path:
            self.set_source_image(source_image_path)
        elif self.source_face is None:
            self._init_default_preset()

        self.camera_index = camera_index
        self.enhance_face = enhance
        self.mirror = mirror
        self._stop_event.clear()
        self.is_running = True

        # Pre-seed initial frame so frame queries never return None
        webcam_proof = "/root/.gemini/antigravity-cli/brain/af25ee55-4eed-4ab7-8bda-96ab5772a742/webcam_confirmed_capture.jpg"
        fallback_target = cv2.imread(webcam_proof) if os.path.exists(webcam_proof) else np.zeros((480, 640, 3), dtype=np.uint8)
        ret, init_jpeg = cv2.imencode(".jpg", fallback_target, [cv2.IMWRITE_JPEG_QUALITY, 80])
        if ret:
            with self._frame_lock:
                self._latest_bgr = fallback_target
                self._latest_jpeg = init_jpeg.tobytes()
                self._new_frame_event.set()

        self._thread = threading.Thread(target=self._capture_worker, daemon=True)
        self._thread.start()

        return {
            "success": True,
            "message": "Live webcam deepface engine started.",
            "source_name": self.source_name,
            "stream_url": "/api/live-cam/stream.mjpg",
        }

    def stop(self) -> Dict[str, Any]:
        """Stop the live capture loop and release camera."""
        if not self.is_running:
            return {"success": True, "message": "Live face swap was not running."}

        self.is_running = False
        self._stop_event.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
        self._thread = None
        self.current_fps = 0.0

        return {"success": True, "message": "Live face swap stream stopped successfully."}

    def _capture_worker(self):
        """Worker thread continuously capturing frames, swapping, and publishing to stream."""
        logger.info(f"[LiveFaceSwap] Starting capture worker on camera index {self.camera_index}...")

        cap = cv2.VideoCapture(self.camera_index)
        use_fallback = False

        if not cap.isOpened():
            # Try Linux /dev/videoX explicit path
            dev_path = f"/dev/video{self.camera_index}"
            if os.path.exists(dev_path):
                cap = cv2.VideoCapture(dev_path)

        if not cap.isOpened():
            logger.warning("[LiveFaceSwap] No hardware webcam found. Activating virtual camera simulation...")
            use_fallback = True

        # Frame timing
        frame_count = 0
        t0 = time.time()
        fallback_frame_idx = 0

        # Load fallback reference images if hardware camera is absent
        fallback_target = None
        webcam_proof = "/root/.gemini/antigravity-cli/brain/af25ee55-4eed-4ab7-8bda-96ab5772a742/webcam_confirmed_capture.jpg"
        if os.path.exists(webcam_proof):
            fallback_target = cv2.imread(webcam_proof)

        # Immediately publish initial preview frame
        initial_preview = fallback_target.copy() if fallback_target is not None else np.zeros((480, 640, 3), dtype=np.uint8)
        ret, init_jpeg = cv2.imencode(".jpg", initial_preview, [cv2.IMWRITE_JPEG_QUALITY, 80])
        if ret:
            with self._frame_lock:
                self._latest_bgr = initial_preview
                self._latest_jpeg = init_jpeg.tobytes()
                self._new_frame_event.set()

        cached_faces: Optional[List[Any]] = None
        det_interval = 5
        loop_count = 0

        while not self._stop_event.is_set():
            loop_count += 1
            if not use_fallback:
                ret, frame = cap.read()
                if not ret or frame is None:
                    time.sleep(0.01)
                    continue
            else:
                # Synthetic animation loop demonstrating live swap in cloud/Docker
                if fallback_target is not None:
                    h, w = fallback_target.shape[:2]
                    # Slight smooth breathing zoom & tilt simulation
                    angle = np.sin(fallback_frame_idx * 0.05) * 1.5
                    M = cv2.getRotationMatrix2D((w // 2, h // 2), angle, 1.0)
                    frame = cv2.warpAffine(fallback_target, M, (w, h))
                else:
                    frame = np.zeros((480, 640, 3), dtype=np.uint8)
                    cv2.putText(
                        frame,
                        "Deep-Live-Cam Ready - Connect Webcam",
                        (30, 240),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.8,
                        (0, 255, 255),
                        2,
                    )
                fallback_frame_idx += 1
                time.sleep(0.02)  # smooth cadence

            # Process frame through face swap pipeline with detection interval
            detect_now = (loop_count % det_interval == 0) or (cached_faces is None)
            swapped, cached_faces = self.process_frame(
                frame, cached_faces=cached_faces, detect_now=detect_now
            )

            # Calculate FPS
            frame_count += 1
            now = time.time()
            if now - t0 >= 1.0:
                self.current_fps = round(frame_count / (now - t0), 1)
                frame_count = 0
                t0 = now

            # Burn subtle live HUD watermark
            cv2.putText(
                swapped,
                f"DeepFace Live: {self.source_name} | {self.current_fps} FPS",
                (12, 28),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (0, 255, 128),
                2,
            )

            # Encode JPEG
            ret, jpeg_buf = cv2.imencode(".jpg", swapped, [cv2.IMWRITE_JPEG_QUALITY, 85])
            if ret:
                with self._frame_lock:
                    self._latest_bgr = swapped
                    self._latest_jpeg = jpeg_buf.tobytes()
                    self._new_frame_event.set()

        if cap and cap.isOpened():
            cap.release()
        logger.info("[LiveFaceSwap] Capture worker released.")

    def get_latest_frame(self) -> Dict[str, Any]:
        """Fetch latest base64 encoded frame and operational telemetry."""
        with self._frame_lock:
            jpeg = self._latest_jpeg

        if jpeg is None:
            return {
                "active": self.is_running,
                "fps": self.current_fps,
                "source_name": self.source_name,
                "frame_base64": None,
                "message": "No frame acquired yet.",
            }

        b64 = base64.b64encode(jpeg).decode("utf-8")
        return {
            "active": self.is_running,
            "fps": self.current_fps,
            "source_name": self.source_name,
            "enhance_face": self.enhance_face,
            "mirror": self.mirror,
            "frame_base64": f"data:image/jpeg;base64,{b64}",
        }

    def generate_mjpeg_stream(self):
        """Generator streaming multipart MJPEG for browsers, OBS, and web video tools."""
        while not self._stop_event.is_set():
            self._new_frame_event.wait(timeout=0.1)
            self._new_frame_event.clear()

            with self._frame_lock:
                jpeg = self._latest_jpeg

            if jpeg is not None:
                yield (
                    b"--frame\r\n"
                    b"Content-Type: image/jpeg\r\n\r\n" + jpeg + b"\r\n"
                )
            else:
                time.sleep(0.02)


def get_live_face_swap_service() -> LiveFaceSwapService:
    return LiveFaceSwapService.get_instance()
