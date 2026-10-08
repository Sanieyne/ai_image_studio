"""Answer /health with a failure reason when the engine cannot start.

The cloud startup script runs this on port 8000 when the self-test fails, so the
backend learns why at once instead of waiting for its provisioning timeout:

    GET /health -> 200 {"status": "failed", "reason": "...", "models": []}

Standard library only (it must work when the engine's dependencies are broken).
"""
from __future__ import annotations

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


def make_handler(reason: str):
    body = json.dumps({"status": "failed", "reason": reason[:2000], "model_loaded": False, "models": []}).encode()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            if self.path.split("?")[0] in ("/health", "/ping"):
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, *args):  # quiet
            pass

    return Handler


def main() -> None:
    # usage: failure_server.py <reason-file> [port]
    reason = open(sys.argv[1], encoding="utf-8", errors="replace").read().strip() or "Engine failed to start."
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8000
    HTTPServer(("0.0.0.0", port), make_handler(reason)).serve_forever()


if __name__ == "__main__":
    main()
