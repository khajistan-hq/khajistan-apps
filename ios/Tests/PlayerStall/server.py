"""A carrier that stops sending, for run.sh. Served on 127.0.0.1.

/tone.mp3?cut=N  a 180 s file, honest about its length, that answers any byte range but never
                 sends a byte past N: the response stops there and the connection is held open.
                 No error ever reaches the player, which is what a dropped mount looks like.
/tone.mp3?cut=N&heal=K
                 the same, but once a response has hung for HEAL_AFTER seconds, a request with the
                 same K is served in full: a carrier that comes back, for a retune to find. Only a
                 request that late counts, so the player's own read-ahead cannot heal it.
"""
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

MP3 = open(sys.argv[1], "rb").read()
HANG_SECONDS = 600
HEAL_AFTER = 15
hung_since = {}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_GET(self):
        url = urlparse(self.path)
        if url.path != "/tone.mp3":
            self.send_error(404)
            return
        query = parse_qs(url.query)
        cut = int(query.get("cut", [len(MP3)])[0])
        heal = query.get("heal", [None])[0]
        if heal in hung_since and time.time() - hung_since[heal] >= HEAL_AFTER:
            cut = len(MP3)
        start, end = 0, len(MP3) - 1
        wanted = self.headers.get("Range", "")
        if wanted.startswith("bytes="):
            first, _, last = wanted[6:].partition("-")
            start = int(first or 0)
            end = min(int(last), end) if last else end
        self.send_response(206 if wanted else 200)
        self.send_header("Content-Type", "audio/mpeg")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if wanted:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(MP3)}")
        self.end_headers()
        if start < cut:
            self.wfile.write(MP3[start : min(end + 1, cut)])
            self.wfile.flush()
        if end >= cut:
            if heal:
                hung_since.setdefault(heal, time.time())
            time.sleep(HANG_SECONDS)


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2])), Handler).serve_forever()
