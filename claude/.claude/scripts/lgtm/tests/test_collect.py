from lgtm.collect import pick_base


def test_pick_base_symbolic():
    assert pick_base("refs/remotes/origin/main", {"origin/main"}) == "origin/main"


def test_pick_base_fallback_order():
    assert pick_base(None, {"origin/master", "origin/develop"}) == "origin/master"
    assert pick_base(None, {"origin/develop"}) == "origin/develop"


def test_pick_base_nothing():
    assert pick_base(None, set()) == "HEAD"
