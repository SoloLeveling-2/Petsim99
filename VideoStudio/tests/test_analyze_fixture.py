import json

import pytest


@pytest.fixture(scope="module")
def analysis(fixture_analysis):
    return fixture_analysis


def test_fixture_ground_truth(analysis, fixture_video):
    result, out = analysis
    truth = fixture_video.truth
    counted = [e for e in result["star_events"] if e["counted"]]

    for gain in truth["star_gains"]:
        match = [e for e in counted if abs(e["t"] - gain["t"]) <= 0.75]
        assert len(match) == 1, (gain, counted)
        assert match[0]["delta"] == gain["to"] - gain["from"]
    assert len(counted) == len(truth["star_gains"])
    assert result["totals"]["stars_verified"] == truth["verified_total"] == 36

    rank_ups = [e for e in result["star_events"] if e["kind"] == "rank_up"]
    assert len(rank_ups) == 1 and abs(rank_ups[0]["t"] - truth["rank_ups"][0]["t"]) <= 0.75
    assert result["totals"]["rank_ups"] == 1

    occ = truth["occlusions"][0]
    assert not [e for e in result["star_events"] if occ["start"] - 1 <= e["t"] <= occ["end"] + 1]

    quests = result["quests"]
    confirmed = [q for q in quests if q["status"] == "confirmed"]
    assert len(confirmed) == 7
    named = sum(1 for q, g in zip(confirmed, truth["star_gains"]) if q["name"] == g["quest"])
    assert named >= 6, [(q["name"], g["quest"]) for q, g in zip(confirmed, truth["star_gains"])]
    for q, g in zip(confirmed, truth["star_gains"]):
        assert abs(q["t"] - g["quest_t"]) <= 0.75

    vt = truth["visual_only"][0]["t"]
    assert any(q["status"] == "visual_only" and abs(q["t"] - vt) <= 1.0 for q in quests)
    assert not [e for e in counted if vt - 1 <= e["t"] <= vt + 2]

    assert result["highlights"] and result["highlights"][0]["event_ids"]
    saved = json.loads((out / "analysis.json").read_text())
    assert saved["totals"] == result["totals"]
    for q in confirmed:
        assert (out / result["evidence"][q["id"]]["frame"]).is_file()


def test_ocr_is_change_gated(analysis):
    result, _ = analysis
    stats = result["stats"]
    assert stats["samples"] == 144
    assert stats["ocr_calls_star"] < stats["samples"] / 2


def test_uncalibrated_analysis_has_no_counts(fixture_video, tmp_path):
    from studio.analyze import analyze_source
    from studio.config import Profile

    result = analyze_source(fixture_video.path, Profile(name="blank"), tmp_path)
    assert result["calibrated"] is False
    assert result["totals"]["stars_verified"] is None
    assert result["star_events"] == [] and result["quests"] == []
    assert result["highlights"]
    assert any("calibrat" in w.lower() for w in result["warnings"])
