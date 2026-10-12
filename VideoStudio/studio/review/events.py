"""The verified events that appear in one edit, with their evidence images."""
from __future__ import annotations

import shutil
from pathlib import Path


def review_events(analysis: dict, plan: dict, analysis_dir: Path, render_dir: Path) -> list[dict]:
    """Quest completions and rank-ups shown in the edit's body, with evidence copied into the render."""
    body = [s for s in plan["segments"] if s["role"] != "hook"]
    inside = lambda t: any(s["src_start"] <= t < s["src_end"] for s in body)  # noqa: E731
    events = []
    for q in analysis["quests"]:
        if q["status"] in ("confirmed", "probable") and inside(q["t"]):
            events.append({"id": q["id"], "t": q["t"], "kind": "quest", "status": q["status"], "name": q["name"],
                           "stars": q["stars"], "proof": q["evidence"]})
    for e in analysis["star_events"]:
        if e["kind"] == "rank_up" and inside(e["t"] - 0.8):
            events.append({"id": e["id"], "t": e["t"], "kind": "rank up", "status": "counter reset",
                           "name": f"{e['from_cur']}/{e['from_total']} -> {e['to_cur']}/{e['to_total']}", "stars": None,
                           "proof": [e["reason"]]})
    (render_dir / "evidence").mkdir(exist_ok=True)
    for ev in events:
        ev["evidence"] = {}
        for kind, rel in analysis.get("evidence", {}).get(ev["id"], {}).items():
            src = Path(analysis_dir) / rel
            if src.is_file():
                shutil.copy2(src, render_dir / "evidence" / src.name)
                ev["evidence"][kind] = f"evidence/{src.name}"
    return sorted(events, key=lambda e: e["t"])
