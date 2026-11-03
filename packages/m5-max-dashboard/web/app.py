"""Read-only loopback dashboard. Python standard library, no resident collector."""

import ctypes
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

ROOT = Path(__file__).resolve().parent
CORE = ctypes.CDLL(str(ROOT / "libmetrics.dylib"))
CORE.m5_sample.argtypes = [ctypes.POINTER(ctypes.c_char), ctypes.c_int, ctypes.c_int]
CORE.m5_sample.restype = None
SAMPLE_LOCK = Lock()
ASSETS = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/static/style.css": ("static/style.css", "text/css; charset=utf-8"),
    "/static/dashboard.js": ("static/dashboard.js", "text/javascript; charset=utf-8"),
    "/static/fonts/JetBrainsMono-Regular.woff2": ("static/fonts/JetBrainsMono-Regular.woff2", "font/woff2"),
    "/static/fonts/JetBrainsMono-SemiBold.woff2": ("static/fonts/JetBrainsMono-SemiBold.woff2", "font/woff2"),
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/api/stats":
            buffer = ctypes.create_string_buffer(32768)
            with SAMPLE_LOCK:
                CORE.m5_sample(buffer, len(buffer), 1)
            self.reply(200, "application/json", buffer.value)
        elif path == "/favicon.ico":
            self.reply(204, "image/x-icon", b"")
        elif path in ASSETS:
            filename, content_type = ASSETS[path]
            self.reply(200, content_type, (ROOT / filename).read_bytes())
        else:
            self.send_error(404)

    def reply(self, status, content_type, body):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_request(self, code="-", size="-"):
        if isinstance(code, int) and code >= 400:
            super().log_request(code, size)


if __name__ == "__main__":
    with ThreadingHTTPServer(("127.0.0.1", 8765), Handler) as server:
        print("M5 Max Dashboard - http://localhost:8765/", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
