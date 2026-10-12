from studio.stars import Reading, detect_star_events


def seq(*runs, start=0.0, step=0.5, conf=0.99):
    """runs: (cur, total, count) with cur=None meaning unreadable."""
    out, t = [], start
    for cur, total, count in runs:
        for _ in range(count):
            out.append(Reading(t, cur, total, conf))
            t += step
    return out


# --- stars -----------------------------------------------------------------------

def test_simple_gains():
    tl = detect_star_events(seq((10, 40, 6), (13, 40, 6), (20, 40, 6)))
    assert [(e.kind, e.delta, e.counted) for e in tl.events] == [("gain", 3, True), ("gain", 7, True)]
    assert tl.events[0].t == 3.0 and tl.events[0].t_prev == 2.5
    assert tl.verified_gain == 10


def test_flicker_ignored():
    tl = detect_star_events(seq((10, 40, 6), (18, 40, 1), (10, 40, 1), (13, 40, 6)))
    assert [(e.kind, e.delta) for e in tl.events] == [("gain", 3)]
    assert tl.verified_gain == 3


def test_revert_marks_review():
    tl = detect_star_events(seq((10, 40, 6), (18, 40, 4), (10, 40, 6)))
    assert [e.kind for e in tl.events] == ["review", "review"]
    assert not any(e.counted for e in tl.events)
    assert "revert" in tl.events[0].reason
    assert tl.verified_gain == 0


def test_implausible_jump_review():
    tl = detect_star_events(seq((10, 400, 6), (300, 400, 6)), max_gain=60)
    assert [(e.kind, e.counted) for e in tl.events] == [("review", False)]
    assert tl.verified_gain == 0


def test_rank_up_not_counted():
    tl = detect_star_events(seq((38, 40, 6), (0, 60, 6), (3, 60, 6)))
    assert [(e.kind, e.counted) for e in tl.events] == [("rank_up", False), ("gain", True)]
    assert tl.verified_gain == 3


def test_drop_without_total_change_is_review():
    tl = detect_star_events(seq((20, 40, 6), (2, 40, 6)))
    assert [(e.kind, e.counted) for e in tl.events] == [("review", False)]


def test_occlusion_none_readings_do_not_break_runs():
    tl = detect_star_events(seq((10, 40, 2), (None, None, 4), (10, 40, 1), (12, 40, 4)))
    assert [(e.kind, e.delta) for e in tl.events] == [("gain", 2)]


def test_low_confidence_readings_ignored():
    readings = seq((10, 40, 6)) + seq((50, 40, 6), start=3.0, conf=0.2) + seq((11, 40, 6), start=6.0)
    tl = detect_star_events(readings, min_conf=0.6)
    assert [(e.kind, e.delta) for e in tl.events] == [("gain", 1)]


def test_counter_without_total():
    tl = detect_star_events(seq((100, None, 6), (104, None, 6)))
    assert [(e.kind, e.delta, e.counted) for e in tl.events] == [("gain", 4, True)]


def test_gained_before():
    tl = detect_star_events(seq((10, 40, 6), (13, 40, 6), (20, 40, 6)))
    assert tl.gained_before(0.0) == 0
    assert tl.gained_before(3.0) == 3
    assert tl.gained_before(100.0) == 10


# --- quests ---------------------------------------------------------------------

def test_find_peaks_robust_threshold():
    from studio.quests import find_peaks

    series = [(i * 0.5, 1.0 + 0.1 * (i % 3)) for i in range(200)]
    series[40] = (20.0, 9.0)
    series[41] = (20.5, 7.0)
    series[120] = (60.0, 8.0)
    peaks = find_peaks(series, k=4.0, min_gap=2.0)
    assert [(p.t, p.score) for p in peaks] == [(20.0, 9.0), (60.0, 8.0)]


def test_quest_name_diff():
    from studio.quests import diff_quest_names

    before = ["QUESTS", "Break 300 Coins", "COMPLETE!", "Hatch 50 Eggs", "67/100", "Collect 5 Diamonds", "1/5"]
    after = ["QUESTS", "Earn 1M Coins", "19/100", "Hatch 50 Eggs", "68/100", "Collect 5 Diamonds", "1/5"]
    assert diff_quest_names(before, after) == ["Break 300 Coins"]
    # OCR noise on an unchanged line must not count as a completed quest
    assert diff_quest_names(["Hatch 50 Eggs"], ["Hatch 5O Eggs"]) == []


def test_confirmed_vs_probable_vs_visual_only():
    from studio.quests import Peak, classify_quests

    stars = detect_star_events(seq((10, 40, 20), (13, 40, 20), (17, 40, 20))).events  # gains at t=10, t=20
    panel = [Peak(9.5, 5.0), Peak(40.0, 4.0)]
    banner = []
    texts = [(8.0, ["Break 300 Coins", "Hatch 50 Eggs"]), (11.5, ["Earn 1M Coins", "Hatch 50 Eggs"])]
    quests = classify_quests(stars, panel, banner, texts)
    assert [(q.status, q.stars) for q in quests] == [("confirmed", 3), ("probable", 4), ("visual_only", 0)]
    assert quests[0].name == "Break 300 Coins"
    assert quests[0].t == 9.5  # the visible moment, not the counter update
    assert quests[1].name is None


# --- highlights -------------------------------------------------------------------

def test_windows_prefer_events():
    from studio.highlights import score_windows

    motion = [(i * 0.5, 1.0) for i in range(120)]
    motion[60] = (30.0, 9.0)  # action spike with no quest
    audio = [(i * 0.5, 0.1) for i in range(120)]
    events = [{"id": "q1", "t": 10.0, "weight": 6.0, "kind": "quest"}]
    windows = score_windows(motion, audio, events, duration=60.0)
    best = windows[0]
    assert best.event_ids == ["q1"]
    assert best.start == 7.5 and best.end == 12.5
    assert any(w.start <= 30.0 <= w.end and not w.event_ids for w in windows)


def test_overlapping_event_windows_merge():
    from studio.highlights import score_windows

    motion = [(i * 0.5, 1.0) for i in range(120)]
    audio = [(i * 0.5, 0.1) for i in range(120)]
    events = [{"id": "a", "t": 10.0, "weight": 6.0, "kind": "quest"},
              {"id": "b", "t": 12.0, "weight": 4.0, "kind": "quest"}]
    windows = [w for w in score_windows(motion, audio, events, duration=60.0) if w.event_ids]
    assert len(windows) == 1
    assert windows[0].event_ids == ["a", "b"]
    assert (windows[0].start, windows[0].end) == (7.5, 14.5)
