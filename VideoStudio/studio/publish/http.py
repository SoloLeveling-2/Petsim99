"""Tiny HTTP client: never follows redirects (YouTube uses 308 for upload progress) and
returns every status instead of raising, so callers decide what an error means."""
from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field


@dataclass
class Response:
    status: int
    headers: dict = field(default_factory=dict)
    body: bytes = b""

    def json(self) -> dict:
        try:
            return json.loads(self.body.decode("utf-8") or "{}")
        except (UnicodeDecodeError, json.JSONDecodeError):
            return {}

    def text(self, limit: int = 500) -> str:
        return self.body.decode("utf-8", "replace")[:limit]


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Http:
    def __init__(self, timeout: float = 600):
        self.timeout = timeout
        self._opener = urllib.request.build_opener(_NoRedirect)

    def request(self, method: str, url: str, headers: dict | None = None, data: bytes | None = None) -> Response:
        req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
        try:
            with self._opener.open(req, timeout=self.timeout) as resp:
                return Response(resp.status, {k.lower(): v for k, v in resp.headers.items()}, resp.read())
        except urllib.error.HTTPError as exc:
            return Response(exc.code, {k.lower(): v for k, v in (exc.headers or {}).items()}, exc.read() or b"")

    def post_json(self, url: str, body: dict, token: str | None = None, headers: dict | None = None) -> Response:
        h = {"Content-Type": "application/json; charset=UTF-8", **(headers or {})}
        if token:
            h["Authorization"] = f"Bearer {token}"
        return self.request("POST", url, h, json.dumps(body).encode("utf-8"))

    def post_form(self, url: str, fields: dict) -> Response:
        return self.request("POST", url, {"Content-Type": "application/x-www-form-urlencoded"},
                            urllib.parse.urlencode(fields).encode("ascii"))

    def put(self, url: str, data: bytes, headers: dict) -> Response:
        return self.request("PUT", url, {**headers, "Content-Length": str(len(data))}, data)
