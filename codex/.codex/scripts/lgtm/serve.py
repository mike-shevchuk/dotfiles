"""LGTM live server. Spec: rescue-serverless/.lgtm/design.md §3, §13.

The comment→Codex live loop bus:

    browser ──POST /comment──▶ inbox.jsonl   (Codex watcher picks it up)
    GET /events (SSE)  ◀── inbox.jsonl + outbox.jsonl merged by cursor

SSE streams BOTH files so a page refresh replays the full thread history
(Mike's questions from inbox, Codex's answers from outbox). The event id is
an "i.o" cursor (lines consumed per file) — stateless resume via the standard
Last-Event-ID header on EventSource auto-reconnect.
"""
from __future__ import annotations
import json
import re
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

PING_EVERY_S = 15          # SSE keepalive comment interval
POLL_S = 1.0               # outbox/inbox growth poll interval
_CURSOR_RE = re.compile(r"^(\d+)\.(\d+)$")


def _lan_ip() -> str:
    """Best-effort LAN IP (no traffic actually sent)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def _read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    out = []
    for ln in path.read_text(encoding="utf-8").splitlines():
        ln = ln.strip()
        if not ln:
            continue
        try:
            out.append(json.loads(ln))
        except json.JSONDecodeError:
            # a torn write mid-append; skip — next poll re-reads the full file
            continue
    return out


def _append_jsonl(path: Path, obj: dict) -> None:
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(obj, ensure_ascii=False) + "\n")


def _parse_cursor(v: str | None) -> tuple[int, int]:
    m = _CURSOR_RE.match(v or "")
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


class LgtmHandler(BaseHTTPRequestHandler):
    # set by make_server(): review dir with page.html / inbox.jsonl / outbox.jsonl
    root: Path
    key: str | None = None
    protocol_version = "HTTP/1.1"

    # ---- helpers ----
    def _deny(self, code: int, msg: str) -> None:
        body = msg.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authed(self, q: dict) -> bool:
        if not self.key:
            return True
        if q.get("key", [""])[0] == self.key:
            return True
        cookie = self.headers.get("Cookie", "")
        return f"lgtm_key={self.key}" in cookie

    def log_message(self, fmt: str, *args) -> None:  # stderr, house style
        print(f"  [{time.strftime('%H:%M:%S')}] {fmt % args}",
              file=__import__("sys").stderr)

    # ---- GET ----
    def do_GET(self) -> None:
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if not self._authed(q):
            return self._deny(403, "bad or missing ?key=")
        if u.path in ("/", "/page", "/page.html"):
            return self._page(q)
        if u.path == "/events":
            return self._events(q)
        if u.path == "/thread":
            return self._thread()
        return self._deny(404, "unknown path")

    def _page(self, q: dict) -> None:
        page = self.root / "page.html"
        if not page.exists():
            return self._deny(404, f"no page.html in {self.root}")
        body = page.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        if self.key and q.get("key", [""])[0] == self.key:
            # first visit with ?key= → cookie, so SSE/POST need no query key
            self.send_header("Set-Cookie", f"lgtm_key={self.key}; Path=/; SameSite=Lax")
        self.end_headers()
        self.wfile.write(body)

    def _thread(self) -> None:
        """Full merged thread as JSON (non-SSE consumers: nvim bridge, debug)."""
        msgs = (_read_jsonl(self.root / "inbox.jsonl")
                + _read_jsonl(self.root / "outbox.jsonl"))
        msgs.sort(key=lambda m: m.get("ts", ""))
        body = json.dumps(msgs, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _events(self, q: dict) -> None:
        # Last-Event-ID (auto-reconnect) wins over ?after= (initial connect)
        i, o = _parse_cursor(self.headers.get("Last-Event-ID")
                             or q.get("after", [""])[0])
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        inbox, outbox = self.root / "inbox.jsonl", self.root / "outbox.jsonl"
        last_ping = time.monotonic()
        try:
            while True:
                ib, ob = _read_jsonl(inbox), _read_jsonl(outbox)
                fresh = ([("i", n, m) for n, m in enumerate(ib) if n >= i]
                         + [("o", n, m) for n, m in enumerate(ob) if n >= o])
                fresh.sort(key=lambda t: t[2].get("ts", ""))
                for src, n, msg in fresh:
                    if src == "i":
                        i = n + 1
                    else:
                        o = n + 1
                    data = json.dumps(msg, ensure_ascii=False)
                    self.wfile.write(f"id: {i}.{o}\ndata: {data}\n\n".encode())
                    self.wfile.flush()
                if time.monotonic() - last_ping > PING_EVERY_S:
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
                    last_ping = time.monotonic()
                time.sleep(POLL_S)
        except (BrokenPipeError, ConnectionResetError):
            return  # client went away — normal

    # ---- POST ----
    def do_POST(self) -> None:
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if not self._authed(q):
            return self._deny(403, "bad or missing ?key=")
        if u.path != "/comment":
            return self._deny(404, "unknown path")
        try:
            n = int(self.headers.get("Content-Length", "0"))
            doc = json.loads(self.rfile.read(n).decode("utf-8"))
            text = str(doc["text"]).strip()
            if not text:
                raise ValueError("empty text")
        except (KeyError, ValueError, json.JSONDecodeError) as e:
            return self._deny(400, f"bad comment payload: {e}")
        msg = {
            "id": f"c-{int(time.time() * 1000)}",
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "who": "mike",
            "text": text,
            # anchors are optional — a global question has no hunk
            "file": doc.get("file") or "",
            "line": doc.get("line") or 0,
            "hunk": doc.get("hunk") or "",
            "finding_id": doc.get("finding_id") or "",
        }
        _append_jsonl(self.root / "inbox.jsonl", msg)
        body = json.dumps({"ok": True, "id": msg["id"]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def make_server(root: Path, port: int, key: str | None = None) -> ThreadingHTTPServer:
    handler = type("BoundLgtmHandler", (LgtmHandler,), {"root": root, "key": key})
    return ThreadingHTTPServer(("0.0.0.0", port), handler)


def run(root: Path, port: int, key: str | None = None) -> None:
    """Blocking serve loop; prints the LAN URL (house rule: loud recipes)."""
    import sys
    srv = make_server(root, port, key)
    (root / "server.pid").write_text(str(__import__("os").getpid()))
    url = f"http://{_lan_ip()}:{port}/" + (f"?key={key}" if key else "")
    print(f"  LGTM live: {url}", file=sys.stderr)
    print(url)  # stdout: machine-readable for recipes
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.shutdown()
        (root / "server.pid").unlink(missing_ok=True)
