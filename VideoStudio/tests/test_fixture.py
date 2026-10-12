import json


def test_fixture_is_valid_video(fixture_video):
    from studio.media import probe

    info = probe(fixture_video.path)
    assert abs(info.duration - 72.0) < 0.1
    assert (info.width, info.height) == (1280, 720)
    assert info.has_audio

    truth = fixture_video.truth
    assert sum(g["to"] - g["from"] for g in truth["star_gains"]) == truth["verified_total"] == 36
    assert len(truth["rank_ups"]) == 1
    profile = json.loads(fixture_video.profile_path.read_text())
    assert set(profile["rois"]) >= {"star_counter", "quest_panel", "completion_banner"}
