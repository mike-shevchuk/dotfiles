"""macOS Notification Center → JSON for pal's notifications folder: [{app, title, sub, body, t}], newest first.

Reads usernoted's own sqlite (what Notification Center shows; cleared ones are gone). Needs Full Disk Access for
the responsible app (Hammerspoon); without it prints {"error": "..."} and exits 1.
Self-check: python3 -I notifs.py --test
"""

from __future__ import annotations  # /usr/bin/python3 is 3.9

import json
import plistlib
import sqlite3
import sys
from pathlib import Path

DB = Path.home() / "Library/Group Containers/group.com.apple.usernoted/db2/db"
MAC_EPOCH = 978307200  # 2001-01-01, Core Data time


def parse(app: str, blob: bytes, when: float) -> dict | None:
    try:
        req = plistlib.loads(blob).get("req", {})
    except Exception:
        return None
    title, sub, body = req.get("titl") or "", req.get("subt") or "", req.get("body") or ""
    if not (title or body):
        return None
    return {"app": app, "title": title, "sub": sub, "body": body, "t": int((when or 0) + MAC_EPOCH)}


def main(limit: int = 400) -> int:
    try:
        con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
        rows = con.execute(
            "SELECT a.identifier, r.data, r.delivered_date FROM record r JOIN app a ON a.app_id = r.app_id "
            "ORDER BY r.delivered_date DESC LIMIT ?", (limit,)).fetchall()
    except Exception as e:  # no Full Disk Access shows up as "unable to open" / "authorization denied"
        print(json.dumps({"error": str(e)}))
        return 1
    print(json.dumps([n for n in (parse(*r) for r in rows) if n], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--test"]:
        blob = plistlib.dumps({"req": {"titl": "Hi", "body": "there"}}, fmt=plistlib.FMT_BINARY)
        assert parse("com.brave.Browser", blob, 0) == {"app": "com.brave.Browser", "title": "Hi", "sub": "",
                                                       "body": "there", "t": MAC_EPOCH}
        assert parse("x", plistlib.dumps({"req": {}}, fmt=plistlib.FMT_BINARY), 0) is None
        assert parse("x", b"junk", 0) is None
        print("ok")
        sys.exit(0)
    sys.exit(main())
