import json
import urllib.error
import urllib.request

import pytest

from tests.review_helpers import CONFIRMATIONS, make_render


@pytest.fixture
def store(tmp_path):
    from studio.review.store import ReviewStore

    make_render(tmp_path)
    return ReviewStore(tmp_path)


RID = "vyhub-run-recap-20261012-120000"


def test_new_render_is_pending(store):
    [item] = store.list()
    assert item["id"] == RID and item["status"] == "pending_review"
    detail = store.get(RID)
    assert detail["metadata"]["youtube_shorts"]["title"].startswith("+36 Rank Stars")
    assert detail["authorizations"] == {}


def test_authorize_requires_approval(store):
    from studio.review.store import ReviewError

    with pytest.raises(ReviewError, match="approved"):
        store.authorize(RID, "tiktok", CONFIRMATIONS, "AUTHORIZE")
    store.decide(RID, "approve", "looks good")
    with pytest.raises(ReviewError, match="confirm"):
        store.authorize(RID, "tiktok", dict(CONFIRMATIONS, checked_disclosure=False), "AUTHORIZE")
    with pytest.raises(ReviewError, match="AUTHORIZE"):
        store.authorize(RID, "tiktok", CONFIRMATIONS, "yes")
    with pytest.raises(ReviewError, match="platform"):
        store.authorize(RID, "instagram", CONFIRMATIONS, "AUTHORIZE")
    auth = store.authorize(RID, "tiktok", CONFIRMATIONS, "AUTHORIZE")
    assert auth["status"] == "authorized_not_published"
    detail = store.get(RID)
    assert detail["status"] == "approved"
    assert detail["authorizations"]["tiktok"]["valid"] is True
    assert "youtube_shorts" not in detail["authorizations"]  # each platform individually


def test_edit_after_approval_makes_stale(store, tmp_path):
    store.decide(RID, "approve", "")
    store.authorize(RID, "youtube_shorts", CONFIRMATIONS, "AUTHORIZE")
    manifest_path = tmp_path / "renders" / RID / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["metadata"]["youtube_shorts"]["title"] = "Changed title"
    manifest_path.write_text(json.dumps(manifest))
    detail = store.get(RID)
    assert detail["status"] == "stale"
    assert detail["authorizations"]["youtube_shorts"]["valid"] is False

    store.decide(RID, "approve", "re-checked")
    assert store.get(RID)["status"] == "approved"
    assert store.get(RID)["authorizations"]["youtube_shorts"]["valid"] is False  # needs a new authorization

    video = tmp_path / "renders" / RID / "final.mp4"
    video.write_bytes(video.read_bytes() + b"\0")
    assert store.get(RID)["status"] == "stale"


def test_reject_and_revoke(store):
    from studio.review.store import ReviewError

    store.decide(RID, "approve", "")
    store.authorize(RID, "tiktok", CONFIRMATIONS, "AUTHORIZE")
    store.revoke(RID, "tiktok")
    assert store.get(RID)["authorizations"]["tiktok"]["valid"] is False
    store.decide(RID, "reject", "counter overlaps the banner")
    assert store.get(RID)["status"] == "rejected"
    with pytest.raises(ReviewError):
        store.authorize(RID, "tiktok", CONFIRMATIONS, "AUTHORIZE")
    history = store.get(RID)["history"]
    assert [h["type"] for h in history] == ["decision", "authorization", "revocation", "decision"]


def test_publish_package_needs_valid_authorization(store, tmp_path):
    from studio.review.store import ReviewError

    with pytest.raises(ReviewError):
        store.package(RID, "tiktok")
    store.decide(RID, "approve", "")
    store.authorize(RID, "tiktok", CONFIRMATIONS, "AUTHORIZE")
    out = store.package(RID, "tiktok")
    assert (out / "final.mp4").is_file()
    caption = (out / "caption.txt").read_text()
    assert "paid in Pet Simulator 99 gems" in caption
    assert json.loads((out / "AUTHORIZATION.json").read_text())["platform"] == "tiktok"


def test_preview_for_browsers_without_h264(store, tmp_path):
    """Review preview is a VP9 transcode of final.mp4, created on demand and never part of the approved content."""
    from studio.media import probe

    before = store.content_hash(RID)
    preview = store.preview(RID)
    info = probe(preview)
    assert preview.name == "preview.webm" and info.vcodec == "vp9"
    assert (info.width, info.height) == (540, 960)
    assert store.preview(RID).stat().st_mtime_ns == preview.stat().st_mtime_ns  # cached
    assert store.content_hash(RID) == before


def test_post_without_token_rejected(tmp_path):
    import threading

    from studio.review.server import make_server

    make_render(tmp_path)
    httpd, token = make_server(tmp_path, port=0)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{httpd.server_address[1]}"
    try:
        body = json.dumps({"decision": "approve", "notes": ""}).encode()
        req = urllib.request.Request(f"{base}/api/renders/{RID}/decision", data=body, method="POST",
                                     headers={"Content-Type": "application/json"})
        with pytest.raises(urllib.error.HTTPError) as err:
            urllib.request.urlopen(req)
        assert err.value.code == 403
        req.add_header("X-Studio-Token", token)
        req.add_header("Origin", "https://evil.example")
        with pytest.raises(urllib.error.HTTPError) as err:
            urllib.request.urlopen(req)
        assert err.value.code == 403
        ok = urllib.request.Request(f"{base}/api/renders/{RID}/decision", data=body, method="POST",
                                    headers={"Content-Type": "application/json", "X-Studio-Token": token})
        assert urllib.request.urlopen(ok).status == 200
        # path traversal is refused
        with pytest.raises(urllib.error.HTTPError) as err:
            urllib.request.urlopen(f"{base}/media/{RID}/..%2F..%2Fsecret.txt")
        assert err.value.code in (400, 404)
        # video supports byte ranges for seeking
        rng = urllib.request.Request(f"{base}/media/{RID}/final.mp4", headers={"Range": "bytes=0-99"})
        resp = urllib.request.urlopen(rng)
        assert resp.status == 206 and len(resp.read()) == 100
    finally:
        httpd.shutdown()
