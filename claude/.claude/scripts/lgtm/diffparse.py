"""Parse `git diff` / `gh pr diff` unified output into model objects."""
from __future__ import annotations
import re
from lgtm.model import DiffLine, Hunk, FileDiff

_HUNK_RE = re.compile(r"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@")

def parse_unified_diff(text: str) -> list[FileDiff]:
    files: list[FileDiff] = []
    cur_path = None; cur_status = "M"; cur_hunks: list[Hunk] = []
    lines_buf: list[DiffLine] = []; hunk_header = ""; old_ln = new_ln = 0

    def flush_hunk():
        nonlocal lines_buf
        if hunk_header:
            cur_hunks.append(Hunk(hunk_id=f"F{len(files)}H{len(cur_hunks)}",
                                  header=hunk_header,
                                  old_start=hunk_old_start, new_start=hunk_new_start,
                                  lines=lines_buf))
        lines_buf = []

    def flush_file():
        nonlocal cur_hunks
        if cur_path is not None:
            files.append(FileDiff(path=cur_path, status=cur_status, hunks=cur_hunks))
        cur_hunks = []

    hunk_old_start = hunk_new_start = 0
    for raw in text.splitlines():
        if raw.startswith("diff --git "):
            flush_hunk(); hunk_header = ""; flush_file()
            # path = b-side (handles renames sanely)
            cur_path = raw.split(" b/", 1)[1] if " b/" in raw else raw.split()[-1]
            cur_status = "M"
        elif raw.startswith("new file mode"):
            cur_status = "A"
        elif raw.startswith("deleted file mode"):
            cur_status = "D"
        elif raw.startswith("@@"):
            flush_hunk()
            m = _HUNK_RE.match(raw)
            if m is None:
                continue
            hunk_old_start, hunk_new_start = int(m.group(1)), int(m.group(2))
            old_ln, new_ln = hunk_old_start, hunk_new_start
            hunk_header = raw
        elif hunk_header and raw[:1] in ("+", "-", " ", ""):
            if raw.startswith("+"):
                lines_buf.append(DiffLine("add", None, new_ln, raw[1:])); new_ln += 1
            elif raw.startswith("-"):
                lines_buf.append(DiffLine("del", old_ln, None, raw[1:])); old_ln += 1
            else:
                lines_buf.append(DiffLine("ctx", old_ln, new_ln, raw[1:])); old_ln += 1; new_ln += 1
    flush_hunk(); flush_file()
    return files
