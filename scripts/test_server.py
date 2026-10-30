"""Deterministic loopback fixtures; no third-party packages or external requests."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import struct
import time
import zlib

parser = argparse.ArgumentParser()
parser.add_argument("--port-file", required=True)
parser.add_argument("--fixture", required=True)
args = parser.parse_args()


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


rows = bytearray()
for y in range(360):
    rows.append(0)
    for x in range(640):
        if (x - 440) ** 2 + (y - 110) ** 2 < 42 ** 2:
            color = (255, 217, 150)
        elif y > 270 - abs(x - 210) * 0.48:
            color = (47 + x // 8, 68 + x // 10, 111 + x // 12)
        else:
            color = (104 + y // 4, 102 + y // 5, 186 + y // 7)
        rows.extend((*color, 255))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 640, 360, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b"")
Path(args.fixture).write_bytes(png)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/not-found":
            self.send_error(404)
            return
        if self.path == "/slow":
            time.sleep(1)
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        if self.path == "/oversized":
            self.send_header("Content-Length", str(81 * 1024 * 1024))
            self.end_headers()
            try:
                for _ in range(81):
                    self.wfile.write(b"x" * 1024 * 1024)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        payload = b"not an image" if self.path == "/invalid" else png
        if self.path != "/oversized-stream":
            self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        try:
            if self.path == "/oversized-stream":
                for _ in range(81):
                    self.wfile.write(b"x" * 1024 * 1024)
            else:
                self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *_):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
Path(args.port_file).write_text(str(server.server_port))
server.serve_forever()
