"""Approval and publication-authorization records, bound to the exact bytes reviewed.

Nothing in this module uploads, schedules or edits a profile. An authorization records
that you approved this exact video file and this exact post text for one platform;
`package()` then prepares a folder for you to upload by hand, and the opt-in
`studio.publish` commands use `publish_target()` / `record_publication()` to post it.
Any change to the video or the post text makes earlier approvals stale.
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

from ..media import FFMPEG, run, sha256_file

REQUIRED_CONFIRMATIONS = ("watched_full_video", "checked_post_text", "checked_disclosure", "checked_music_license")
CONFIRM_PHRASE = "AUTHORIZE"
_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$")


class ReviewError(ValueError):
    pass


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def canonical_hash(obj) -> str:
    return hashlib.sha256(json.dumps(obj, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()


class ReviewStore:
    def __init__(self, workspace: Path):
        self.root = Path(workspace) / "renders"
        self._video_hash_cache: dict[tuple, str] = {}

    # --- paths & loading -------------------------------------------------------------
    def render_dir(self, render_id: str) -> Path:
        if not _ID.match(render_id or ""):
            raise ReviewError("invalid render id")
        path = (self.root / render_id).resolve()
        if path.parent != self.root.resolve() or not (path / "manifest.json").is_file():
            raise ReviewError(f"no such render: {render_id}")
        return path

    def _manifest(self, render_id: str) -> dict:
        return json.loads((self.render_dir(render_id) / "manifest.json").read_text(encoding="utf-8"))

    def _history(self, render_id: str) -> list[dict]:
        path = self.render_dir(render_id) / "review.json"
        return json.loads(path.read_text(encoding="utf-8"))["history"] if path.is_file() else []

    def _append(self, render_id: str, event: dict) -> dict:
        path = self.render_dir(render_id) / "review.json"
        history = self._history(render_id) + [event]
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps({"history": history}, indent=1), encoding="utf-8")
        tmp.replace(path)
        return event

    def _video_hash(self, render_id: str, manifest: dict) -> str:
        video = self.render_dir(render_id) / manifest["video"]["file"]
        stat = video.stat()
        key = (str(video), stat.st_size, stat.st_mtime_ns)
        if key not in self._video_hash_cache:
            self._video_hash_cache[key] = sha256_file(video)
        return self._video_hash_cache[key]

    def content_hash(self, render_id: str, manifest: dict | None = None) -> dict:
        manifest = manifest or self._manifest(render_id)
        return {"video_sha256": self._video_hash(render_id, manifest),
                "metadata_sha256": canonical_hash(manifest.get("metadata"))}

    # --- state ------------------------------------------------------------------------
    def _state(self, render_id: str, manifest: dict) -> tuple[str, dict, list[dict]]:
        current = self.content_hash(render_id, manifest)
        history = self._history(render_id)
        decisions = [h for h in history if h["type"] == "decision"]
        if not decisions:
            status = "pending_review"
        elif decisions[-1]["content"] != current:
            status = "stale"
        else:
            status = "approved" if decisions[-1]["decision"] == "approve" else "rejected"
        last_decision_at = decisions[-1]["at_index"] if decisions else -1
        auths: dict[str, dict] = {}
        for h in history:
            if h["type"] == "authorization":
                auths[h["platform"]] = dict(h)
            elif h["type"] == "revocation" and h["platform"] in auths:
                auths[h["platform"]]["revoked_at"] = h["at"]
        for platform, a in auths.items():
            a["valid"] = (status == "approved" and "revoked_at" not in a and a["content"] == current
                          and a["at_index"] > last_decision_at)
        return status, auths, history

    def list(self) -> list[dict]:
        items = []
        if not self.root.is_dir():
            return items
        for path in sorted(self.root.iterdir(), reverse=True):
            if not (path / "manifest.json").is_file() or not _ID.match(path.name):
                continue
            manifest = self._manifest(path.name)
            status, auths, _ = self._state(path.name, manifest)
            items.append({"id": path.name, "label": manifest.get("label"), "variant": manifest.get("variant"),
                          "created_at": manifest.get("created_at"), "duration": manifest["video"]["duration"],
                          "cover": manifest.get("cover"), "status": status,
                          "title": (manifest.get("metadata") or {}).get("youtube_shorts", {}).get("title"),
                          "authorized": sorted(p for p, a in auths.items() if a["valid"])})
        return items

    def get(self, render_id: str) -> dict:
        manifest = self._manifest(render_id)
        status, auths, history = self._state(render_id, manifest)
        plan_path = self.render_dir(render_id) / manifest.get("plan_file", "plan.json")
        plan = json.loads(plan_path.read_text(encoding="utf-8")) if plan_path.is_file() else {}
        publications = {}
        for h in history:
            if h["type"] == "publication":
                publications.setdefault(h["platform"], []).append(h)
        return {**manifest, "status": status, "authorizations": auths, "history": history,
                "publications": publications,
                "content": self.content_hash(render_id, manifest),
                "plan_summary": {k: plan.get(k) for k in ("duration", "segments", "layout") if k in plan}}

    # --- actions ----------------------------------------------------------------------
    def decide(self, render_id: str, decision: str, notes: str = "") -> dict:
        if decision not in ("approve", "reject"):
            raise ReviewError("decision must be approve or reject")
        manifest = self._manifest(render_id)
        return self._append(render_id, {"type": "decision", "decision": decision, "notes": str(notes)[:2000],
                                        "at": _now(), "at_index": len(self._history(render_id)),
                                        "content": self.content_hash(render_id, manifest)})

    def authorize(self, render_id: str, platform: str, confirmations: dict, confirm_text: str,
                  scheduled_for: str | None = None) -> dict:
        manifest = self._manifest(render_id)
        status, _, history = self._state(render_id, manifest)
        if platform not in (manifest.get("metadata") or {}):
            raise ReviewError(f"unknown platform {platform!r}")
        if status != "approved":
            raise ReviewError(f"the video must be approved (current status: {status})")
        missing = [c for c in REQUIRED_CONFIRMATIONS if confirmations.get(c) is not True]
        if missing:
            raise ReviewError("please confirm: " + ", ".join(missing))
        if (confirm_text or "").strip() != CONFIRM_PHRASE:
            raise ReviewError(f"type {CONFIRM_PHRASE} to authorize")
        post = manifest["metadata"][platform]
        return self._append(render_id, {
            "type": "authorization", "platform": platform, "action": "publish",
            "scheduled_for": scheduled_for or None, "status": "authorized_not_published",
            "post": post, "at": _now(), "at_index": len(history), "content": self.content_hash(render_id, manifest),
            "note": "Recorded only. The studio has no upload, scheduling or profile-editing code.",
        })

    def revoke(self, render_id: str, platform: str) -> dict:
        return self._append(render_id, {"type": "revocation", "platform": platform, "at": _now(),
                                        "at_index": len(self._history(render_id))})

    def preview(self, render_id: str) -> Path:
        """Low-res VP9 copy for browsers without an H.264 decoder. Review aid only: approvals
        always bind to the final MP4's hash, and this file is never packaged for upload."""
        rdir = self.render_dir(render_id)
        manifest = self._manifest(render_id)
        final, out = rdir / manifest["video"]["file"], rdir / "preview.webm"
        if not out.is_file() or out.stat().st_mtime_ns < final.stat().st_mtime_ns:
            tmp = rdir / "preview.tmp.webm"
            run([FFMPEG, "-hide_banner", "-v", "error", "-y", "-i", final, "-vf", "scale=540:960",
                 "-c:v", "libvpx-vp9", "-deadline", "realtime", "-cpu-used", "8", "-row-mt", "1", "-crf", "36",
                 "-b:v", "0", "-c:a", "libopus", "-b:a", "96k", tmp])
            tmp.replace(out)
        return out

    def publish_target(self, render_id: str, platform: str, again: bool = False) -> dict:
        """What may be posted: the authorized post text and the video path. Refuses without a
        valid authorization, and refuses a second post of the same content unless `again`."""
        detail = self.get(render_id)
        auth = detail["authorizations"].get(platform)
        if not auth or not auth["valid"]:
            raise ReviewError(f"no valid authorization for {platform}")
        done = [p for p in detail["publications"].get(platform, []) if p["content"] == detail["content"]]
        if done and not again:
            last = done[-1]
            raise ReviewError(f"already posted to {platform} at {last['at']} "
                              f"({last.get('url') or last.get('remote_id')}); pass --again to post it again")
        return {"render_id": render_id, "platform": platform, "post": auth["post"], "authorization": auth,
                "content": detail["content"], "video": self.render_dir(render_id) / detail["video"]["file"],
                "duration": detail["video"]["duration"]}

    def record_publication(self, render_id: str, platform: str, content: dict, result: dict) -> dict:
        keep = ("status", "remote_id", "url", "visibility", "upload_status", "post_ids", "account", "options")
        return self._append(render_id, {"type": "publication", "platform": platform,
                                        **{k: result[k] for k in keep if k in result},
                                        "at": _now(), "at_index": len(self._history(render_id)),
                                        "content": content})

    def package(self, render_id: str, platform: str) -> Path:
        """A folder with the authorized video and post text, for uploading by hand."""
        detail = self.get(render_id)
        auth = detail["authorizations"].get(platform)
        if not auth or not auth["valid"]:
            raise ReviewError(f"no valid authorization for {platform}")
        out = self.render_dir(render_id) / f"publish_{platform}"
        out.mkdir(exist_ok=True)
        shutil.copy2(self.render_dir(render_id) / detail["video"]["file"], out / "final.mp4")
        post = detail["metadata"][platform]
        text = post.get("caption") or f"{post['title']}\n\n{post['description']}"
        (out / "caption.txt").write_text(text + "\n", encoding="utf-8")
        (out / "post.json").write_text(json.dumps(post, indent=1, ensure_ascii=False), encoding="utf-8")
        (out / "AUTHORIZATION.json").write_text(json.dumps(auth, indent=1, ensure_ascii=False), encoding="utf-8")
        return out
