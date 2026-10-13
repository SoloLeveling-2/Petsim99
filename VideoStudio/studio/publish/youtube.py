"""YouTube Data API v3: OAuth sign-in and resumable upload of one Short.

Setup (once): in Google Cloud Console create a project, enable "YouTube Data API v3",
configure the OAuth consent screen (add yourself as a test user) and create an OAuth
client of type "Desktop app". Download its JSON as credentials/youtube_client.json.

Google limits videos uploaded from unverified API projects to private viewing until the
project passes Google's API audit; the upload still succeeds and you can see it in
YouTube Studio.
"""
from __future__ import annotations

import json
import secrets
import time
import urllib.error
import urllib.parse
from pathlib import Path

from . import PublishError
from .http import Http
from .oauth import REDIRECT_URI, TokenFile, expiry, pkce_pair, receive_code

SCOPE = "https://www.googleapis.com/auth/youtube.upload"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
UPLOAD_URL = "https://www.googleapis.com/upload/youtube/v3/videos"
CATEGORY_GAMING = "20"
VISIBILITY = {"public": "public", "unlisted": "unlisted", "private": "private"}
TITLE_MAX, DESCRIPTION_MAX_BYTES, TAGS_MAX_CHARS = 100, 5000, 500


def client(cred_dir: Path) -> dict:
    path = Path(cred_dir) / "youtube_client.json"
    if not path.is_file():
        raise PublishError(f"missing {path}: create a Desktop-app OAuth client in Google Cloud Console "
                           "(YouTube Data API v3 enabled) and save its JSON there")
    data = json.loads(path.read_text(encoding="utf-8"))
    data = data.get("installed") or data.get("web") or data
    if not data.get("client_id") or not data.get("client_secret"):
        raise PublishError(f"{path} has no client_id/client_secret")
    return {"client_id": data["client_id"], "client_secret": data["client_secret"]}


def tokens(cred_dir: Path) -> TokenFile:
    return TokenFile(Path(cred_dir) / "youtube_token.json")


def connect(cred_dir: Path, open_url, http: Http | None = None, receive=receive_code) -> dict:
    http = http or Http(timeout=60)
    c = client(cred_dir)
    verifier, challenge = pkce_pair()
    state = secrets.token_urlsafe(16)
    open_url(AUTH_URL + "?" + urllib.parse.urlencode({
        "client_id": c["client_id"], "redirect_uri": REDIRECT_URI, "response_type": "code", "scope": SCOPE,
        "access_type": "offline", "prompt": "consent", "state": state,
        "code_challenge": challenge, "code_challenge_method": "S256"}))
    code = receive(state)
    resp = http.post_form(TOKEN_URL, {"client_id": c["client_id"], "client_secret": c["client_secret"],
                                      "code": code, "code_verifier": verifier, "grant_type": "authorization_code",
                                      "redirect_uri": REDIRECT_URI})
    data = resp.json()
    if resp.status != 200 or "access_token" not in data:
        raise PublishError(f"Google token exchange failed ({resp.status}): {resp.text()}")
    return tokens(cred_dir).save(expiry(data))


def _refresher(cred_dir: Path, http: Http):
    def refresh(refresh_token: str) -> dict:
        c = client(cred_dir)
        resp = http.post_form(TOKEN_URL, {"client_id": c["client_id"], "client_secret": c["client_secret"],
                                          "refresh_token": refresh_token, "grant_type": "refresh_token"})
        if resp.status != 200:
            raise PublishError(f"Google sign-in refresh failed ({resp.status}): {resp.text()}; connect again")
        return expiry(resp.json())
    return refresh


def build_body(post: dict, visibility: str, made_for_kids: bool, paid_promotion: bool) -> dict:
    """The videos.insert resource for an authorized post. Raises if YouTube would reject it."""
    if visibility not in VISIBILITY:
        raise PublishError(f"YouTube visibility must be one of {', '.join(VISIBILITY)}")
    title, description, tags = post["title"], post["description"], list(post.get("tags") or [])
    problems = []
    if not title or len(title) > TITLE_MAX or "<" in title or ">" in title:
        problems.append(f"title must be 1-{TITLE_MAX} characters without < or >")
    if len(description.encode("utf-8")) > DESCRIPTION_MAX_BYTES or "<" in description or ">" in description:
        problems.append(f"description must be at most {DESCRIPTION_MAX_BYTES} bytes without < or >")
    if sum(len(t) + (2 if " " in t else 0) for t in tags) + max(0, len(tags) - 1) > TAGS_MAX_CHARS:
        problems.append(f"tags exceed {TAGS_MAX_CHARS} characters")
    if problems:
        raise PublishError("; ".join(problems))
    body = {"snippet": {"title": title, "description": description, "tags": tags, "categoryId": CATEGORY_GAMING},
            "status": {"privacyStatus": VISIBILITY[visibility], "selfDeclaredMadeForKids": bool(made_for_kids),
                       "containsSyntheticMedia": False}}
    if paid_promotion:
        body["paidProductPlacementDetails"] = {"hasPaidProductPlacement": True}
    return body


def _created(resp) -> dict:
    video = resp.json()
    vid = video.get("id")
    if not vid:
        raise PublishError(f"YouTube finished the upload but returned no video id: {resp.text()}")
    status = video.get("status") or {}
    return {"remote_id": vid, "url": f"https://www.youtube.com/shorts/{vid}",
            "visibility": status.get("privacyStatus"), "upload_status": status.get("uploadStatus")}


def upload(cred_dir: Path, data: bytes, body: dict, http: Http | None = None, attempts: int = 4,
           sleep=time.sleep) -> dict:
    """Resumable upload of `data` (the exact authorized bytes). Returns the created video."""
    http = http or Http()
    token = tokens(cred_dir).access_token(_refresher(cred_dir, http))
    auth = {"Authorization": f"Bearer {token}"}
    parts = ",".join(body)
    init = http.post_json(f"{UPLOAD_URL}?uploadType=resumable&part={parts}", body, headers={
        **auth, "X-Upload-Content-Length": str(len(data)), "X-Upload-Content-Type": "video/mp4"})
    session = init.headers.get("location")
    if init.status != 200 or not session:
        raise PublishError(f"YouTube refused the upload ({init.status}): {init.text()}")
    size, offset = len(data), 0
    for attempt in range(attempts):
        try:
            resp = http.put(session, data[offset:], {**auth, "Content-Type": "video/mp4",
                                                     "Content-Range": f"bytes {offset}-{size - 1}/{size}"})
        except (urllib.error.URLError, OSError):
            resp = None
        if resp is not None and resp.status in (200, 201):
            return _created(resp)
        if resp is not None and resp.status < 500 and resp.status != 308:
            raise PublishError(f"YouTube upload failed ({resp.status}): {resp.text()}")
        sleep(min(30, 2 ** attempt))
        probe = http.put(session, b"", {**auth, "Content-Range": f"bytes */{size}"})
        if probe.status in (200, 201):
            return _created(probe)
        rng = probe.headers.get("range", "")
        offset = int(rng.rsplit("-", 1)[1]) + 1 if probe.status == 308 and "-" in rng else 0
    raise PublishError("YouTube upload did not complete after retries; nothing was recorded, try again later")
