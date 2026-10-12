import json
import shutil
import subprocess
import sys

import pytest

from tests.conftest import ROOT, make_clip


def cli(workspace, *args, check=True):
    proc = subprocess.run([sys.executable, "-m", "studio", "--workspace", str(workspace), *map(str, args)],
                          cwd=ROOT, capture_output=True, text=True, timeout=1800)
    if check and proc.returncode != 0:
        raise AssertionError(f"exit {proc.returncode}\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}")
    return proc


def test_cli_audit_runs(tmp_path):
    out = cli(tmp_path, "audit").stdout
    assert "libx264" in out and "RapidOCR" in out and "Remotion" in out
    assert "ANTHROPIC_API_KEY" in out


def test_cli_find(tmp_path):
    make_clip(tmp_path / "videos" / "VyHub ranking.mp4", 6, audio=False)
    make_clip(tmp_path / "videos" / "other.mp4", 1, audio=False)
    out = cli(tmp_path / "ws", "find", "--root", tmp_path / "videos", "--min-minutes", 0.05, "--max-minutes", 0.2).stdout
    assert "VyHub ranking.mp4" in out and "other.mp4" not in out


def test_cli_run_uncalibrated_stops_before_counting(tmp_path):
    clip = make_clip(tmp_path / "rec" / "new recording.mp4", 3)
    proc = cli(tmp_path / "ws", "run", clip, check=False)
    assert proc.returncode == 2
    assert "calibrat" in proc.stdout.lower()
    assert not (tmp_path / "ws" / "renders").exists()


def test_cli_run_end_to_end(fixture_video, tmp_path):
    from studio.config import load_brand
    from studio.media import SourceGuard
    from studio.metadata import validate_metadata
    from studio.review.store import ReviewStore

    ws = tmp_path / "ws"
    guard = SourceGuard(fixture_video.path)
    proc = cli(ws, "ingest", fixture_video.path)
    sid = proc.stdout.strip().splitlines()[-1].split()[-1]
    shutil.copy(fixture_video.profile_path, ws / "sources" / sid / "profile.json")  # calibration for the fixture
    cli(ws, "run", fixture_video.path, "--variants", "highlight", "--overlay", "ass")
    guard.verify(full=True)

    [render] = (ws / "renders").iterdir()
    manifest = json.loads((render / "manifest.json").read_text())
    assert manifest["facts"]["stars_verified"] == 36
    assert validate_metadata(manifest["metadata"], load_brand()) == []
    assert manifest["events"] and all((render / p).is_file() for e in manifest["events"] for p in e["evidence"].values())
    [item] = ReviewStore(ws).list()
    assert item["status"] == "pending_review"

    proc = cli(ws, "package", render.name, "tiktok", check=False)
    assert proc.returncode == 1 and "authoriz" in (proc.stdout + proc.stderr).lower()
