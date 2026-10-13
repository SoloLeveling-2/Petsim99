"""Publishing: every network call goes to a fake transport; nothing real is contacted."""
import hashlib
import json
import time
import urllib.parse

import pytest

from studio.publish import PublishError, tiktok, youtube
from studio.publish.http import Response
from studio.publish.oauth import TokenFile, pkce_pair
from tests.review_helpers import CONFIRMATIONS, make_render

RID = "vyhub-run-recap-20261012-120000"
POST_YT = {"title": "+36 Rank Stars | Pet Sim 99", "description": "Disclosure: paid service.\n\n#PS99",
           "tags": ["ps99", "pet sim 99"]}
POST_TT = {"caption": "+36 rank stars\nDisclosure: paid service.\n#ps99"}
CREATOR = {"creator_username": "tester", "privacy_level_options": ["PUBLIC_TO_EVERYONE", "SELF_ONLY"],
           "comment_disabled": False, "duet_disabled": True, "stitch_disabled": False,
           "max_video_post_duration_sec": 600}


class FakeHttp:
    """Scripted responses keyed by (method, url-prefix); records every call."""

    def __init__(self, script):
        self.script = list(script)
        self.calls = []

    def _next(self, method, url, headers=None, body=None):
        self.calls.append({"method": method, "url": url, "headers": headers or {}, "body": body})
        for i, (m, prefix, resp) in enumerate(self.script):
            if m == method and url.startswith(prefix):
                del self.script[i]
                return resp
        raise AssertionError(f"unexpected {method} {url}")

    def post_json(self, url, body, token=None, headers=None):
        return self._next("POST", url, {**(headers or {}), **({"Authorization": f"Bearer {token}"} if token else {})},
                          body)

    def post_form(self, url, fields):
        return self._next("POST", url, {}, fields)

    def put(self, url, data, headers):
        return self._next("PUT", url, headers, data)


def ok_json(data, status=200, headers=None):
    return Response(status, headers or {}, json.dumps(data).encode())


@pytest.fixture
def creds(tmp_path):
    d = tmp_path / "credentials"
    d.mkdir()
    (d / "youtube_client.json").write_text(json.dumps({"installed": {"client_id": "cid", "client_secret": "cs"}}))
    (d / "tiktok_client.json").write_text(json.dumps({"client_key": "ck", "client_secret": "cs"}))
    for stem in ("youtube", "tiktok"):
        TokenFile(d / f"{stem}_token.json").save({"access_token": "AT", "refresh_token": "RT",
                                                  "expires_at": int(time.time()) + 3600})
    return d


def test_pkce_encodings():
    v, c = pkce_pair()
    assert 43 <= len(v) <= 128 and "=" not in c and len(c) == 43
    v, c = pkce_pair(hex_challenge=True)
    assert c == hashlib.sha256(v.encode()).hexdigest()


def test_token_refresh_when_expired(tmp_path):
    tf = TokenFile(tmp_path / "t.json")
    tf.save({"access_token": "old", "refresh_token": "RT", "expires_at": int(time.time()) + 10})
    assert tf.access_token(lambda rt: {"access_token": "new", "expires_at": int(time.time()) + 3600}) == "new"
    assert tf.load()["refresh_token"] == "RT"  # kept when the refresh response omits it


def test_youtube_body_and_validation():
    body = youtube.build_body(POST_YT, "public", made_for_kids=False, paid_promotion=False)
    assert body["snippet"]["categoryId"] == "20" and body["status"] == {
        "privacyStatus": "public", "selfDeclaredMadeForKids": False, "containsSyntheticMedia": False}
    assert "paidProductPlacementDetails" not in body
    assert youtube.build_body(POST_YT, "unlisted", True, True)["paidProductPlacementDetails"] == {
        "hasPaidProductPlacement": True}
    with pytest.raises(PublishError, match="title"):
        youtube.build_body(dict(POST_YT, title="x" * 101), "public", False, False)
    with pytest.raises(PublishError, match="visibility"):
        youtube.build_body(POST_YT, "friends", False, False)


