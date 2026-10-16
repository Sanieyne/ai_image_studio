import unittest
import numpy as np
import cv2
import os
import sys

# Add python_engine to path
ENGINE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ENGINE_DIR not in sys.path:
    sys.path.insert(0, ENGINE_DIR)

from generation.live_face_swap import get_live_face_swap_service
from api.routes import (
    get_live_cam_status,
    get_live_cam_presets,
    start_live_cam,
    get_live_cam_frame,
    set_live_cam_source,
    stop_live_cam,
)
from api.schemas import LiveCamStartRequest, LiveCamSetSourceRequest


class TestLiveFaceSwapEngine(unittest.TestCase):
    def setUp(self):
        self.service = get_live_face_swap_service()

    def tearDown(self):
        self.service.stop()

    def test_presets_available(self):
        presets = self.service.get_available_presets()
        self.assertIsInstance(presets, list)
        self.assertGreater(len(presets), 0)
        preset_names = [p["name"] for p in presets]
        self.assertIn("Elon Musk", preset_names)

    def test_live_cam_lifecycle(self):
        # 1. Start live cam
        res = self.service.start(camera_index=0, mirror=True)
        self.assertTrue(res["success"])
        self.assertTrue(self.service.is_running)

        # 2. Get frame
        frame_data = self.service.get_latest_frame()
        self.assertTrue(frame_data["active"])
        self.assertIsNotNone(frame_data["frame_base64"])
        self.assertGreater(len(frame_data["frame_base64"]), 100)

        # 3. Switch clone target to Yann LeCun
        switch_ok = self.service.set_source_image(
            os.path.join(ENGINE_DIR, "models", "deep_live_cam", "presets", "yann-lecun_resize.jpg"),
            name="Yann LeCun",
        )
        self.assertTrue(switch_ok)
        self.assertEqual(self.service.source_name, "Yann LeCun")

        # 4. Stop live cam
        stop_res = self.service.stop()
        self.assertTrue(stop_res["success"])
        self.assertFalse(self.service.is_running)

    def test_api_routes(self):
        # Check presets route
        presets_resp = get_live_cam_presets()
        self.assertGreater(len(presets_resp.presets), 0)

        # Start via route
        start_resp = start_live_cam(LiveCamStartRequest(camera_index=0))
        self.assertTrue(start_resp.success)
        self.assertTrue(start_resp.active)

        # Fetch frame via route
        frame_resp = get_live_cam_frame()
        self.assertTrue(frame_resp.active)
        self.assertIsNotNone(frame_resp.frame_base64)

        # Switch source via route
        set_resp = set_live_cam_source(LiveCamSetSourceRequest(preset_name="Musk"))
        self.assertTrue(set_resp.success)

        # Stop via route
        stop_resp = stop_live_cam()
        self.assertTrue(stop_resp.success)
        self.assertFalse(stop_resp.active)


if __name__ == "__main__":
    unittest.main()
