import json
import os
import subprocess

import numpy as np
import pytest

BROWSER = "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell"


@pytest.fixture(scope="module")
def highlight_plan(fixture_analysis):
    from studio.config import load_brand
    from studio.planner import plan_variant

    brand = load_brand()
    variant = next(v for v in brand["variants"] if v["id"] == "highlight")
    return plan_variant(fixture_analysis[0], brand, variant)


def _probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-print_format", "json", "-show_streams", "-show_format", str(path)],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def _loudness(path):
    err = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    summary = err[err.rindex("Summary:"):]
    return float(summary.split("I:")[1].split("LUFS")[0])


def _frame(path, t):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(t), "-i", str(path), "-frames:v", "1", "-f", "rawvideo",
                          "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(1920, 1080, 3)


def _color_fraction(region, rgb, tol=40):
    return float((np.abs(region.astype(int) - np.array(rgb)).max(axis=2) < tol).mean())


def _check_output_spec(manifest, plan):
    video = manifest["video"]
    info = _probe(manifest["dir"] + "/" + video["file"])
    v = next(s for s in info["streams"] if s["codec_type"] == "video")
    a = next(s for s in info["streams"] if s["codec_type"] == "audio")
    assert (v["width"], v["height"]) == (1080, 1920)
    assert v["codec_name"] == "h264" and v["pix_fmt"] == "yuv420p" and v["avg_frame_rate"] == "30/1"
    assert a["codec_name"] == "aac" and a["sample_rate"] == "48000"
    assert abs(float(info["format"]["duration"]) - plan["duration"]) < 0.15
    assert abs(_loudness(manifest["dir"] + "/" + video["file"]) - (-14.0)) <= 1.5
    from studio.media import sha256_file

    assert sha256_file(manifest["dir"] + "/" + video["file"]) == video["sha256"]
    assert manifest["source"]["verified_unchanged"] is True


def test_render_ass_output_spec(highlight_plan, fixture_video, artifacts_dir):
    from studio.media import SourceGuard
    from studio.render.run import render_plan

    guard = SourceGuard(fixture_video.path)
    manifest = render_plan(highlight_plan, artifacts_dir, overlay="ass")
    guard.verify(full=True)
    assert manifest["overlay_engine"] == "ass"
    _check_output_spec(manifest, highlight_plan)
    assert (artifacts_dir / manifest["cover"]).is_file()
    # the disclosure badge (white text) is burned in after the opening card, and absent from the plain gameplay
    frame = _frame(artifacts_dir / "final.mp4", highlight_plan["overlay"]["disclosure"]["badge_start"] + 1.0)
    assert _color_fraction(frame[1440:1530, 60:1020], (255, 255, 255), tol=30) > 0.01


def test_hw_encoder_failure_falls_back_to_libx264(highlight_plan, artifacts_dir):
    from studio.hwaccel import choose_encoder
    from studio.render.run import render_plan

    nvenc = choose_encoder({"h264_nvenc": True})  # not usable in this container: no GPU
    short = dict(highlight_plan)
    manifest = render_plan(short, artifacts_dir, overlay="ass", encoder=nvenc)
    assert manifest["encoder"]["name"] == "libx264"
    assert manifest["encoder"]["fallback_from"] == "h264_nvenc"


@pytest.mark.skipif(not os.path.exists(BROWSER), reason="needs the preinstalled headless Chromium")
def test_render_remotion_overlay_present(highlight_plan, artifacts_dir, monkeypatch):
    from studio.render.run import render_plan

    monkeypatch.setenv("REMOTION_BROWSER_EXECUTABLE", BROWSER)
    manifest = render_plan(highlight_plan, artifacts_dir, overlay="remotion")
    assert manifest["overlay_engine"] == "remotion"
    _check_output_spec(manifest, highlight_plan)
    pop = highlight_plan["overlay"]["quests"][0]
    main = highlight_plan["layout"]["main_rect"]
    frame = _frame(artifacts_dir / "final.mp4", pop["t"] + 0.8)
    # "QUEST COMPLETE" banner in the brand accent colour over the gameplay
    assert _color_fraction(frame[main["y"]:main["y"] + main["h"]], (61, 220, 151)) > 0.01
    assert not list((artifacts_dir / "overlay").glob("*.png")), "overlay frames are cleaned up after compositing"
