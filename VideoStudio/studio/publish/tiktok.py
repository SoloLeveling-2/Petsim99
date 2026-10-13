"""TikTok Content Posting API (Direct Post): OAuth sign-in and chunked upload of one video.

Setup (once): at developers.tiktok.com create an app (platform: Desktop), add Login Kit
and Content Posting API with Direct Post enabled, request the scopes user.info.basic and
video.publish, register the redirect URI http://127.0.0.1:8766/callback/ and save
{"client_key": "...", "client_secret": "..."} as credentials/tiktok_client.json.

Until TikTok audits the app, posts are limited to private (SELF_ONLY) viewing and TikTok
may require the account itself to be private.
"""
from __future__ import annotations

import json
import secrets
import time
import urllib.parse
from pathlib import Path

from . import PublishError
from .http import Http
from .oauth import REDIRECT_URI, TokenFile, expiry, pkce_pair, receive_code

SCOPES = "user.info.basic,video.publish"
AUTH_URL = "https://www.tiktok.com/v2/auth/authorize/"
API = "https://open.tiktokapis.com/v2"
TOKEN_URL = f"{API}/oauth/token/"
CREATOR_URL = f"{API}/post/publish/creator_info/query/"
INIT_URL = f"{API}/post/publish/video/init/"
STATUS_URL = f"{API}/post/publish/status/fetch/"
VISIBILITY = {"public": "PUBLIC_TO_EVERYONE", "friends": "MUTUAL_FOLLOW_FRIENDS",
              "followers": "FOLLOWER_OF_CREATOR", "private": "SELF_ONLY"}
MIN_CHUNK, MAX_CHUNK, CHUNK = 5 << 20, 64 << 20, 10 << 20
CAPTION_MAX = 2200


def client(cred_dir: Path) -> dict:
    path = Path(cred_dir) / "tiktok_client.json"
    if not path.is_file():
        raise PublishError(f"missing {path}: create a TikTok developer app (Login Kit + Content Posting API) "
                           'and save {"client_key": "...", "client_secret": "..."} there')
    data = json.loads(path.read_text(encoding="utf-8"))
    if not data.get("client_key") or not data.get("client_secret"):
        raise PublishError(f"{path} needs client_key and client_secret")
    return data


def tokens(cred_dir: Path) -> TokenFile:
    return TokenFile(Path(cred_dir) / "tiktok_token.json")


def _token_call(http: Http, fields: dict) -> dict:
    resp = http.post_form(TOKEN_URL, fields)
    data = resp.json()
    if resp.status != 200 or "access_token" not in data:
        raise PublishError(f"TikTok sign-in failed ({resp.status}): "
                           f"{data.get('error_description') or data.get('error') or resp.text()}")
    return expiry(data)


def connect(cred_dir: Path, open_url, http: Http | None = None, receive=receive_code) -> dict:
    http = http or Http(timeout=60)
    c = client(cred_dir)
    verifier, challenge = pkce_pair(hex_challenge=True)
    state = secrets.token_urlsafe(16)
    open_url(AUTH_URL + "?" + urllib.parse.urlencode({
        "client_key": c["client_key"], "scope": SCOPES, "response_type": "code", "redirect_uri": REDIRECT_URI,
        "state": state, "code_challenge": challenge, "code_challenge_method": "S256"}))
    code = receive(state)
    return tokens(cred_dir).save(_token_call(http, {
        "client_key": c["client_key"], "client_secret": c["client_secret"], "code": code,
        "grant_type": "authorization_code", "redirect_uri": REDIRECT_URI, "code_verifier": verifier}))


def _access_token(cred_dir: Path, http: Http) -> str:
    def refresh(refresh_token: str) -> dict:
        c = client(cred_dir)
        return _token_call(http, {"client_key": c["client_key"], "client_secret": c["client_secret"],
                                  "grant_type": "refresh_token", "refresh_token": refresh_token})
    return tokens(cred_dir).access_token(refresh)


def _api(http: Http, url: str, token: str, body: dict) -> dict:
    resp = http.post_json(url, body, token)
    payload = resp.json()
    err = payload.get("error") or {}
    if resp.status != 200 or err.get("code", "ok") != "ok":
        hint = {"unaudited_client_can_only_post_to_private_accounts":
                    " (TikTok has not audited this app yet: make the TikTok account private, or wait for the audit)",
                "privacy_level_option_mismatch": " (pick a visibility this account offers)",
                "spam_risk_too_many_posts": " (daily post limit reached; try tomorrow)"}.get(err.get("code"), "")
        raise PublishError(f"TikTok error {resp.status} {err.get('code') or ''}: "
                           f"{err.get('message') or resp.text()}{hint}")
    return payload.get("data") or {}