def test_youtube_upload_sends_exact_bytes(creds):
    data = b"\x00video-bytes" * 1000
    http = FakeHttp([
        ("POST", youtube.UPLOAD_URL, Response(200, {"location": "https://upload.example/session1"})),
        ("PUT", "https://upload.example/session1", ok_json({"id": "abc123", "status": {
            "privacyStatus": "private", "uploadStatus": "uploaded"}})),
    ])
    body = youtube.build_body(POST_YT, "public", False, False)
    result = youtube.upload(creds, data, body, http=http)
    assert result == {"remote_id": "abc123", "url": "https://www.youtube.com/shorts/abc123",
                      "visibility": "private", "upload_status": "uploaded"}
    init, put = http.calls
    assert "part=snippet,status" in init["url"] and init["headers"]["Authorization"] == "Bearer AT"
    assert init["headers"]["X-Upload-Content-Length"] == str(len(data))
    assert put["body"] == data and put["headers"]["Content-Range"] == f"bytes 0-{len(data) - 1}/{len(data)}"


def test_youtube_upload_resumes_after_server_error(creds):
    data = bytes(range(256)) * 40
    http = FakeHttp([
        ("POST", youtube.UPLOAD_URL, Response(200, {"location": "https://upload.example/s"})),
        ("PUT", "https://upload.example/s", Response(503)),
        ("PUT", "https://upload.example/s", Response(308, {"range": "bytes=0-4095"})),
        ("PUT", "https://upload.example/s", ok_json({"id": "v2", "status": {"privacyStatus": "public"}})),
    ])
    result = youtube.upload(creds, data, youtube.build_body(POST_YT, "public", False, False), http=http,
                            sleep=lambda s: None)
    assert result["remote_id"] == "v2"
    assert http.calls[2]["headers"]["Content-Range"] == f"bytes */{len(data)}"
    assert http.calls[3]["body"] == data[4096:]
    assert http.calls[3]["headers"]["Content-Range"] == f"bytes 4096-{len(data) - 1}/{len(data)}"


def test_youtube_upload_client_error_is_reported(creds):
    http = FakeHttp([("POST", youtube.UPLOAD_URL, ok_json({"error": {"message": "quotaExceeded"}}, 403))])
    with pytest.raises(PublishError, match="refused.*quotaExceeded"):
        youtube.upload(creds, b"x", youtube.build_body(POST_YT, "public", False, False), http=http)


def test_tiktok_chunk_plan():
    assert tiktok.chunk_plan(3 << 20) == (3 << 20, 1)
    assert tiktok.chunk_plan(53_220_031) == (53_220_031, 1)
    size = 150_000_123
    chunk, count = tiktok.chunk_plan(size)
    assert chunk == 10 << 20 and count == size // chunk
    assert size - chunk * (count - 1) <= 128 << 20  # last chunk absorbs the remainder


def test_tiktok_post_info_rules():
    info = tiktok.build_post_info(POST_TT, "public", CREATOR, 45.7, paid_promotion=False)
    assert info["privacy_level"] == "PUBLIC_TO_EVERYONE" and info["brand_organic_toggle"] is True
    assert info["disable_duet"] is True and info["brand_content_toggle"] is False and info["is_aigc"] is False
    with pytest.raises(PublishError, match="only allows: public, private"):
        tiktok.build_post_info(POST_TT, "followers", CREATOR, 45.7, False)
    with pytest.raises(PublishError, match="at most 600s"):
        tiktok.build_post_info(POST_TT, "public", CREATOR, 601, False)
    with pytest.raises(PublishError, match="branded"):
        tiktok.build_post_info(POST_TT, "private", CREATOR, 10, True)


