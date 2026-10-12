import copy

import pytest


@pytest.fixture(scope="module")
def brand():
    from studio.config import load_brand

    return load_brand()


def _variant(brand, vid):
    return next(v for v in brand["variants"] if v["id"] == vid)


@pytest.fixture(scope="module")
def plans(fixture_analysis, brand):
    from studio.planner import plan_variant

    analysis, _ = fixture_analysis
    return {v["id"]: plan_variant(analysis, brand, v) for v in brand["variants"]}


def _star_events(analysis):
    return [e for e in analysis["star_events"] if e["counted"]]


def _to_out(plan, src_t, roles=("body", "timelapse", "outro")):
    for s in plan["segments"]:
        if s["role"] in roles and s["src_start"] <= src_t < s["src_end"]:
            return s["out_start"] + (src_t - s["src_start"]) / s["speed"]
    return None


def test_plan_duration_within_target(plans, brand):
    for vid, plan in plans.items():
        target = _variant(brand, vid)["target_seconds"]
        assert 0.6 * target <= plan["duration"] <= 1.1 * target, (vid, plan["duration"])
        assert (plan["width"], plan["height"], plan["fps"]) == (1080, 1920, 30)


def test_segments_within_source_and_timeline_consistent(plans, fixture_analysis):
    analysis, _ = fixture_analysis
    duration = analysis["source"]["duration"]
    for plan in plans.values():
        segs = plan["segments"]
        assert segs[0]["role"] == "hook" and segs[-1]["role"] == "outro"
        assert segs[0]["out_start"] == 0
        for s in segs:
            assert 0 <= s["src_start"] < s["src_end"] <= duration
            assert abs((s["out_end"] - s["out_start"]) - (s["src_end"] - s["src_start"]) / s["speed"]) < 1e-6
        for a, b in zip(segs, segs[1:]):
            assert abs((a["out_end"] - b["out_start"]) - plan["xfade"]) < 1e-6
        body = [s for s in segs if s["role"] != "hook"]
        assert all(a["src_end"] <= b["src_start"] + 1e-6 for a, b in zip(body, body[1:])), "body is chronological"
        assert abs(plan["duration"] - segs[-1]["out_end"]) < 1e-6


def test_counter_monotonic_and_matches_verified_total(plans, fixture_analysis):
    analysis, _ = fixture_analysis
    events = _star_events(analysis)
    for plan in plans.values():
        counter = plan["overlay"]["counter"]
        values = [k["value"] for k in counter]
        assert values == sorted(values)
        assert values[-1] <= analysis["totals"]["stars_verified"]
        # every counted gain inside the edit appears at the moment it is visible, with the right running total
        for e in events:
            out_t = _to_out(plan, e["t"])
            if out_t is None:
                continue
            running = sum(x["delta"] for x in events if x["t"] <= e["t"])
            assert any(abs(k["t"] - out_t) < 1e-6 and k["value"] == running for k in counter), (e, counter)
    assert plans["recap"]["overlay"]["outro"]["total"] == 36


def test_recap_shows_most_events(plans, fixture_analysis):
    analysis, _ = fixture_analysis
    shown = [e for e in _star_events(analysis) if _to_out(plans["recap"], e["t"], roles=("body",)) is not None]
    assert len(shown) >= 5


def test_quest_pops_inside_segments(plans):
    for plan in plans.values():
        segs = plan["segments"]
        hook_end, outro_start = segs[0]["out_end"], segs[-1]["out_start"]
        pops = plan["overlay"]["quests"]
        assert pops
        for pop in pops:
            assert hook_end - plan["xfade"] <= pop["t"] <= outro_start + plan["xfade"]
            assert pop["stars"] > 0 and pop["status"] in ("confirmed", "probable")


def test_hook_counter_hidden(plans):
    for plan in plans.values():
        hook = plan["segments"][0]
        assert plan["overlay"]["hook"]["end"] <= hook["out_end"]
        assert min(k["t"] for k in plan["overlay"]["counter"]) >= hook["out_end"] - plan["xfade"] - 1e-6


def test_disclosure_card_then_badge(plans, brand):
    for plan in plans.values():
        d = plan["overlay"]["disclosure"]
        assert d["card_start"] == 0 and d["card_end"] >= 3.0
        assert d["badge_end"] == plan["duration"]
        assert d["text"] == brand["disclosure"]["short"]


def test_layout_rects_inside_frame_and_safe_area(plans):
    for plan in plans.values():
        layout = plan["layout"]
        assert layout["mode"] == "split_ui"
        main, panel, star = layout["main_rect"], layout["panel_rect"], layout["star_rect"]
        for r in (main, panel, star):
            assert all(v % 2 == 0 for v in r.values()), r  # even sizes for yuv420p
            assert 0 <= r["x"] and r["x"] + r["w"] <= 1080 and 0 <= r["y"] and r["y"] + r["h"] <= 1920
        assert main["w"] == 1080
        assert main["y"] + main["h"] <= panel["y"]  # panel inset sits below the gameplay
        assert panel["y"] + panel["h"] <= 1530      # above the platform caption area
        src_aspect = 1280 / 720 * layout["panel_roi"]["w"] / layout["panel_roi"]["h"]
        assert abs(panel["w"] / panel["h"] - src_aspect) < 0.05


def test_uncalibrated_plan_has_no_counter(fixture_analysis, brand):
    from studio.planner import plan_variant

    analysis = copy.deepcopy(fixture_analysis[0])
    analysis.update(calibrated=False, star_events=[], quests=[])
    analysis["totals"].update(stars_verified=None, quests_confirmed=0, quests_probable=0, rank_ups=0)
    analysis["highlights"] = [h for h in analysis["highlights"] if not h["event_ids"]]
    plan = plan_variant(analysis, brand, _variant(brand, "highlight"))
    assert plan["overlay"]["counter"] == [] and plan["overlay"]["quests"] == []
    assert plan["overlay"]["hook"]["text"] in brand["hooks_no_numbers"]
    assert plan["duration"] > 5
