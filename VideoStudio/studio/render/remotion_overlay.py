"""Render the Remotion overlay as a transparent PNG sequence."""
from __future__ import annotations

import json
import os
import re
import shutil
from pathlib import Path

from ..config import STUDIO_ROOT
from ..media import MediaError, run

REMOTION_DIR = STUDIO_ROOT / "remotion"
PATTERN = "frame-[frame].[ext]"


def remotion_available(remotion_dir: Path = REMOTION_DIR) -> bool:
    return shutil.which("npx") is not None and (remotion_dir / "node_modules" / "remotion").is_dir()


def overlay_props(plan: dict) -> dict:
    return {k: plan[k] for k in ("width", "height", "fps", "duration", "overlay", "layout", "brand")}


def render_overlay(plan: dict, frames_dir: Path, *, concurrency: int = 2, log_path: Path | None = None,
                   remotion_dir: Path = REMOTION_DIR) -> tuple[str, int, int]:
    """Returns (ffmpeg input pattern, start number, frame count)."""
    npx = shutil.which("npx")
    if npx is None or not remotion_available(remotion_dir):
        raise MediaError("Remotion is not installed: run `npm ci` in VideoStudio/remotion")
    frames_dir = Path(frames_dir)
    if frames_dir.exists():
        shutil.rmtree(frames_dir)
    frames_dir.mkdir(parents=True)
    props = frames_dir.parent / "overlay_props.json"
    props.write_text(json.dumps(overlay_props(plan)), encoding="utf-8")
    cmd = [npx, "remotion", "render", "src/index.ts", "ShortOverlay", str(frames_dir.resolve()), "--sequence",
           "--image-format=png", f"--image-sequence-pattern={PATTERN}", f"--props={props.resolve()}",
           f"--concurrency={concurrency}", "--log=warn"]
    browser = os.environ.get("REMOTION_BROWSER_EXECUTABLE")
    if browser:
        cmd.append(f"--browser-executable={browser}")
    run(cmd, log_path=log_path, timeout=3600, cwd=remotion_dir)
    frames = sorted(frames_dir.glob("frame-*.png"))
    if not frames:
        raise MediaError("Remotion produced no frames")
    first = re.match(r"frame-(\d+)\.png", frames[0].name)
    digits = len(first.group(1))
    return str(frames_dir / f"frame-%0{digits}d.png"), int(first.group(1)), len(frames)