def test_tiktok_upload_chunks_and_polls(creds):
    size = 70 << 20  # > 64 MB, so chunked
    data = bytes(size)
    chunk, count = tiktok.chunk_plan(size)
    script = [("POST", tiktok.INIT_URL, ok_json({"data": {"publish_id": "p1", "upload_url": "https://up.tt/u"},
                                                 "error": {"code": "ok"}}))]
    script += [("PUT", "https://up.tt/u", Response(206))] * (count - 1) + [("PUT", "https://up.tt/u", Response(201))]
    script += [("POST", tiktok.STATUS_URL, ok_json({"data": {"status": "PROCESSING_UPLOAD"}, "error": {"code": "ok"}})),
               ("POST", tiktok.STATUS_URL, ok_json({"data": {"status": "PUBLISH_COMPLETE",
                                                             "publicaly_available_post_id": [777]},
                                                    "error": {"code": "ok"}}))]
    http = FakeHttp(script)
    info = tiktok.build_post_info(POST_TT, "public", CREATOR, 30, False)
    result = tiktok.upload(creds, data, info, http=http, sleep=lambda s: None)
    assert result == {"remote_id": "p1", "status": "published", "url": None, "post_ids": [777]}
    init = http.calls[0]["body"]
    assert init["source_info"] == {"source": "FILE_UPLOAD", "video_size": size, "chunk_size": chunk,
                                   "total_chunk_count": count}
    puts = [c for c in http.calls if c["method"] == "PUT"]
    assert b"".join(p["body"] for p in puts) == data
    assert puts[-1]["headers"]["Content-Range"].endswith(f"-{size - 1}/{size}")


def test_tiktok_unaudited_error_has_hint(creds):
    http = FakeHttp([("POST", tiktok.INIT_URL, ok_json({"data": {}, "error": {
        "code": "unaudited_client_can_only_post_to_private_accounts", "message": "nope"}}, 403))])
    with pytest.raises(PublishError, match="not audited"):
        tiktok.upload(creds, b"x" * 100, tiktok.build_post_info(POST_TT, "private", CREATOR, 5, False), http=http)


def test_store_publish_gate_and_history(tmp_path):
    from studio.review.store import ReviewError, ReviewStore

    make_render(tmp_path)
    store = ReviewStore(tmp_path)
    with pytest.raises(ReviewError, match="no valid authorization"):
        store.publish_target(RID, "tiktok")
    store.decide(RID, "approve")
    store.authorize(RID, "tiktok", CONFIRMATIONS, "AUTHORIZE")
    target = store.publish_target(RID, "tiktok")
    assert target["post"]["caption"] and target["video"].name == "final.mp4"
    with pytest.raises(ReviewError, match="no valid authorization"):
        store.publish_target(RID, "youtube_shorts")  # authorized per platform
    store.record_publication(RID, "tiktok", target["content"], {"status": "published", "remote_id": "p1",
                                                                 "secret": "dropped"})
    with pytest.raises(ReviewError, match="already posted"):
        store.publish_target(RID, "tiktok")
    assert store.publish_target(RID, "tiktok", again=True)
    [pub] = store.get(RID)["publications"]["tiktok"]
    assert pub["remote_id"] == "p1" and "secret" not in pub
    assert store.get(RID)["authorizations"]["tiktok"]["valid"] is True  # posting does not void the authorization