def creator_info(cred_dir: Path, http: Http | None = None) -> dict:
    http = http or Http(timeout=60)
    return _api(http, CREATOR_URL, _access_token(cred_dir, http), {})


def chunk_plan(size: int) -> tuple[int, int]:
    """(chunk_size, total_chunk_count) per TikTok's rules: one chunk up to 64 MB, otherwise
    10 MB chunks with the remainder merged into the last one."""
    if size <= 0:
        raise PublishError("empty video file")
    if size <= MAX_CHUNK:
        return size, 1
    return CHUNK, size // CHUNK


def build_post_info(post: dict, visibility: str, creator: dict, duration: float, paid_promotion: bool) -> dict:
    caption = post["caption"]
    privacy = VISIBILITY.get(visibility)
    offered = creator.get("privacy_level_options") or []
    problems = []
    if privacy is None:
        problems.append(f"TikTok visibility must be one of {', '.join(VISIBILITY)}")
    elif privacy not in offered:
        names = [k for k, v in VISIBILITY.items() if v in offered]
        problems.append(f"this account only allows: {', '.join(names) or 'nothing (posting unavailable)'}")
    if len(caption.encode("utf-16-le")) // 2 > CAPTION_MAX:
        problems.append(f"caption over {CAPTION_MAX} characters")
    max_sec = creator.get("max_video_post_duration_sec")
    if max_sec and duration > max_sec:
        problems.append(f"video is {duration:.1f}s but this account can post at most {max_sec}s")
    if paid_promotion and privacy == "SELF_ONLY":
        problems.append("TikTok does not allow branded (paid) content to be private")
    if problems:
        raise PublishError("; ".join(problems))
    return {"title": caption, "privacy_level": privacy,
            "disable_comment": bool(creator.get("comment_disabled")),
            "disable_duet": bool(creator.get("duet_disabled")),
            "disable_stitch": bool(creator.get("stitch_disabled")),
            # Auto Ranking is a paid service shown in the video: always disclose it as promoting
            # "your brand"; mark it branded content too when a third party paid you.
            "brand_organic_toggle": True, "brand_content_toggle": bool(paid_promotion), "is_aigc": False}


def upload(cred_dir: Path, data: bytes, post_info: dict, http: Http | None = None, sleep=time.sleep,
           poll_seconds: float = 180) -> dict:
    http = http or Http()
    token = _access_token(cred_dir, http)
    size = len(data)
    chunk_size, count = chunk_plan(size)
    init = _api(http, INIT_URL, token, {"post_info": post_info, "source_info": {
        "source": "FILE_UPLOAD", "video_size": size, "chunk_size": chunk_size, "total_chunk_count": count}})
    publish_id, upload_url = init.get("publish_id"), init.get("upload_url")
    if not publish_id or not upload_url:
        raise PublishError(f"TikTok did not return an upload URL: {init}")
    for i in range(count):
        first = i * chunk_size
        last = size - 1 if i == count - 1 else first + chunk_size - 1
        for attempt in range(3):
            resp = http.put(upload_url, data[first:last + 1], {
                "Content-Type": "video/mp4", "Content-Range": f"bytes {first}-{last}/{size}"})
            if resp.status in (201, 206) or resp.status < 500:
                break
            sleep(2 ** attempt)
        if resp.status not in (201, 206):
            raise PublishError(f"TikTok rejected chunk {i + 1}/{count} ({resp.status}): {resp.text()}")
    result = {"remote_id": publish_id, "status": "processing", "url": None}
    deadline = time.monotonic() + poll_seconds
    while time.monotonic() < deadline:
        st = _api(http, STATUS_URL, token, {"publish_id": publish_id})
        status = st.get("status")
        if status == "PUBLISH_COMPLETE":
            ids = st.get("publicaly_available_post_id") or st.get("publicly_available_post_id") or []
            result.update(status="published", post_ids=ids)
            break
        if status == "FAILED":
            raise PublishError(f"TikTok could not publish the video: {st.get('fail_reason') or 'unknown reason'}")
        sleep(5)
    return result
