"""Score candidate clip windows: real events first, then raw on-screen/audio activity."""
from __future__ import annotations

from dataclasses import asdict, dataclass, field

import numpy as np


@dataclass
class Window:
    start: float
    end: float
    score: float
    reasons: list[str] = field(default_factory=list)
    event_ids: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)


def _robust_z(series: list[tuple[float, float]]) -> tuple[np.ndarray, np.ndarray]:
    if not series:
        return np.zeros(0), np.zeros(0)
    t = np.array([s[0] for s in series], dtype=float)
    v = np.array([s[1] for s in series], dtype=float)
    median = np.median(v)
    sigma = 1.4826 * np.median(np.abs(v - median)) or (np.std(v) or 1.0)
    return t, np.clip((v - median) / sigma, -3, 6)


def _mean_in(t: np.ndarray, z: np.ndarray, start: float, end: float) -> float:
    mask = (t >= start) & (t <= end)
    return float(z[mask].mean()) if mask.any() else 0.0


def activity_scorer(motion: list[tuple[float, float]], audio: list[tuple[float, float]]):
    """Return f(start, end) -> mean robust z-score of motion and audio in that span."""
    mt, mz = _robust_z(motion)
    at, az = _robust_z(audio)
    return lambda start, end: (_mean_in(mt, mz, start, end) + _mean_in(at, az, start, end)) / 2


def score_windows(motion: list[tuple[float, float]], audio: list[tuple[float, float]], events: list[dict],
                  duration: float, pre: float = 2.5, post: float = 2.5, activity_len: float = 4.0,
                  max_activity: int = 10) -> list[Window]:
    activity = activity_scorer(motion, audio)
    windows: list[Window] = []
    for ev in sorted(events, key=lambda e: e["t"]):
        start, end = max(0.0, ev["t"] - pre), min(duration, ev["t"] + post)
        reason = f"{ev['kind']} {ev['id']} at {ev['t']:.1f}s"
        if windows and start <= windows[-1].end:
            last = windows[-1]
            last.end = max(last.end, end)
            last.score = max(last.score, ev["weight"]) + 0.5 * min(last.score, ev["weight"])
            last.event_ids.append(ev["id"])
            last.reasons.append(reason)
        else:
            windows.append(Window(start, end, float(ev["weight"]), [reason], [ev["id"]]))
    for w in windows:
        act = activity(w.start, w.end)
        w.score = round(w.score + 0.5 * act, 3)
        w.reasons.append(f"activity {act:+.2f}")

    candidates = []
    t = 0.0
    while t + activity_len <= duration:
        candidates.append(Window(t, t + activity_len, round(activity(t, t + activity_len), 3)))
        t += 1.0
    chosen: list[Window] = []
    for c in sorted(candidates, key=lambda w: -w.score):
        if len(chosen) >= max_activity or c.score <= 0:
            break
        if any(c.start < w.end and w.start < c.end for w in windows + chosen):
            continue
        c.reasons.append(f"on-screen/audio activity {c.score:+.2f}")
        chosen.append(c)
    return sorted(windows + chosen, key=lambda w: -w.score)
