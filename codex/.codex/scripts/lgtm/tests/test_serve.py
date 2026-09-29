"""Tests for the LGTM live server (serve.py): comment POST, SSE merge, auth."""
import json
import threading
import time
import urllib.request
from pathlib import Path

from lgtm.serve import make_server, _parse_cursor, _read_jsonl


def _start(tmp_path: Path, key=None):
    (tmp_path / "page.html").write_text("<html>ok</html>", encoding="utf-8")
    srv = make_server(tmp_path, 0, key)  # port 0 = OS-assigned, no collisions
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    return srv, f"http://127.0.0.1:{srv.server_address[1]}"


def _post(url: str, doc: dict) -> dict:
    req = urllib.request.Request(url, data=json.dumps(doc).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def test_comment_appends_inbox(tmp_path):
    srv, base = _start(tmp_path)
    try:
        out = _post(f"{base}/comment", {"text": "чому тут 403, а не 404?",
                                        "hunk": "F1H1", "file": "a.py", "line": 7})
        assert out["ok"] and out["id"].startswith("c-")
        msgs = _read_jsonl(tmp_path / "inbox.jsonl")
        assert len(msgs) == 1
        assert msgs[0]["who"] == "mike" and msgs[0]["hunk"] == "F1H1"
        assert msgs[0]["file"] == "a.py" and msgs[0]["line"] == 7
    finally:
        srv.shutdown()


def test_comment_rejects_empty_text(tmp_path):
    srv, base = _start(tmp_path)
    try:
        req = urllib.request.Request(f"{base}/comment", data=b'{"text":"  "}',
                                     headers={"Content-Type": "application/json"})
        try:
            urllib.request.urlopen(req)
            assert False, "expected 400"
        except urllib.error.HTTPError as e:
            assert e.code == 400
        assert not (tmp_path / "inbox.jsonl").exists()
    finally:
        srv.shutdown()


def test_key_guards_all_routes_and_cookie_flows(tmp_path):
    srv, base = _start(tmp_path, key="s3cret")
    try:
        try:
            urllib.request.urlopen(f"{base}/page")
            assert False, "expected 403"
        except urllib.error.HTTPError as e:
            assert e.code == 403
        with urllib.request.urlopen(f"{base}/page?key=s3cret") as r:
            assert r.status == 200
            assert "lgtm_key=s3cret" in (r.headers.get("Set-Cookie") or "")
        # cookie alone (no query key) must authenticate
        req = urllib.request.Request(f"{base}/thread",
                                     headers={"Cookie": "lgtm_key=s3cret"})
        with urllib.request.urlopen(req) as r:
            assert r.status == 200
    finally:
        srv.shutdown()


def test_sse_replays_history_and_merges_both_files(tmp_path):
    (tmp_path / "inbox.jsonl").write_text(
        '{"id":"c-1","ts":"2026-07-06T10:00:00","who":"mike","text":"q1","hunk":"F1H1"}\n',
        encoding="utf-8")
    (tmp_path / "outbox.jsonl").write_text(
        '{"id":"a-1","ts":"2026-07-06T10:00:05","who":"claude","text":"a1","hunk":"F1H1"}\n',
        encoding="utf-8")
    srv, base = _start(tmp_path)
    try:
        req = urllib.request.Request(f"{base}/events?after=0.0")
        with urllib.request.urlopen(req, timeout=5) as r:
            raw, deadline = b"", time.time() + 4
            while raw.count(b"\n\n") < 2 and time.time() < deadline:
                raw += r.read1(4096)
        events = [e for e in raw.decode().split("\n\n") if e.startswith("id:")]
        assert len(events) == 2
        # chronological: mike question first, claude answer second; cursor advances
        assert '"q1"' in events[0] and events[0].startswith("id: 1.0")
        assert '"a1"' in events[1] and events[1].startswith("id: 1.1")
    finally:
        srv.shutdown()


def test_thread_endpoint_merges_sorted(tmp_path):
    (tmp_path / "outbox.jsonl").write_text(
        '{"id":"a-1","ts":"2026-07-06T10:00:05","who":"claude","text":"a1"}\n',
        encoding="utf-8")
    (tmp_path / "inbox.jsonl").write_text(
        '{"id":"c-1","ts":"2026-07-06T10:00:00","who":"mike","text":"q1"}\n',
        encoding="utf-8")
    srv, base = _start(tmp_path)
    try:
        with urllib.request.urlopen(f"{base}/thread") as r:
            msgs = json.loads(r.read())
        assert [m["id"] for m in msgs] == ["c-1", "a-1"]  # sorted by ts
    finally:
        srv.shutdown()


def test_parse_cursor_tolerates_garbage():
    assert _parse_cursor("3.7") == (3, 7)
    assert _parse_cursor(None) == (0, 0)
    assert _parse_cursor("lol") == (0, 0)
