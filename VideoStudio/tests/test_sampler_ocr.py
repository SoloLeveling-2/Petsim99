import subprocess

import numpy as np


def _frame_at(path, t, w, h):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(t), "-i", str(path), "-frames:v", "1",
                          "-f", "rawvideo", "-pix_fmt", "bgr24", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(h, w, 3)


def test_mosaic_regions_match_rois(fixture_video):
    from studio.config import load_profile
    from studio.media import probe
    from studio.sampler import MosaicLayout, iter_samples

    info = probe(fixture_video.path)
    profile = load_profile(fixture_video.profile_path)
    layout = MosaicLayout.from_rois(info, profile.rois)
    assert set(layout.names) == {"overview", "star_counter", "quest_panel", "completion_banner", "rank_label"}

    samples = iter_samples(fixture_video.path, layout, fps=2.0, start=10.0, duration=2.0)
    first = next(samples)
    assert abs(first.t - 10.0) < 0.01
    star = first.regions["star_counter"]
    x, y, w, h = profile.rois["star_counter"].to_pixels(info.width, info.height)
    reference = _frame_at(fixture_video.path, 10.0, info.width, info.height)[y:y + h, x:x + w]
    # star_counter is cropped at native resolution (no rescale), so it must match closely
    assert star.shape == reference.shape
    assert np.abs(star.astype(int) - reference.astype(int)).mean() < 6
    assert first.regions["overview"].shape == (180, 320, 3)
    rest = list(samples)
    assert len(rest) == 3  # 2 s at 2 fps = 4 samples total
    assert [round(s.t, 2) for s in rest] == [10.5, 11.0, 11.5]


def test_parse_star_text():
    from studio.ocr import parse_star_text

    pattern = r"(?P<cur>\d{1,5})\s*/\s*(?P<total>\d{1,5})"
    assert parse_star_text("★ 45/90", pattern) == (45, 90)
    assert parse_star_text("4S/9O", pattern) == (45, 90)
    assert parse_star_text("12 / 40", pattern) == (12, 40)
    assert parse_star_text("abc", pattern) is None
    assert parse_star_text("", pattern) is None
    assert parse_star_text("Stars: 1,250", r"(?P<cur>\d{1,6})") == (1250, None)


def test_ocr_reads_fixture_counter(fixture_video):
    from studio.config import load_profile
    from studio.ocr import OcrEngine, parse_star_text

    profile = load_profile(fixture_video.profile_path)
    frame = _frame_at(fixture_video.path, 3.0, 1280, 720)
    x, y, w, h = profile.rois["star_counter"].to_pixels(1280, 720)
    text, conf = OcrEngine().read_line(frame[y:y + h, x:x + w])
    assert parse_star_text(text, profile.star_pattern) == (12, 40)
    assert conf > 0.8


def test_ocr_confidence_ignores_misread_icon(fixture_video):
    """At 14.5 s the star icon is misread as '￥' (conf ~0.55) next to a perfect '19/40'."""
    from studio.config import load_profile
    from studio.ocr import OcrEngine, parse_star_text

    profile = load_profile(fixture_video.profile_path)
    frame = _frame_at(fixture_video.path, 14.5, 1280, 720)
    x, y, w, h = profile.rois["star_counter"].to_pixels(1280, 720)
    text, conf = OcrEngine().read_line(frame[y:y + h, x:x + w])
    assert parse_star_text(text, profile.star_pattern) == (19, 40)
    assert conf > 0.9


def test_ocr_small_crop_is_fast(fixture_video):
    """Small HUD crops must not be upscaled for text detection (was ~1.8 s per read)."""
    import time

    from studio.config import load_profile
    from studio.ocr import OcrEngine

    profile = load_profile(fixture_video.profile_path)
    frame = _frame_at(fixture_video.path, 14.5, 1280, 720)
    x, y, w, h = profile.rois["star_counter"].to_pixels(1280, 720)
    crop = frame[y:y + h, x:x + w]
    engine = OcrEngine()
    engine.read_line(crop)
    started = time.perf_counter()
    for _ in range(5):
        engine.read_line(crop)
    assert (time.perf_counter() - started) / 5 < 0.25


def test_ocr_reads_panel_lines(fixture_video):
    from studio.config import load_profile
    from studio.ocr import OcrEngine

    profile = load_profile(fixture_video.profile_path)
    frame = _frame_at(fixture_video.path, 3.0, 1280, 720)
    x, y, w, h = profile.rois["quest_panel"].to_pixels(1280, 720)
    lines = [t for t, _ in OcrEngine().read_lines(frame[y:y + h, x:x + w])]
    joined = " | ".join(lines).lower()
    for name in ("break 300 coins", "hatch 50 eggs", "collect 5 diamonds"):
        assert name in joined, joined


def test_gated_reader_skips_unchanged():
    from studio.ocr import GatedReader

    calls = []

    class FakeEngine:
        def read_line(self, img):
            calls.append(1)
            return "12/40", 0.99

    reader = GatedReader(FakeEngine(), keepalive_s=8.0)
    img = np.full((40, 120, 3), 50, np.uint8)
    a = reader.read(0.0, img)
    b = reader.read(0.5, img.copy())
    assert (a.reused, b.reused) == (False, True)
    assert b.text == "12/40"
    changed = img.copy()
    changed[:, :60] = 255
    c = reader.read(1.0, changed)
    assert c.reused is False
    d = reader.read(10.0, changed)  # keepalive forces a fresh read
    assert d.reused is False
    assert len(calls) == 3


def test_gated_reader_sees_small_digit_change():
    """A digit change touches ~2% of the counter's pixels; it must trigger a fresh read."""
    from studio.ocr import GatedReader

    class FakeEngine:
        def read_line(self, img):
            return "x", 0.99

    reader = GatedReader(FakeEngine())
    img = np.full((56, 220, 3), 40, np.uint8)
    reader.read(0.0, img)
    noisy = np.clip(img.astype(int) + np.random.default_rng(1).integers(-10, 11, img.shape), 0, 255).astype(np.uint8)
    assert reader.read(0.5, noisy).reused is True  # compression-level noise is ignored
    digit = noisy.copy()
    digit[20:36, 150:166] = 250  # 256 px = 2.1% of the region
    assert reader.read(1.0, digit).reused is False
