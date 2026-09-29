from pathlib import Path

import pytest

from lgtm.collect import collect_diff, pick_base


def test_collect_diff_empty_base_raises_value_error():
    """refs intent must be explicit: passing base='' (e.g. from `--refs "" HEAD`)
    is not 'no refs requested' — it's a malformed refs request and must raise,
    not silently fall through to local-mode diff."""
    with pytest.raises(ValueError, match="порожній base/head"):
        collect_diff(Path("."), base="", head="HEAD")


def test_collect_diff_empty_head_raises_value_error():
    with pytest.raises(ValueError, match="порожній base/head"):
        collect_diff(Path("."), base="main", head="")


def test_pick_base_symbolic():
    assert pick_base("refs/remotes/origin/main", {"origin/main"}) == "origin/main"


def test_pick_base_fallback_order():
    assert pick_base(None, {"origin/master", "origin/develop"}) == "origin/master"
    assert pick_base(None, {"origin/develop"}) == "origin/develop"


def test_pick_base_nothing():
    assert pick_base(None, set()) == "HEAD"
