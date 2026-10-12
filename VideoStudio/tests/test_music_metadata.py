import copy
import re
import wave

import numpy as np
import pytest


# --- music ---------------------------------------------------------------------

def _read_wav(path):
    with wave.open(str(path)) as w:
        frames = w.readframes(w.getnframes())
        return w.getframerate(), w.getnchannels(), np.frombuffer(frames, np.int16).astype(np.float32) / 32768


def test_generated_track_length_and_level(tmp_path):
    from studio.music import generate_track

    path = generate_track(tmp_path / "t.wav", seconds=90.0, bpm=124, seed=7)
    rate, channels, pcm = _read_wav(path)
    assert (rate, channels) == (48000, 2)
    assert abs(pcm.size / channels / rate - 90.0) < 0.05
    peak_db = 20 * np.log10(np.abs(pcm).max())
    rms_db = 20 * np.log10(np.sqrt(np.mean(pcm ** 2)))
    assert peak_db <= -1.0
    assert rms_db > -24.0  # audible, not near-silent


def test_generated_track_deterministic(tmp_path):
    from studio.media import sha256_file
    from studio.music import generate_track

    a = generate_track(tmp_path / "a.wav", seconds=8.0, seed=3)
    b = generate_track(tmp_path / "b.wav", seconds=8.0, seed=3)
    assert sha256_file(a) == sha256_file(b)


def test_library_rejects_unlicensed(tmp_path):
    from studio.music import pick_track, validate_track

    good = {"id": "ok", "title": "Ok", "file": str(tmp_path / "ok.wav"), "license": "Bought from X",
            "license_type": "licensed", "proof": "invoice-123.pdf", "allowed_platforms": ["youtube_shorts", "tiktok"]}
    (tmp_path / "ok.wav").write_bytes(b"RIFF")
    bad = dict(good, id="bad", license="", proof="")
    assert validate_track(good) == []
    errors = validate_track(bad)
    assert any("license" in e for e in errors) and any("proof" in e for e in errors)
    assert pick_track([bad, good], ["youtube_shorts", "tiktok"])["id"] == "ok"
    with pytest.raises(ValueError):
        pick_track([bad], ["tiktok"])


def test_platform_restricted_track_not_picked_for_other_platform(tmp_path):
    from studio.music import pick_track

    yt_only = {"id": "yt", "title": "YT", "file": str(tmp_path / "yt.wav"), "license": "YouTube Audio Library",
               "license_type": "platform_library", "proof": "https://studio.youtube.com/...",
               "allowed_platforms": ["youtube_shorts"]}
    (tmp_path / "yt.wav").write_bytes(b"RIFF")
    with pytest.raises(ValueError):
        pick_track([yt_only], ["youtube_shorts", "tiktok"])


def test_default_library_valid():
    from studio.music import load_library, validate_track

    tracks = load_library()
    assert tracks and all(validate_track(t, require_file=False) == [] for t in tracks)


# --- metadata --------------------------------------------------------------------

def _analysis(stars=36, quests=7, duration=660.0):
    return {"source": {"duration": duration},
            "totals": {"stars_verified": stars, "quests_confirmed": quests, "quests_probable": 0, "rank_ups": 1}}


@pytest.fixture
def brand():
    from studio.config import load_brand

    return load_brand()


def test_disclosure_in_every_platform(brand):
    from studio.metadata import build_metadata, validate_metadata

    meta = build_metadata(_analysis(), None, brand)
    assert set(meta) == {"youtube_shorts", "tiktok"}
    assert brand["disclosure"]["caption"] in meta["youtube_shorts"]["description"]
    assert meta["youtube_shorts"]["description"].startswith(brand["disclosure"]["caption"])
    assert brand["disclosure"]["caption"] in meta["tiktok"]["caption"]
    for post in meta.values():
        assert "gems" in post["on_screen_disclosure"].lower()
    assert validate_metadata(meta, brand) == []


def test_missing_disclosure_fails_validation(brand):
    from studio.metadata import build_metadata, validate_metadata

    meta = build_metadata(_analysis(), None, brand)
    meta["tiktok"]["caption"] = "no disclosure here #ps99"
    assert any("disclosure" in e.lower() for e in validate_metadata(meta, brand))


def test_youtube_title_limit_100(brand):
    from studio.metadata import build_metadata

    long_brand = copy.deepcopy(brand)
    long_brand["titles"]["youtube_shorts"].insert(0, "+{stars} Rank Stars " + "x" * 120)
    meta = build_metadata(_analysis(), None, long_brand)
    assert len(meta["youtube_shorts"]["title"]) <= 100
    assert len(meta["tiktok"]["caption"]) <= 2200


def test_blocked_terms_rejected(brand):
    from studio.metadata import BlockedTermError, build_metadata

    blocked = copy.deepcopy(brand)
    blocked["blocked_terms"] = ["pet sim"]
    with pytest.raises(BlockedTermError):
        build_metadata(_analysis(), None, blocked)


def test_titles_without_verified_stars_have_no_numbers(brand):
    from studio.metadata import build_metadata

    meta = build_metadata(_analysis(stars=None, quests=0), None, brand)
    assert meta["youtube_shorts"]["title"] in brand["titles"]["youtube_shorts_no_numbers"]
    assert not re.search(r"\+\d+|\d+ (Rank )?Stars|\d+ Quests", meta["youtube_shorts"]["title"] + meta["tiktok"]["caption"])
    assert meta["youtube_shorts"]["facts"]["stars_verified"] is None


def test_numbers_match_analysis(brand):
    from studio.metadata import build_metadata

    meta = build_metadata(_analysis(stars=36, duration=662.0), None, brand)
    title = meta["youtube_shorts"]["title"]
    assert "+36 Rank Stars" in title and "11 Minutes" in title
    assert "+36 rank stars in 11 minutes" in meta["tiktok"]["caption"]


def test_research_keywords_used_and_attributed(brand):
    from studio.metadata import build_metadata

    research = {"source": "vidIQ", "fetched_at": "2026-10-12", "keywords": [{"keyword": "ps99 rank up", "score": 71}]}
    meta = build_metadata(_analysis(), None, brand, research=research)
    assert "ps99 rank up" in meta["youtube_shorts"]["tags"]
    assert meta["youtube_shorts"]["research"].startswith("vidIQ")
    plain = build_metadata(_analysis(), None, brand)
    assert "not vidIQ-validated" in plain["youtube_shorts"]["research"]
