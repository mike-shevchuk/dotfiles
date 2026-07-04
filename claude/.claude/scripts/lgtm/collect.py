"""Collect the diff to review: local branch (merge-base + uncommitted), two refs, or a PR."""
from __future__ import annotations
import subprocess
from pathlib import Path


def _run(cmd: list[str], cwd: Path) -> str:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=True).stdout


def pick_base(symbolic_ref_out: str | None, existing_refs: set[str]) -> str:
    if symbolic_ref_out:
        return symbolic_ref_out.strip().replace("refs/remotes/", "")
    for cand in ("origin/main", "origin/master", "origin/develop"):
        if cand in existing_refs:
            return cand
    return "HEAD"


def collect_diff(repo: Path, mode: str = "local", pr: int | None = None,
                 base: str | None = None, head: str | None = None) -> tuple[str, dict]:
    if mode == "pr":
        text = _run(["gh", "pr", "diff", str(pr)], repo)
        return text, {"ref": f"pr{pr}", "base": "(github)", "mode": "pr"}
    if mode == "refs":
        text = _run(["git", "diff", f"{base}...{head}"], repo)
        return text, {"ref": head, "base": base, "mode": "refs"}
    # local: default-branch merge-base -> HEAD, uncommitted included (= prefix-v)
    try:
        sym = _run(["git", "symbolic-ref", "refs/remotes/origin/HEAD"], repo)
    except subprocess.CalledProcessError:
        sym = None
    refs = set(_run(["git", "for-each-ref", "--format=%(refname:short)",
                     "refs/remotes"], repo).split())
    b = pick_base(sym, refs)
    mb = _run(["git", "merge-base", b, "HEAD"], repo).strip() if b != "HEAD" else "HEAD"
    text = _run(["git", "diff", mb], repo)
    branch = _run(["git", "branch", "--show-current"], repo).strip() or "HEAD"
    return text, {"ref": branch, "base": b, "mode": "local"}
