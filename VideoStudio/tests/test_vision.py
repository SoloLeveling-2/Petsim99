import json
from types import SimpleNamespace

import cv2
import numpy as np

from studio.stars import StarEvent


class FakeMessages:
    def __init__(self, replies):
        self.replies = list(replies)
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        reply = self.replies.pop(0)
        if reply == "refusal":
            return SimpleNamespace(stop_reason="refusal", content=[], stop_details=SimpleNamespace(category="cyber"),
                                   usage=SimpleNamespace(input_tokens=900, output_tokens=0))
        return SimpleNamespace(stop_reason="end_turn", content=[SimpleNamespace(type="text", text=json.dumps(reply))],
                               stop_details=None, usage=SimpleNamespace(input_tokens=900, output_tokens=60))


def _client(replies):
    return SimpleNamespace(beta=SimpleNamespace(messages=FakeMessages(replies)))


def _setup(tmp_path, n):
    (tmp_path / "evidence").mkdir()
    events, evidence = [], {}
    for i in range(n):
        for side in ("before", "after"):
            cv2.imwrite(str(tmp_path / "evidence" / f"s{i}_{side}.jpg"), np.full((40, 120, 3), 90, np.uint8))
        events.append(StarEvent(f"s{i}", 10.0 * i, 10.0 * i - 0.5, "gain", 10 + i, 13 + i, 40, 40, 3, True))
        evidence[f"q{i}"] = {"star_before": f"evidence/s{i}_before.jpg", "star_after": f"evidence/s{i}_after.jpg"}
    star_to_evidence = {f"s{i}": f"q{i}" for i in range(n)}
    return events, evidence, star_to_evidence


def _reply(before, after):
    return {"before_value": before, "before_total": 40, "after_value": after, "after_total": 40,
            "readable": True, "notes": ""}


def test_vision_disabled_without_budget(tmp_path):
    from studio.vision import verify_events

    events, evidence, mapping = _setup(tmp_path, 2)
    report = verify_events(tmp_path, evidence, events, mapping, budget=0, client=_client([]))
    assert report["status"].startswith("skipped")
    assert report["events_checked"] == 0


def test_vision_respects_budget_and_compares(tmp_path):
    from studio.vision import MODEL, verify_events

    events, evidence, mapping = _setup(tmp_path, 3)
    client = _client([_reply(10, 13), _reply(11, 15)])
    report = verify_events(tmp_path, evidence, events, mapping, budget=2, client=client)
    calls = client.beta.messages.calls
    assert len(calls) == 2  # third event skipped: budget
    assert report["events_checked"] == 2
    assert [r["agrees"] for r in report["results"]] == [True, False]
    assert report["disagreements"] == ["s1"]
    req = calls[0]
    assert req["model"] == MODEL == "claude-opus-5-5"
    assert req["fallbacks"] == "default" and "server-side-fallback-2026-07-01" in req["betas"]
    assert req["output_config"]["effort"] == "low"
    assert req["output_config"]["format"]["type"] == "json_schema"
    images = [b for b in req["messages"][0]["content"] if b["type"] == "image"]
    assert len(images) == 2 and images[0]["source"]["media_type"] == "image/jpeg"
    assert report["usage"] == {"input_tokens": 1800, "output_tokens": 120}


def test_vision_refusal_recorded_not_crashing(tmp_path):
    from studio.vision import verify_events

    events, evidence, mapping = _setup(tmp_path, 1)
    report = verify_events(tmp_path, evidence, events, mapping, budget=5, client=_client(["refusal"]))
    assert report["results"][0]["status"] == "refused"
    assert report["results"][0]["agrees"] is None


def test_cost_estimate_scales_with_events():
    from studio.vision import estimate_cost

    one, ten = estimate_cost(1), estimate_cost(10)
    assert ten["usd"] > one["usd"] > 0
    assert ten["model"] == "claude-opus-5-5"
