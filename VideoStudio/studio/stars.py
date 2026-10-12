"""Turn noisy star-counter readings into trustworthy rank-star events.

Only *observable* changes are counted: a value must be read in `confirm_samples`
consecutive valid samples to become stable, and a step between two stable values is
counted only when it is a plausible gain with an unchanged denominator that is not
reverted shortly afterwards. Everything else is kept as a `review` item so nothing is
silently dropped or silently counted.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, field


@dataclass(frozen=True)
class Reading:
    t: float
    cur: int | None
    total: int | None
    conf: float


@dataclass
class StarEvent:
    id: str
    t: float
    t_prev: float
    kind: str  # "gain" | "rank_up" | "review"
    from_cur: int
    to_cur: int
    from_total: int | None
    to_total: int | None
    delta: int | None
    counted: bool
    reason: str = ""

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class StableRun:
    cur: int
    total: int | None
    t_first: float
    t_last: float
    count: int


@dataclass
class StarTimeline:
    stable: list[StableRun] = field(default_factory=list)
    events: list[StarEvent] = field(default_factory=list)

    @property
    def verified_gain(self) -> int:
        return sum(e.delta for e in self.events if e.counted)

    def gained_before(self, t: float) -> int:
        return sum(e.delta for e in self.events if e.counted and e.t <= t)


def _runs(readings: list[Reading], min_conf: float) -> list[StableRun]:
    runs: list[StableRun] = []
    for r in readings:
        if r.cur is None or r.conf < min_conf:
            continue  # unreadable samples (popups, motion blur) never break a run
        if runs and (runs[-1].cur, runs[-1].total) == (r.cur, r.total):
            runs[-1].t_last = r.t
            runs[-1].count += 1
        else:
            runs.append(StableRun(r.cur, r.total, r.t, r.t, 1))
    return runs


def _stable(runs: list[StableRun], confirm_samples: int) -> list[StableRun]:
    stable: list[StableRun] = []
    for run in runs:
        if run.count < confirm_samples:
            continue
        if stable and (stable[-1].cur, stable[-1].total) == (run.cur, run.total):
            stable[-1].t_last = run.t_last
            stable[-1].count += run.count
        else:
            stable.append(StableRun(run.cur, run.total, run.t_first, run.t_last, run.count))
    return stable


def _classify(a: StableRun, b: StableRun, max_gain: int) -> tuple[str, int | None, str]:
    delta = b.cur - a.cur
    if a.total == b.total:
        if 1 <= delta <= max_gain:
            return "gain", delta, ""
        if delta > max_gain:
            return "review", delta, f"jump of {delta} exceeds max_gain {max_gain}"
        return "review", delta, "counter dropped without a rank change"
    if delta < 0 and a.total is not None and b.total is not None:
        return "rank_up", None, "counter reset with a new requirement"
    return "review", delta, "requirement changed without a reset"


def detect_star_events(readings: list[Reading], *, min_conf: float = 0.6, confirm_samples: int = 3,
                       max_gain: int = 60, revert_window: float = 5.0) -> StarTimeline:
    stable = _stable(_runs(sorted(readings, key=lambda r: r.t), min_conf), confirm_samples)
    events: list[StarEvent] = []
    for i, (a, b) in enumerate(zip(stable, stable[1:]), start=1):
        kind, delta, reason = _classify(a, b, max_gain)
        events.append(StarEvent(f"s{i}", b.t_first, a.t_last, kind, a.cur, b.cur, a.total, b.total, delta,
                                kind == "gain", reason))
    # a step that is undone shortly afterwards was a misread, not progress
    for e1, e2 in zip(events, events[1:]):
        if (e2.to_cur, e2.to_total) == (e1.from_cur, e1.from_total) and e2.t - e1.t <= revert_window:
            for e in (e1, e2):
                e.kind, e.counted, e.reason = "review", False, "reverted within %.1fs" % revert_window
    return StarTimeline(stable, events)
