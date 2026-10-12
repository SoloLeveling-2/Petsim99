"""Edit decision list for one Short: which source spans, in what order, at what speed,
and exactly when each overlay (counter, quest pop, disclosure, outro) appears."""
from __future__ import annotations

import math
from dataclasses import dataclass, field

from .highlights import activity_scorer
from .metadata import facts_from, pick_template


@dataclass
class Moment:
    times: list[float]
    weight: float
    ids: list[str] = field(default_factory=list)

    @property
    def peak(self) -> float:
        return min(self.times)


def _moments(analysis: dict) -> list[Moment]:
    stars = {e["id"]: e for e in analysis["star_events"]}
    moments = []
    for q in analysis["quests"]:
        if q["status"] not in ("confirmed", "probable"):
            continue
        times = [q["t"]] + ([stars[q["star_event"]]["t"]] if q.get("star_event") in stars else [])
        moments.append(Moment(times, (6.0 if q["status"] == "confirmed" else 4.0) + math.log1p(q["stars"]), [q["id"]]))
    for e in analysis["star_events"]:
        if e["kind"] == "rank_up":
            moments.append(Moment([e["t"] - 0.8, e["t"]], 9.0, [e["id"]]))
    if not moments:  # uncalibrated: fall back to the most active footage
        for h in analysis["highlights"]:
            mid = (h["start"] + h["end"]) / 2
            moments.append(Moment([mid], h["score"], []))
    return moments


def _window(m: Moment, pre: float, post: float, duration: float) -> tuple[float, float]:
    return max(0.0, min(m.times) - pre), min(duration, max(m.times) + post)


def _merge(spans: list[tuple[float, float, Moment]]) -> list[tuple[float, float, Moment]]:
    merged: list[tuple[float, float, Moment]] = []
    for start, end, m in sorted(spans, key=lambda s: s[0]):
        if merged and start <= merged[-1][1]:
            s0, e0, m0 = merged[-1]
            combo = Moment(m0.times + m.times, max(m0.weight, m.weight) + 0.5 * min(m0.weight, m.weight), m0.ids + m.ids)
            merged[-1] = (s0, max(e0, end), combo)
        else:
            merged.append((start, end, m))
    return merged


def _segment(role: str, src_start: float, src_end: float, speed: float = 1.0) -> dict:
    return {"role": role, "src_start": round(src_start, 3), "src_end": round(src_end, 3), "speed": speed}


def _layout(analysis: dict) -> dict:
    rois = analysis.get("profile", {}).get("rois", {})
    if "quest_panel" in rois:
        return {"mode": "split_ui", "main": {"y": 400, "h": 810}, "panel_roi": rois["quest_panel"],
                "panel_box": {"y": 1230, "max_w": 820, "max_h": 200}, "star_roi": rois.get("star_counter")}
    return {"mode": "full", "main": {"y": 380, "h": 1000}, "panel_roi": None, "panel_box": None,
            "star_roi": rois.get("star_counter")}


