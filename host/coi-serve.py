#!/usr/bin/env python3
# host/coi-serve.py <port> <dir> [bind] — serve a directory with the two
# cross-origin-isolation headers (COOP same-origin, COEP require-corp), so a
# page gets SharedArrayBuffer: the stock `lg -w` lane's key ring needs it
# (host/ABI.md, "COI"; the JSPI lane does not, D91). Threaded, because a page
# fetches index.html, a multi-megabyte module and a service worker at once.
# Binds 127.0.0.1 unless a third argument says otherwise.
import http.server, os, sys

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8301
directory = sys.argv[2] if len(sys.argv) > 2 else "."
host = sys.argv[3] if len(sys.argv) > 3 else "127.0.0.1"
os.chdir(directory)


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer.allow_reuse_address = True
httpd = http.server.ThreadingHTTPServer((host, port), Handler)
print(f"COI server on http://{host}:{port}/ serving {directory}", flush=True)
httpd.serve_forever()