def test_cli_publish_refuses_without_authorization_or_choices(tmp_path, monkeypatch, creds, capsys):
    from studio import cli
    from studio.review.store import ReviewStore

    monkeypatch.setattr("studio.publish.CREDENTIALS", creds)
    make_render(tmp_path)
    assert cli.main(["--workspace", str(tmp_path), "publish", RID, "youtube_shorts", "--dry-run"]) == 1
    assert "no valid authorization" in capsys.readouterr().out
    store = ReviewStore(tmp_path)
    store.decide(RID, "approve")
    store.authorize(RID, "youtube_shorts", CONFIRMATIONS, "AUTHORIZE")
    assert cli.main(["--workspace", str(tmp_path), "publish", RID, "youtube_shorts", "--dry-run"]) == 1
    assert "--paid-promotion" in capsys.readouterr().out
    assert cli.main(["--workspace", str(tmp_path), "publish", RID, "youtube_shorts", "--dry-run",
                     "--paid-promotion", "no"]) == 1
    assert "--made-for-kids" in capsys.readouterr().out
    rc = cli.main(["--workspace", str(tmp_path), "publish", RID, "youtube_shorts", "--dry-run",
                   "--paid-promotion", "no", "--made-for-kids", "no"])
    out = capsys.readouterr().out
    assert rc == 0 and "Dry run: nothing was posted." in out and "+36 Rank Stars" in out
    assert not store.get(RID)["publications"]


def test_cli_publish_needs_typed_confirmation_then_records(tmp_path, monkeypatch, creds, capsys):
    from studio import cli
    from studio.review.store import ReviewStore

    monkeypatch.setattr("studio.publish.CREDENTIALS", creds)
    make_render(tmp_path)
    store = ReviewStore(tmp_path)
    store.decide(RID, "approve")
    store.authorize(RID, "youtube_shorts", CONFIRMATIONS, "AUTHORIZE")
    args = ["--workspace", str(tmp_path), "publish", RID, "youtube_shorts", "--paid-promotion", "no",
            "--made-for-kids", "no"]
    uploads = []
    monkeypatch.setattr("studio.publish.youtube.upload", lambda cred, data, body: uploads.append((data, body)) or {
        "remote_id": "yt1", "url": "https://www.youtube.com/shorts/yt1", "visibility": "private"})
    monkeypatch.setattr("builtins.input", lambda prompt: "yes")
    assert cli.main(args) == 1 and not uploads
    assert "Cancelled" in capsys.readouterr().out
    monkeypatch.setattr("builtins.input", lambda prompt: "POST")
    assert cli.main(args) == 0
    out = capsys.readouterr().out
    assert "https://www.youtube.com/shorts/yt1" in out and "set the visibility to private" in out
    data, body = uploads[0]
    assert hashlib.sha256(data).hexdigest() == store.get(RID)["content"]["video_sha256"]
    [pub] = store.get(RID)["publications"]["youtube_shorts"]
    assert pub["remote_id"] == "yt1" and pub["options"]["made_for_kids"] is False
    assert cli.main(args) == 1 and "already posted" in capsys.readouterr().out
    assert len(uploads) == 1


def test_connect_finishes_from_pasted_redirect(creds):
    from studio.publish.oauth import Pending

    opened = []
    http = FakeHttp([("POST", youtube.TOKEN_URL, ok_json({"access_token": "A1", "refresh_token": "R1",
                                                          "expires_in": 3599}))])

    def no_browser_return(state, auth_url=None):
        raise PublishError("sign-in timed out")

    with pytest.raises(PublishError, match="timed out"):
        youtube.connect(creds, opened.append, http=http, receive=no_browser_return)
    state = urllib.parse.parse_qs(urllib.parse.urlparse(opened[0]).query)["state"][0]
    with pytest.raises(PublishError, match="different sign-in"):
        youtube.connect(creds, opened.append, http=http, redirect_url="http://127.0.0.1:8766/callback/?state=x&code=c")
    with pytest.raises(PublishError, match="code="):
        youtube.connect(creds, opened.append, http=http, redirect_url=f"http://127.0.0.1:8766/callback/?state={state}")
    token = youtube.connect(creds, opened.append, http=http,
                            redirect_url=f"http://127.0.0.1:8766/callback/?state={state}&code=4%2Fabc&scope=x")
    assert token["access_token"] == "A1" and len(opened) == 1
    assert http.calls[-1]["body"]["code"] == "4/abc" and http.calls[-1]["body"]["code_verifier"]
    assert not Pending(creds / "youtube_pending.json").path.exists()