def plan_variant(analysis: dict, brand: dict, variant: dict) -> dict:
    out = brand["output"]
    xfade = float(out.get("xfade_seconds", 0.25))
    duration = float(analysis["source"]["duration"])
    target = float(variant["target_seconds"])
    hook_s, outro_s = float(variant["hook_seconds"]), float(variant["outro_seconds"])
    pre, post = float(variant["clip_pre"]), float(variant["clip_post"])
    activity = activity_scorer(analysis["activity"]["motion"], analysis["activity"]["audio"])

    spans = _merge([(*_window(m, pre, post, duration), m) for m in _moments(analysis)])
    scored = sorted(spans, key=lambda s: -(s[2].weight + 0.5 * activity(s[0], s[1])))
    if not scored:
        scored = [(0.0, min(duration, target), Moment([min(duration, target) / 2], 0.0))]

    # hook: the strongest moment, shown first as a teaser
    best = scored[0][2]
    hook_start = max(0.0, min(duration - hook_s, best.peak - 0.45 * hook_s))
    hook = _segment("hook", hook_start, hook_start + hook_s)

    budget = target - hook_s - outro_s + xfade
    chosen, used = [], 0.0
    for start, end, m in scored:
        if len(chosen) >= variant["max_event_clips"]:
            break
        length = end - start
        if used + length - xfade > budget:
            continue
        chosen.append((start, end, m))
        used += length - xfade
    chosen.sort(key=lambda s: s[0])
    body = [_segment("body", s, e) for s, e, _ in chosen]

    # time-lapses across long gaps make the time compression visible (recap only)
    speed, tl_out = float(variant.get("timelapse_speed") or 0), float(variant.get("timelapse_seconds") or 0)
    if speed > 1 and tl_out > 0:
        with_tl = []
        for a, b in zip(body, body[1:] + [None]):
            with_tl.append(a)
            gap_end = b["src_start"] if b else duration - outro_s
            span = speed * tl_out
            if gap_end - a["src_end"] >= span + 2.0 and used + tl_out - xfade <= budget + 0.1 * target:
                mid = (a["src_end"] + gap_end) / 2
                with_tl.append(_segment("timelapse", mid - span / 2, mid + span / 2, speed))
                used += tl_out - xfade
        body = with_tl

    last_end = body[-1]["src_end"] if body else hook["src_end"]
    available = duration - last_end
    if available >= outro_s:
        outro = _segment("outro", last_end, last_end + outro_s)
    elif available >= outro_s * 0.25:  # slow motion over the final footage
        outro = _segment("outro", last_end, duration, round(available / outro_s, 4))
    else:
        start = max(0.0, duration - outro_s)
        if body:
            body[-1]["src_end"] = round(max(body[-1]["src_start"] + 1.0, start), 3)
        outro = _segment("outro", start, duration)
    segments = [hook] + body + [outro]

    t = 0.0
    for seg in segments:
        seg["out_start"] = round(t, 6)
        seg["out_end"] = round(t + (seg["src_end"] - seg["src_start"]) / seg["speed"], 6)
        t = seg["out_end"] - xfade
    total = segments[-1]["out_end"]

    facts = facts_from(analysis)
    stars = sorted((e for e in analysis["star_events"] if e["counted"]), key=lambda e: e["t"])
    star_by_id = {e["id"]: e for e in analysis["star_events"]}

    def gained(upto: float, inclusive: bool) -> int:
        return sum(e["delta"] for e in stars if (e["t"] <= upto if inclusive else e["t"] < upto))

    def to_out(seg: dict, src_t: float) -> float:
        return round(seg["out_start"] + (src_t - seg["src_start"]) / seg["speed"], 6)

    counter, clock, pops, rank_ups, speedups = [], [], [], [], []
    for seg in segments[1:]:
        clock += [{"t": seg["out_start"], "src_t": seg["src_start"]}, {"t": seg["out_end"], "src_t": seg["src_end"]}]
        if seg["speed"] != 1:
            speedups.append({"start": seg["out_start"], "end": seg["out_end"], "speed": seg["speed"]})
        if analysis.get("calibrated"):
            counter.append({"t": seg["out_start"], "value": gained(seg["src_start"], inclusive=False)})
            for e in stars:
                if seg["src_start"] <= e["t"] < seg["src_end"]:
                    counter.append({"t": to_out(seg, e["t"]), "value": gained(e["t"], inclusive=True),
                                    "delta": e["delta"]})
        if seg["role"] != "body":
            continue
        for q in analysis["quests"]:
            if q["status"] in ("confirmed", "probable") and seg["src_start"] <= q["t"] < seg["src_end"]:
                pops.append({"t": to_out(seg, q["t"]), "stars": q["stars"], "status": q["status"],
                             "name": q["name"],
                             "label": "QUEST COMPLETE" if q["status"] == "confirmed" else f"+{q['stars']} RANK STARS"})
        for e in analysis["star_events"]:
            if e["kind"] == "rank_up" and seg["src_start"] <= e["t"] - 0.8 < seg["src_end"]:
                rank_ups.append({"t": to_out(seg, e["t"] - 0.8), "to_total": star_by_id[e["id"]]["to_total"]})

    verified = facts["stars_verified"] is not None
    hook_text = pick_template(brand["hooks"] if verified else [], brand["hooks_no_numbers"], facts, 40)
    card_end = max(3.0, hook["out_end"] - xfade)
    return {
        "variant": variant["id"],
        "label": variant.get("label", variant["id"]),
        "width": out["width"], "height": out["height"], "fps": out["fps"],
        "xfade": xfade,
        "duration": round(total, 6),
        "source": {"path": analysis["source"]["path"], "sha256": analysis["source"]["sha256"],
                   "duration": duration, "width": analysis["source"]["width"], "height": analysis["source"]["height"],
                   "has_audio": analysis["source"]["has_audio"]},
        "segments": segments,
        "layout": _layout(analysis),
        "overlay": {
            "hook": {"start": 0.0, "end": round(hook["out_end"] - xfade, 6), "text": hook_text,
                     "sub": brand["product_name"]},
            "counter": counter,
            "clock": clock,
            "speedups": speedups,
            "quests": pops,
            "rank_ups": rank_ups,
            "disclosure": {"text": brand["disclosure"]["short"], "title": brand["disclosure"]["card_title"],
                           "body": brand["disclosure"]["card_body"], "card_start": 0.0, "card_end": card_end,
                           "badge_start": card_end, "badge_end": round(total, 6)},
            "outro": {"start": segments[-1]["out_start"], "end": round(total, 6), "total": facts["stars_verified"],
                      "quests": facts["quests_confirmed"], "rank_ups": facts["rank_ups"], "minutes": facts["minutes"],
                      "cta": brand["cta"], "handle": brand["handle"]},
        },
        "brand": {"colors": brand["colors"], "font": brand["font"], "channel_name": brand["channel_name"]},
        "music": None,
    }
