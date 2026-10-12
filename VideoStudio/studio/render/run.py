"""Render one plan into a reviewable package: final.mp4, cover, plan, manifest."""
from __future__ import annotations

import json
import shutil
import time
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

from ..config import DEFAULT_BRAND, load_brand
from ..hwaccel import EncoderChoice, choose_encoder, probe_encoders
from ..media import FFMPEG, MediaError, SourceGuard, probe, run, sha256_file
from ..music import ensure_track_file, load_library, pick_track
from .ass import write_ass
from .graph import OverlayInput, build_command
from .remotion_overlay import remotion_available, render_overlay

PLATFORMS = ["youtube_shorts", "tiktok"]


@lru_cache(maxsize=1)
def _available_encoders() -> tuple[tuple[str, bool], ...]:
    return tuple(probe_encoders().items())


def default_encoder() -> EncoderChoice:
    return choose_encoder(dict(_available_encoders()))


def _music_for(plan: dict, brand: dict) -> dict:
    if plan.get("music") and plan["music"].get("file") and Path(plan["music"]["file"]).is_file():
        return plan["music"]
    track = pick_track(load_library(), PLATFORMS, prefer=brand["music"]["default_track"])
    ensure_track_file(track)
    return {k: track.get(k) for k in ("id", "title", "file", "license", "license_type", "proof", "attribution_required")}


def measure_loudness(path: Path) -> float | None:
    proc = run([FFMPEG, "-hide_banner", "-nostats", "-i", path, "-vn", "-af", "ebur128", "-f", "null", "-"], check=False)
    err = proc.stderr or ""
    if "Summary:" not in err:
        return None
    summary = err[err.rindex("Summary:"):]
    try:
        return float(summary.split("I:")[1].split("LUFS")[0])
    except (IndexError, ValueError):
        return None


def _cover(video: Path, plan: dict, out: Path) -> None:
    pops = plan["overlay"]["quests"]
    t = pops[0]["t"] + 0.7 if pops else min(1.0, plan["duration"] / 2)
    run([FFMPEG, "-hide_banner", "-v", "error", "-y", "-ss", f"{t:.3f}", "-i", video, "-frames:v", "1",
         "-vf", "scale=540:960", "-q:v", "3", out])


def render_plan(plan: dict, out_dir: Path, *, overlay: str = "auto", encoder: EncoderChoice | None = None,
                concurrency: int = 2, brand: dict | None = None, metadata: dict | None = None,
                threads: int | None = None) -> dict:
    started = time.monotonic()
    brand = brand or load_brand()
    out_dir = Path(out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    source = Path(plan["source"]["path"])
    guard = SourceGuard(source)
    if guard.fingerprint.sha256 != plan["source"]["sha256"]:
        raise MediaError("The recording on disk is not the one that was analysed (SHA-256 differs). Re-run analyze.")
    final = guard.check_output(out_dir / "final.mp4")
    log = out_dir / "render.log"
    warnings: list[str] = []

    plan = dict(plan)
    plan["music"] = _music_for(plan, brand)

    engine = overlay
    if overlay == "auto":
        engine = "remotion" if remotion_available() else "ass"
        if engine == "ass":
            warnings.append("Remotion not installed; used the simpler ASS overlay. Run `npm ci` in VideoStudio/remotion.")
    frames_dir = out_dir / "overlay"
    if engine == "remotion":
        try:
            pattern, start_number, _ = render_overlay(plan, frames_dir, concurrency=concurrency, log_path=log)
            ov = OverlayInput("png_sequence", pattern, start_number)
        except MediaError as exc:
            if overlay != "auto":
                raise
            warnings.append(f"Remotion overlay failed ({exc}); fell back to the ASS overlay.")
            engine = "ass"
    if engine == "ass":
        write_ass(plan, out_dir / "overlay.ass")
        fonts = out_dir / "fonts"
        fonts.mkdir(exist_ok=True)
        shutil.copy2(Path(DEFAULT_BRAND).parent / brand["font"]["file"], fonts)
        ov = OverlayInput("ass", "overlay.ass", fonts_dir="fonts")

    chosen = encoder or default_encoder()
    fallback_from = None
    common = dict(music_volume=brand["music"]["music_volume"], game_volume=brand["music"]["game_volume"],
                  loudness=float(brand["output"]["loudness_lufs"]), threads=threads)
    try:
        run(build_command(plan, source, Path(plan["music"]["file"]), ov, chosen, final, **common), log_path=log,
            cwd=out_dir)
    except MediaError:
        if not chosen.hw:
            raise
        fallback_from = chosen.name
        warnings.append(f"Hardware encoder {chosen.name} failed; re-encoded with libx264.")
        chosen = choose_encoder({"libx264": True})
        run(build_command(plan, source, Path(plan["music"]["file"]), ov, chosen, final, **common), log_path=log,
            cwd=out_dir)
    if frames_dir.exists():
        shutil.rmtree(frames_dir)  # transparent PNGs are large and no longer needed
    guard.verify(full=True)

    info = probe(final)
    _cover(final, plan, out_dir / "cover.jpg")
    (out_dir / "plan.json").write_text(json.dumps(plan, indent=1), encoding="utf-8")
    manifest = {
        "id": out_dir.name,
        "dir": str(out_dir),
        "variant": plan["variant"],
        "label": plan["label"],
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "video": {"file": final.name, "sha256": sha256_file(final), "size": info.size, "duration": info.duration,
                  "width": info.width, "height": info.height, "fps": info.fps, "vcodec": info.vcodec,
                  "loudness_lufs": measure_loudness(final)},
        "cover": "cover.jpg",
        "plan_file": "plan.json",
        "overlay_engine": engine,
        "encoder": {"name": chosen.name, "hw": chosen.hw, "fallback_from": fallback_from},
        "music": plan["music"],
        "source": {"path": str(source), "sha256": guard.fingerprint.sha256, "verified_unchanged": True},
        "metadata": metadata,
        "warnings": warnings,
        "render_seconds": round(time.monotonic() - started, 1),
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    return manifest
