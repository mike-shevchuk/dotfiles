"""LGTM data model. Spec: rescue-serverless/.lgtm/design.md §4, §12."""
from __future__ import annotations
import json
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional

@dataclass(frozen=True)
class DiffLine:
    kind: str                 # 'add' | 'del' | 'ctx'
    old_ln: Optional[int]
    new_ln: Optional[int]
    text: str

@dataclass(frozen=True)
class Hunk:
    hunk_id: str              # F<fileIdx>H<hunkIdx>, top-to-bottom (review_html convention)
    header: str
    old_start: int
    new_start: int
    lines: list[DiffLine]

    @property
    def additions(self) -> int: return sum(1 for l in self.lines if l.kind == "add")
    @property
    def deletions(self) -> int: return sum(1 for l in self.lines if l.kind == "del")
    @property
    def has_add(self) -> bool: return self.additions > 0
    @property
    def has_del(self) -> bool: return self.deletions > 0

@dataclass(frozen=True)
class FileDiff:
    path: str
    status: str               # 'M' | 'A' | 'D'
    hunks: list[Hunk]

    @property
    def additions(self) -> int: return sum(h.additions for h in self.hunks)
    @property
    def deletions(self) -> int: return sum(h.deletions for h in self.hunks)

@dataclass(frozen=True)
class ReviewMeta:
    lang: str                 # 'ukr' | 'eng' | 'both'
    # ref/base/mode/repo/generated are identity fields the CLI always recomputes
    # fresh for the current run (see cli.cmd_review) — a findings.json only needs
    # to carry `lang`; these default empty so a minimal meta block still loads.
    ref: str = ""
    base: str = ""
    mode: str = ""             # 'local' | 'refs' | 'pr'
    generated: str = ""
    repo: str = ""

@dataclass(frozen=True)
class Finding:
    id: str
    layer: str                # 'claude' | 'code-review' | 'bot' | 'coach'
    source: str
    file: str
    line: int
    hunk: str
    severity_emoji: str
    severity_score: int
    problem: dict
    harm: dict
    fix: dict
    agrees_with: list = field(default_factory=list)
    coach: Optional[dict] = None
    status: str = "open"
    thread: list = field(default_factory=list)

def save_findings(path: Path | str, meta: ReviewMeta, findings: list[Finding]) -> None:
    doc = {"meta": asdict(meta), "findings": [asdict(f) for f in findings]}
    Path(path).write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")

def load_findings(path: Path | str) -> tuple[ReviewMeta, list[Finding]]:
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    meta = ReviewMeta(**doc["meta"])
    findings = [Finding(**f) for f in doc.get("findings", [])]
    return meta, findings
