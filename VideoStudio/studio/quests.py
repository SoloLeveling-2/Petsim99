"""Decide which star gains are real quest completions, and name them."""
from __future__ import annotations

import difflib
import re
from dataclasses import asdict, dataclass, field

import numpy as np

from .stars import StarEvent

_STATUS_WORDS = {"complete", "completed", "complete!", "claim", "claimed", "quests", "quest", "done", "new", "goals"}
_PROGRESS = re.compile(r"^[\d.,kmb%\s/]+$", re.IGNORECASE)


@dataclass(frozen=True)
class Peak:
    t: float
    score: float


@dataclass
class QuestEvent:
    id: str
    t: float
    status: str  # "confirmed" | "probable" | "visual_only"
    stars: int
    name: str | None = None
    star_event: str | None = None
    evidence: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)


def find_peaks(series: list[tuple[float, float]], k: float = 4.0, min_gap: float = 2.0,
               min_score: float = 0.0) -> list[Peak]:
    """Local maxima above median + k * robust sigma, at least `min_gap` seconds apart."""
    if len(series) < 3:
        return []
    values = np.array([v for _, v in series], dtype=float)
    median = float(np.median(values))
    sigma = 1.4826 * float(np.median(np.abs(values - median))) or 1e-6
    threshold = max(min_score, median + k * sigma)
    candidates = [Peak(t, v) for i, (t, v) in enumerate(series)
                  if v > threshold and v >= values[max(0, i - 1)] and v >= values[min(len(values) - 1, i + 1)]]
    kept: list[Peak] = []
    for peak in sorted(candidates, key=lambda p: -p.score):
        if all(abs(peak.t - k_.t) >= min_gap for k_ in kept):
            kept.append(peak)
    return sorted(kept, key=lambda p: p.t)


def _clean(line: str) -> str:
    return re.sub(r"\s+", " ", line.strip().lower())


def _is_quest_line(line: str) -> bool:
    cleaned = _clean(line)
    letters = sum(c.isalpha() for c in cleaned)
    return letters >= 3 and cleaned not in _STATUS_WORDS and not _PROGRESS.match(cleaned)


def diff_quest_names(before: list[str], after: list[str]) -> list[str]:
    """Quest lines visible before a completion that are gone afterwards (fuzzy, OCR-tolerant)."""
    after_clean = [_clean(a) for a in after if _is_quest_line(a)]
    gone = []
    for line in before:
        if not _is_quest_line(line):
            continue
        cleaned = _clean(line)
        if not any(difflib.SequenceMatcher(None, cleaned, a).ratio() >= 0.8 for a in after_clean):
            gone.append(line.strip())
    return gone


def _snapshot(texts: list[tuple[float, list[str]]], at_or_before: float | None = None,
              at_or_after: float | None = None) -> list[str] | None:
    if at_or_before is not None:
        options = [lines for t, lines in texts if t <= at_or_before]
        return options[-1] if options else None
    options = [lines for t, lines in texts if t >= at_or_after]
    return options[0] if options else None


def classify_quests(star_events: list[StarEvent], panel_peaks: list[Peak], banner_peaks: list[Peak],
                    panel_text: list[tuple[float, list[str]]], before: float = 3.0,
                    after: float = 2.0) -> list[QuestEvent]:
    texts = sorted(panel_text, key=lambda x: x[0])
    used: set[tuple[str, float]] = set()
    quests: list[QuestEvent] = []
    for event in star_events:
        if not event.counted:
            continue
        lo, hi = event.t - before, event.t + after
        evidence = [("banner", p) for p in banner_peaks if lo <= p.t <= hi] + \
                   [("panel", p) for p in panel_peaks if lo <= p.t <= hi]
        used.update((kind, p.t) for kind, p in evidence)
        times = [p.t for _, p in evidence]
        moment = min(times) if times else event.t
        name = None
        prev = _snapshot(texts, at_or_before=min(moment, event.t) - 0.5)
        nxt = _snapshot(texts, at_or_after=max([event.t] + times) + 1.0)
        if prev is not None and nxt is not None:
            gone = diff_quest_names(prev, nxt)
            name = gone[0] if len(gone) == 1 else (" + ".join(gone) if gone else None)
        quests.append(QuestEvent("", moment, "confirmed" if evidence else "probable", event.delta, name, event.id,
                                 [f"{kind} change at {p.t:.1f}s (score {p.score:.1f})" for kind, p in evidence]
                                 + [f"star counter {event.from_cur}->{event.to_cur} at {event.t:.1f}s"]))
    for kind, peaks in (("banner", banner_peaks), ("panel", panel_peaks)):
        for p in peaks:
            if (kind, p.t) not in used:
                quests.append(QuestEvent("", p.t, "visual_only", 0, None, None,
                                         [f"{kind} change at {p.t:.1f}s with no star gain"]))
    quests.sort(key=lambda q: q.t)
    for i, q in enumerate(quests, start=1):
        q.id = f"q{i}"
    return quests
