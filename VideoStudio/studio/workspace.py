"""Workspace layout: registered recordings, their calibration, analyses and renders.

workspace/
  sources/<source_id>/source.json    path + fingerprint of the original (never copied)
  sources/<source_id>/profile.json   calibrated screen regions for this recording
  sources/<source_id>/frames/        stills for the calibration page
  sources/<source_id>/analysis/      analysis.json + evidence/
  renders/<render_id>/               final.mp4, cover, plan, manifest, review.json
"""
from __future__ import annotations

import json
import re
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

from .config import DEFAULT_PROFILE, ROI, ROI_NAMES, WORKSPACE, Profile, load_profile, save_profile
from .media import FFMPEG, SourceGuard, probe, run

_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$")


class WorkspaceError(ValueError):
    pass


def _slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:40] or "recording"


class Workspace:
    def __init__(self, root: Path = WORKSPACE):
        self.root = Path(root)
        self.sources = self.root / "sources"
        self.renders = self.root / "renders"

    def source_dir(self, source_id: str) -> Path:
        if not _ID.match(source_id or ""):
            raise WorkspaceError("invalid source id")
        path = self.sources / source_id
        if not (path / "source.json").is_file():
            raise WorkspaceError(f"no such source: {source_id}")
        return path

    def register(self, path: Path, profile_template: Path = DEFAULT_PROFILE) -> dict:
        guard = SourceGuard(path)
        info = probe(guard.path)
        source_id = f"{_slug(guard.path.stem)}-{guard.fingerprint.sha256[:8]}"
        sdir = self.sources / source_id
        sdir.mkdir(parents=True, exist_ok=True)
        record = {"id": source_id, "path": str(guard.path), "fingerprint": guard.as_dict(), "info": asdict(info),
                  "registered_at": datetime.now(timezone.utc).isoformat(timespec="seconds")}
        if (sdir / "source.json").is_file():
            record["registered_at"] = self.source(source_id)["registered_at"]
        (sdir / "source.json").write_text(json.dumps(record, indent=1), encoding="utf-8")
        if not (sdir / "profile.json").is_file():
            template = load_profile(profile_template)
            template.name = source_id
            save_profile(template, sdir / "profile.json")
        return record

    def source(self, source_id: str) -> dict:
        return json.loads((self.source_dir(source_id) / "source.json").read_text(encoding="utf-8"))

    def guard(self, source_id: str) -> SourceGuard:
        record = self.source(source_id)
        return SourceGuard(record["path"], record["fingerprint"])

    def list_sources(self) -> list[dict]:
        if not self.sources.is_dir():
            return []
        out = []
        for p in sorted(self.sources.iterdir()):
            if (p / "source.json").is_file():
                rec = self.source(p.name)
                rec["calibrated"] = self.profile(p.name).calibrated
                rec["analyzed"] = (p / "analysis" / "analysis.json").is_file()
                out.append(rec)
        return out

    def profile(self, source_id: str) -> Profile:
        return load_profile(self.source_dir(source_id) / "profile.json")

    def save_rois(self, source_id: str, rois: dict) -> Profile:
        clean = {}
        for name, box in rois.items():
            if name not in ROI_NAMES:
                raise WorkspaceError(f"unknown region {name!r}")
            try:
                x, y, w, h = (float(box[k]) for k in ("x", "y", "w", "h"))
            except (KeyError, TypeError, ValueError):
                raise WorkspaceError(f"region {name} needs numeric x, y, w, h")
            if not (0 <= x < 1 and 0 <= y < 1 and 0.005 <= w <= 1 - x + 1e-9 and 0.005 <= h <= 1 - y + 1e-9):
                raise WorkspaceError(f"region {name} must lie inside the frame")
            clean[name] = ROI(round(x, 5), round(y, 5), round(w, 5), round(h, 5))
        profile = self.profile(source_id)
        profile.rois = clean
        save_profile(profile, self.source_dir(source_id) / "profile.json")
        return profile

    def frame(self, source_id: str, t: float) -> Path:
        """A full-resolution still for calibration (cached by tenth of a second)."""
        record = self.source(source_id)
        t = max(0.0, min(float(t), record["info"]["duration"] - 0.05))
        out = self.source_dir(source_id) / "frames" / f"t{int(round(t * 10)):06d}.jpg"
        if not out.is_file():
            out.parent.mkdir(exist_ok=True)
            self.guard(source_id)  # refuses if the original changed
            run([FFMPEG, "-hide_banner", "-v", "error", "-y", "-ss", f"{t:.2f}", "-i", record["path"],
                 "-frames:v", "1", "-q:v", "2", out])
        return out

    def analysis_dir(self, source_id: str) -> Path:
        return self.source_dir(source_id) / "analysis"

    def new_render_dir(self, source_id: str, variant: str) -> Path:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        path = self.renders / f"{source_id}-{variant}-{stamp}"
        path.mkdir(parents=True, exist_ok=False)
        return path
