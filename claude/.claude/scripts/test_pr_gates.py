"""Fails if pr-gates rules a (CI ✓0), c (fixture quiet), e (dev ⊇ head) break. Run: python3 -m pytest -q test_pr_gates.py  (or python3 test_pr_gates.py)"""

import importlib.util
import json
import os
import tempfile

spec = importlib.util.spec_from_file_location(
    "pg", os.path.join(os.path.dirname(os.path.abspath(__file__)), "pr-gates.py")
)
pg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pg)

D = tempfile.mkdtemp()
pg.DEMO_DIR = D
pg.contains = (
    lambda repo, head, sha: bool(head) and bool(sha) and sha.startswith(head[:3])
)  # fake ancestry: same prefix = contains


def row(ci="✓3 ✗0 ⏳0 ↷0", try_="r ✓/✓"):
    return dict(
        badges="CR✓ SMP✓ PT✓ JT✓ FE✓",
        behind="0",
        ci=ci,
        mergeable="MERGEABLE",
        linear="PUN-1",
        **{"try": try_},
    )


def put(name, **kw):
    json.dump(kw, open(f"{D}/{name}.json", "w"))


def gates(num=1, head="abc1", ci="✓3 ✗0 ⏳0 ↷0"):
    return pg.gates_of(row(ci), "rescue-serverless", 0, num, {"PUN-1"}, head=head)


def test_ci_zero_checks_is_red_unless_deploy_contains_head():
    pg.dev_deploy_sha = lambda repo: "zzz"
    assert gates(ci="✓0 ✗0 ⏳0 ↷2")["CI"][0] is False  # a
    pg.dev_deploy_sha = lambda repo: "abc9"
    assert gates(ci="✓0 ✗0 ⏳0 ↷2")["CI"][0] is True  # green train deploy contains head
    assert gates(ci="✓3 ✗0 ⏳0 ↷0")["CI"][0] is True


def test_pre_needs_dev_to_contain_head_and_quiet_fixture():
    pg.dev_deploy_sha = lambda repo: "abc9"
    put(
        "pr-1", dev_sha="abc9", finished="2026-11-10T00:00:00Z", fixture_alerts_before=0
    )
    assert gates()["PRE"][0] is True
    put(
        "pr-1", dev_sha="zzz9", finished="2026-11-10T00:00:00Z", fixture_alerts_before=0
    )
    assert gates()["PRE"][0] is False  # e: dev lacks the head
    put(
        "pr-1", dev_sha="abc9", finished="2026-11-10T00:00:00Z", fixture_alerts_before=2
    )
    assert gates()["PRE"][0] is False  # c: fixture had alerts
    put("pr-1", dev_sha="abc9", finished="2026-11-10T00:00:00Z")
    assert gates()["PRE"][0] is False  # c: new run, field missing
    put("pr-1", dev_sha="abc9", finished="2026-11-01T00:00:00Z")
    assert gates()["PRE"][0] is True  # c: old run grandfathered


def test_mike_needs_dev_to_contain_head():
    put("pr-1.mike", dev_sha="abc9", approved=True)
    assert gates()["MIKE"][0] is True
    put("pr-1.mike", dev_sha="zzz9", approved=True)
    assert gates()["MIKE"][0] is False


if __name__ == "__main__":
    for n, f in list(globals().items()):
        if n.startswith("test_"):
            f()
            print("ok", n)
