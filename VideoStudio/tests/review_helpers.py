"""Builds a small but complete render package for review tests (no full render needed)."""
import json
from pathlib import Path

from tests.conftest import make_clip

CONFIRMATIONS = {"watched_full_video": True, "checked_post_text": True, "checked_disclosure": True,
                 "checked_music_license": True}


def make_render(workspace: Path, render_id: str = "vyhub-run-recap-20261012-120000") -> Path:
    from studio.config import load_brand
    from studio.metadata import build_metadata
    from studio.media import probe, sha256_file

    brand = load_brand()
    rdir = workspace / "renders" / render_id
    video = make_clip(rdir / "final.mp4", 3, size="1080x1920")
    make_clip(rdir / "_cover_src.mp4", 1, size="540x960", audio=False)
    import subprocess

    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(rdir / "_cover_src.mp4"), "-frames:v", "1",
                    str(rdir / "cover.jpg")], check=True)
    (rdir / "_cover_src.mp4").unlink()
    (rdir / "evidence").mkdir()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=gray:s=200x60", "-frames:v", "1",
                    str(rdir / "evidence" / "q1_star_before.jpg")], check=True)
    analysis = {"source": {"duration": 662.0}, "totals": {"stars_verified": 36, "quests_confirmed": 7,
                                                           "quests_probable": 0, "rank_ups": 1}}
    plan = {"variant": "recap", "label": "Full-run recap", "duration": 3.0,
            "music": {"id": "studio-original-01", "title": "Rank Rush (original)", "license_type": "owned",
                      "license": "Original composition", "proof": "studio/music.py seed 7"},
            "overlay": {"quests": [{"t": 1.0, "name": "Hatch 50 Eggs", "stars": 4, "status": "confirmed",
                                    "label": "QUEST COMPLETE"}], "counter": [{"t": 0.5, "value": 0}]}}
    info = probe(video)
    manifest = {
        "id": render_id, "dir": str(rdir), "variant": "recap", "label": "Full-run recap",
        "created_at": "2026-10-12T12:00:00+00:00",
        "video": {"file": "final.mp4", "sha256": sha256_file(video), "size": info.size, "duration": info.duration,
                  "width": info.width, "height": info.height, "fps": info.fps, "vcodec": info.vcodec,
                  "loudness_lufs": -14.1},
        "cover": "cover.jpg", "plan_file": "plan.json", "overlay_engine": "remotion",
        "encoder": {"name": "libx264", "hw": False, "fallback_from": None}, "music": plan["music"],
        "source": {"path": "/videos/VyHub Auto Ranking.mp4", "sha256": "ab" * 32, "verified_unchanged": True},
        "metadata": build_metadata(analysis, plan, brand), "warnings": [],
        "facts": {"stars_verified": 36, "quests_confirmed": 7, "rank_ups": 1, "minutes": 11},
        "events": [{"id": "q1", "t": 120.5, "kind": "quest", "status": "confirmed", "name": "Hatch 50 Eggs",
                    "stars": 4, "evidence": {"star_before": "evidence/q1_star_before.jpg"}}],
    }
    (rdir / "plan.json").write_text(json.dumps(plan))
    (rdir / "manifest.json").write_text(json.dumps(manifest))
    return rdir
