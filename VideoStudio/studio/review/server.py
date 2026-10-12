"""Localhost-only review dashboard (Python standard library, no build step).

Security: binds 127.0.0.1, rejects foreign Host headers (DNS rebinding) and foreign
Origins, requires a per-start token on every state-changing request, and only serves
files from inside the workspace's render and source folders.
"""
from __future__ import annotations

import json
import mimetypes
import re
import secrets
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

from ..media import MediaError
from ..workspace import Workspace, WorkspaceError
from .store import ReviewError, ReviewStore

STATIC = Path(__file__).parent / "static"
_SEG = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$")
CSP = ("default-src 'self'; img-src 'self' data:; media-src 'self'; style-src 'self'; script-src 'self'; "
       "connect-src 'self'; frame-ancestors 'none'")


def _safe_child(base: Path, *parts: str) -> Path | None:
    if not all(_SEG.match(p) for p in parts):
        return None
    path = base.joinpath(*parts).resolve()
    base = base.resolve()
    return path if path.is_file() and base in path.parents else None


def make_server(workspace: Path, host: str = "127.0.0.1", port: int = 8765):
    ws = Workspace(Path(workspace))
    store = ReviewStore(Path(workspace))
    token = secrets.token_urlsafe(24)

    class Handler(BaseHTTPRequestHandler):
        server_version = "PS99Studio/1"

        def log_message(self, fmt, *args):  # keep the console quiet
            pass

        # --- helpers --------------------------------------------------------------
        def _allowed_hosts(self) -> set[str]:
            p = self.server.server_address[1]
            return {f"127.0.0.1:{p}", f"localhost:{p}"}

        def _send(self, code: int, body: bytes, ctype: str, extra: dict | None = None) -> None:
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", CSP)
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)

        def _json(self, code: int, obj) -> None:
            self._send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

        def _error(self, code: int, message: str) -> None:
            self._json(code, {"error": message})

        def _host_ok(self) -> bool:
            return self.headers.get("Host", "") in self._allowed_hosts()

        def _file(self, path: Path | None) -> None:
            if path is None:
                return self._error(404, "not found")
            size = path.stat().st_size
            ctype = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            rng = self.headers.get("Range")
            match = re.match(r"bytes=(\d*)-(\d*)$", rng or "")
            if match and (match.group(1) or match.group(2)):
                if match.group(1):
                    start = int(match.group(1))
                    end = min(int(match.group(2)) if match.group(2) else size - 1, size - 1)
                else:
                    start, end = max(0, size - int(match.group(2))), size - 1
                if start > end or start >= size:
                    return self._send(416, b"", ctype, {"Content-Range": f"bytes */{size}"})
                with open(path, "rb") as fh:
                    fh.seek(start)
                    data = fh.read(end - start + 1)
                return self._send(206, data, ctype, {"Content-Range": f"bytes {start}-{end}/{size}",
                                                     "Accept-Ranges": "bytes"})
            self._send(200, path.read_bytes(), ctype, {"Accept-Ranges": "bytes"})

        # --- GET --------------------------------------------------------------------
        def do_HEAD(self):
            self.do_GET()

        def do_GET(self):
            if not self._host_ok():
                return self._error(403, "forbidden host")
            parts = [unquote(p) for p in urlparse(self.path).path.split("/") if p]
            try:
                if not parts:
                    html = (STATIC / "index.html").read_text(encoding="utf-8").replace("{{TOKEN}}", token)
                    return self._send(200, html.encode("utf-8"), "text/html; charset=utf-8")
                if parts[0] == "static" and len(parts) == 2:
                    return self._file(_safe_child(STATIC, parts[1]))
                if parts[:2] == ["api", "renders"]:
                    if len(parts) == 2:
                        return self._json(200, store.list())
                    if len(parts) == 3:
                        return self._json(200, store.get(parts[2]))
                if parts[:2] == ["api", "sources"]:
                    if len(parts) == 2:
                        return self._json(200, ws.list_sources())
                    if len(parts) == 3:
                        prof = ws.profile(parts[2])
                        return self._json(200, {"source": ws.source(parts[2]),
                                                "rois": {k: vars(v) for k, v in prof.rois.items()},
                                                "suggested": {k: vars(v) for k, v in prof.suggested_rois.items()}})
                if parts[0] == "media" and len(parts) >= 3:
                    if parts[1] == "source" and len(parts) == 5 and parts[3] == "frames":
                        return self._file(_safe_child(ws.source_dir(parts[2]), "frames", parts[4]))
                    return self._file(_safe_child(store.render_dir(parts[1]), *parts[2:]))
                return self._error(404, "not found")
            except (ReviewError, WorkspaceError) as exc:
                return self._error(404, str(exc))

        # --- POST -------------------------------------------------------------------
        def do_POST(self):
            if not self._host_ok():
                return self._error(403, "forbidden host")
            origin = self.headers.get("Origin")
            if origin and origin.removeprefix("http://") not in self._allowed_hosts():
                return self._error(403, "forbidden origin")
            if not secrets.compare_digest(self.headers.get("X-Studio-Token", ""), token):
                return self._error(403, "missing or wrong session token")
            try:
                length = min(int(self.headers.get("Content-Length", "0")), 1 << 20)
                body = json.loads(self.rfile.read(length) or b"{}")
            except (ValueError, json.JSONDecodeError):
                return self._error(400, "invalid JSON")
            parts = [unquote(p) for p in urlparse(self.path).path.split("/") if p]
            try:
                if parts[:2] == ["api", "renders"] and len(parts) == 4:
                    rid, action = parts[2], parts[3]
                    if action == "decision":
                        store.decide(rid, body.get("decision", ""), body.get("notes", ""))
                    elif action == "authorize":
                        store.authorize(rid, body.get("platform", ""), body.get("confirmations") or {},
                                        body.get("confirm_text", ""), body.get("scheduled_for"))
                    elif action == "revoke":
                        store.revoke(rid, body.get("platform", ""))
                    elif action == "preview":
                        return self._json(200, {"url": f"/media/{rid}/{store.preview(rid).name}"})
                    else:
                        return self._error(404, "not found")
                    return self._json(200, store.get(rid))
                if parts[:2] == ["api", "sources"] and len(parts) == 4:
                    sid, action = parts[2], parts[3]
                    if action == "frame":
                        frame = ws.frame(sid, float(body.get("t", 0)))
                        return self._json(200, {"url": f"/media/source/{sid}/frames/{frame.name}"})
                    if action == "profile":
                        prof = ws.save_rois(sid, body.get("rois") or {})
                        return self._json(200, {"rois": {k: vars(v) for k, v in prof.rois.items()},
                                                "calibrated": prof.calibrated})
                return self._error(404, "not found")
            except (ReviewError, WorkspaceError, MediaError, ValueError) as exc:
                return self._error(400, str(exc))

    httpd = ThreadingHTTPServer((host, port), Handler)
    httpd.daemon_threads = True
    return httpd, token
