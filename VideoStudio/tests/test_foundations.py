import os
import time

import pytest

from tests.conftest import make_clip


# --- hwaccel -----------------------------------------------------------------

def test_choose_encoder_priority():
    from studio.hwaccel import choose_encoder

    choice = choose_encoder({"h264_nvenc": True, "h264_qsv": True, "libx264": True})
    assert choice.name == "h264_nvenc"
    assert choice.hw is True

    cpu = choose_encoder({"h264_nvenc": False, "h264_qsv": False, "libx264": True})
    assert cpu.name == "libx264"
    assert cpu.hw is False
    assert "-crf" in cpu.args


def test_choose_encoder_honours_preference_only_when_available():
    from studio.hwaccel import choose_encoder

    assert choose_encoder({"h264_qsv": True, "libx264": True}, prefer="h264_qsv").name == "h264_qsv"
    assert choose_encoder({"h264_qsv": False, "libx264": True}, prefer="h264_qsv").name == "libx264"


def test_probe_encoders_real():
    from studio.hwaccel import probe_encoders

    available = probe_encoders()
    assert available["libx264"] is True
    # This cloud container has no GPU device, so no hardware encoder can open.
    assert set(available) >= {"h264_nvenc", "h264_qsv", "h264_amf", "h264_videotoolbox", "h264_vaapi"}


# --- media / source guard ------------------------------------------------------

def test_probe_reads_basic_info(artifacts_dir):
    from studio.media import probe

    clip = make_clip(artifacts_dir / "clip.mp4", 2)
    info = probe(clip)
    assert abs(info.duration - 2.0) < 0.1
    assert (info.width, info.height) == (320, 180)
    assert abs(info.fps - 30) < 0.01
    assert info.has_audio is True
    assert info.vcodec == "h264"


def test_source_guard_detects_change(artifacts_dir):
    from studio.media import SourceGuard, SourceModifiedError

    clip = make_clip(artifacts_dir / "src.mp4", 1)
    guard = SourceGuard(clip)
    guard.verify(full=True)  # unchanged: no error

    with open(clip, "ab") as fh:
        fh.write(b"\0")
    with pytest.raises(SourceModifiedError):
        guard.verify()


def test_source_guard_detects_same_size_rewrite(artifacts_dir):
    from studio.media import SourceGuard, SourceModifiedError

    clip = make_clip(artifacts_dir / "src.mp4", 1)
    guard = SourceGuard(clip)
    data = bytearray(clip.read_bytes())
    data[-1] ^= 0xFF
    stat = clip.stat()
    clip.write_bytes(bytes(data))
    os.utime(clip, ns=(stat.st_atime_ns, stat.st_mtime_ns))  # hide the mtime change
    guard.verify()  # quick check cannot see it
    with pytest.raises(SourceModifiedError):
        guard.verify(full=True)


def test_source_guard_refuses_source_folder_output(artifacts_dir):
    from studio.media import SourceGuard, UnsafeOutputError

    clip = make_clip(artifacts_dir / "rec" / "src.mp4", 1)
    guard = SourceGuard(clip)
    with pytest.raises(UnsafeOutputError):
        guard.check_output(clip)
    with pytest.raises(UnsafeOutputError):
        guard.check_output(clip.parent / "edited.mp4")
    guard.check_output(artifacts_dir / "workspace" / "edited.mp4")  # allowed


def test_paths_with_spaces_and_unicode(artifacts_dir):
    from studio.media import SourceGuard, probe

    clip = make_clip(artifacts_dir / "My Videos" / "VyHub Auto Ranking ⭐ (1).mp4", 1)
    assert probe(clip).width == 320
    SourceGuard(clip).verify(full=True)


# --- discovery ------------------------------------------------------------------

def test_find_recordings_duration_window(artifacts_dir):
    from studio.discover import find_recordings

    make_clip(artifacts_dir / "short.mp4", 2, audio=False)
    target = make_clip(artifacts_dir / "nested" / "VyHub auto rank.mp4", 9, audio=False)
    make_clip(artifacts_dir / "long.mkv", 20, audio=False)
    (artifacts_dir / "notes.txt").write_text("not a video")

    found = find_recordings([artifacts_dir], min_s=5, max_s=15)
    assert [c.path for c in found] == [target]
    assert "name" in " ".join(found[0].reasons)


def test_find_recordings_ranks_named_files_first(artifacts_dir):
    from studio.discover import find_recordings

    plain = make_clip(artifacts_dir / "2026-10-11 20-01-02.mp4", 6, audio=False)
    named = make_clip(artifacts_dir / "ps99 vyhub ranking.mp4", 6, audio=False)
    time.sleep(0.01)
    found = find_recordings([artifacts_dir], min_s=5, max_s=15)
    assert [c.path for c in found] == [named, plain]


def test_default_roots_are_existing_dirs():
    from studio.discover import default_roots

    for root in default_roots():
        assert root.is_dir()


# --- config ---------------------------------------------------------------------

def test_default_profile_and_brand_load():
    from studio.config import load_brand, load_profile, DEFAULT_PROFILE

    profile = load_profile(DEFAULT_PROFILE)
    assert profile.sample_fps == 2.0
    assert profile.max_gain == 60
    for roi in profile.rois.values():
        assert 0 <= roi.x < 1 and 0 <= roi.y < 1 and 0 < roi.w <= 1 and 0 < roi.h <= 1

    brand = load_brand()
    assert "gems" in brand["disclosure"]["short"].lower()
    assert brand["blocked_terms"]
