"""Serves build/web on http://localhost:8060 for testing the web export.

Browsers won't run Godot web exports from file://. The cross-origin isolation headers are only
needed for threaded exports, but sending them keeps local testing identical to itch.io with
SharedArrayBuffer support enabled.
"""

import functools
import http.server
import pathlib
import sys

PORT = 8060
ROOT = pathlib.Path(__file__).resolve().parent.parent / "build" / "web"


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    if not (ROOT / "index.html").exists():
        sys.exit(f"No export found in {ROOT}. Run tools/export_web.sh first.")
    handler = functools.partial(Handler, directory=str(ROOT))
    print(f"Serving {ROOT} at http://localhost:{PORT}")
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), handler).serve_forever()
