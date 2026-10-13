"""OAuth for desktop apps: PKCE, a one-shot loopback receiver and a local token file."""
from __future__ import annotations

import base64
import hashlib
import json
import os
import secrets
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from . import PublishError

LOOPBACK_HOST = "127.0.0.1"
LOOPBACK_PORT = 8766
CALLBACK_PATH = "/callback/"
REDIRECT_URI = f"http://{LOOPBACK_HOST}:{LOOPBACK_PORT}{CALLBACK_PATH}"
START_PATH = "/start"
START_URL = f"http://{LOOPBACK_HOST}:{LOOPBACK_PORT}{START_PATH}"  # short link that forwards to the sign-in page


def pkce_pair(hex_challenge: bool = False) -> tuple[str, str]:
    """(verifier, S256 challenge). Google wants base64url; TikTok desktop wants hex."""
    verifier = secrets.token_urlsafe(64)[:96]
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    challenge = digest.hex() if hex_challenge else base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return verifier, challenge


def code_from_redirect(url: str, state: str) -> str:
    """The auth code from a pasted redirect URL (the browser's address bar after signing in)."""
    q = {k: v[0] for k, v in parse_qs(urlparse(url.strip()).query).items()}
    if "error" in q:
        raise PublishError(f"sign-in failed: {q['error']} {q.get('error_description', '')}".strip())
    if "code" not in q:
        raise PublishError("that address has no ?code=... in it; copy the whole address bar after signing in")
    if q.get("state") != state:
        raise PublishError("that address belongs to a different sign-in attempt; start `connect` again")
    return q["code"]


class Pending:
    """PKCE verifier and state of the sign-in in progress, so a pasted redirect can finish it."""

    def __init__(self, path: Path):
        self.path = Path(path)

    def save(self, verifier: str, state: str) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps({"verifier": verifier, "state": state, "at": int(time.time())}),
                             encoding="utf-8")

    def load(self) -> dict:
        if not self.path.is_file():
            raise PublishError("no sign-in in progress; run `connect` first, then paste the address")
        data = json.loads(self.path.read_text(encoding="utf-8"))
        if time.time() - data.get("at", 0) > 3600:
            raise PublishError("the sign-in attempt is over an hour old; run `connect` again")
        return data

    def clear(self) -> None:
        self.path.unlink(missing_ok=True)


def receive_code(state: str, timeout: float = 600, port: int = LOOPBACK_PORT, auth_url: str | None = None) -> str:
    """Wait for the browser to come back to the loopback redirect and return the auth code.
    While waiting, START_URL forwards to `auth_url`, so the user can type a short address."""
    result: dict = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            url = urlparse(self.path)
            if url.path == START_PATH and auth_url:
                self.send_response(302)
                self.send_header("Location", auth_url)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if url.path != CALLBACK_PATH:
                self.send_error(404)
                return
            q = {k: v[0] for k, v in parse_qs(url.query).items()}
            if q.get("state") != state:
                result["error"] = "state mismatch (ignored a request that did not come from this sign-in)"
            elif "error" in q:
                result["error"] = f"{q['error']}: {q.get('error_description', '')}".strip(": ")
            elif "code" in q:
                result["code"] = q["code"]
            else:
                result["error"] = "no authorization code in the redirect"
            ok = "code" in result
            body = (f"<!doctype html><meta charset=utf-8><title>VideoStudio</title><body style='font:16px system-ui;"
                    f"padding:40px'><h2>{'Connected.' if ok else 'Sign-in failed.'}</h2><p>"
                    f"{'You can close this tab and go back to the terminal.' if ok else 'See the terminal for details.'}"
                    "</p></body>").encode("utf-8")
            self.send_response(200 if ok else 400)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    try:
        server = HTTPServer((LOOPBACK_HOST, port), Handler)
    except OSError as exc:
        raise PublishError(f"port {port} is busy ({exc}); close whatever uses it and try again") from exc
    server.timeout = 5
    deadline = time.monotonic() + timeout
    with server:
        while not result and time.monotonic() < deadline:
            server.handle_request()
    if "code" in result:
        return result["code"]
    raise PublishError(f"sign-in failed: {result['error']}" if result else
                       "sign-in timed out (the browser never came back). If the last page showed an address "
                       "starting with http://127.0.0.1:8766/callback/, copy it and run: "
                       "python -m studio connect <platform> --redirect-url \"<that address>\"")


class TokenFile:
    """Access/refresh tokens on disk. `expires_at` is epoch seconds."""

    def __init__(self, path: Path):
        self.path = Path(path)

    def load(self) -> dict | None:
        return json.loads(self.path.read_text(encoding="utf-8")) if self.path.is_file() else None

    def save(self, token: dict) -> dict:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(token, indent=1), encoding="utf-8")
        try:
            os.chmod(tmp, 0o600)
        except OSError:
            pass
        tmp.replace(self.path)
        return token

    def access_token(self, refresh) -> str:
        """A token valid for at least 2 more minutes, refreshing (and saving) if needed."""
        token = self.load()
        if not token:
            raise PublishError("not connected")
        if token.get("expires_at", 0) - time.time() < 120:
            if not token.get("refresh_token"):
                raise PublishError("the saved sign-in expired; connect again")
            token = self.save({**token, **refresh(token["refresh_token"])})
        return token["access_token"]


def expiry(token_response: dict) -> dict:
    """Normalise a token endpoint response into what TokenFile stores."""
    out = {k: v for k, v in token_response.items() if k in ("access_token", "refresh_token", "scope", "open_id",
                                                             "refresh_expires_in")}
    out["expires_at"] = int(time.time()) + int(token_response.get("expires_in", 3600))
    return out
