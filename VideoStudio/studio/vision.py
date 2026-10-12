"""Optional second opinion from Claude on star-counter changes (costs API credits).

Never runs unless the caller passes a positive `budget` (the CLI also requires an
explicit --vision flag and shows the estimate first). Claude reads the before/after
crops of the on-screen counter independently; disagreements with OCR are reported as
review items, never silently "fixed".
"""
from __future__ import annotations

import base64
import json
from pathlib import Path

MODEL = "claude-opus-5-5"
PRICE_PER_MTOK = {"input": 4.00, "output": 20.00}  # claude-opus-5-5, USD
EST_INPUT_TOKENS_PER_EVENT = 700
EST_OUTPUT_TOKENS_PER_EVENT = 450

SCHEMA = {
    "type": "object",
    "properties": {
        "before_value": {"type": ["integer", "null"]},
        "before_total": {"type": ["integer", "null"]},
        "after_value": {"type": ["integer", "null"]},
        "after_total": {"type": ["integer", "null"]},
        "readable": {"type": "boolean"},
        "notes": {"type": "string"},
    },
    "required": ["before_value", "before_total", "after_value", "after_total", "readable", "notes"],
    "additionalProperties": False,
}

PROMPT = ("These two images are crops of the rank-star counter in a Pet Simulator 99 gameplay recording: the first "
          "is just before a change, the second just after. Read the counter in each image exactly as displayed "
          "(format 'current/required', e.g. '19/40'). Use null for any number you cannot read with certainty, set "
          "readable to false if either image is unreadable, and put anything unusual in notes.")


def estimate_cost(events: int) -> dict:
    tokens_in, tokens_out = events * EST_INPUT_TOKENS_PER_EVENT, events * EST_OUTPUT_TOKENS_PER_EVENT
    usd = tokens_in / 1e6 * PRICE_PER_MTOK["input"] + tokens_out / 1e6 * PRICE_PER_MTOK["output"]
    return {"model": MODEL, "events": events, "input_tokens": tokens_in, "output_tokens": tokens_out,
            "usd": round(usd, 4)}


def _image_block(path: Path) -> dict:
    data = base64.standard_b64encode(Path(path).read_bytes()).decode("ascii")
    return {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": data}}


def _ask(client, before: Path, after: Path):
    return client.beta.messages.create(
        model=MODEL,
        max_tokens=4000,
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        output_config={"effort": "low", "format": {"type": "json_schema", "schema": SCHEMA}},
        messages=[{"role": "user", "content": [_image_block(before), _image_block(after),
                                                {"type": "text", "text": PROMPT}]}],
    )


def verify_events(out_dir: Path, evidence: dict, star_events: list, star_to_evidence: dict, budget: int,
                  client=None) -> dict:
    report = {"enabled": True, "model": MODEL, "status": "ok", "events_checked": 0, "results": [],
              "disagreements": [], "usage": {"input_tokens": 0, "output_tokens": 0}}
    candidates = [e for e in star_events if e.kind in ("gain", "review") and e.id in star_to_evidence]
    candidates.sort(key=lambda e: e.kind != "review")  # uncertain ones first
    if budget <= 0 or not candidates:
        report["status"] = "skipped: no budget" if budget <= 0 else "skipped: nothing to verify"
        return report
    errors = ()
    if client is None:
        try:
            import anthropic
        except ImportError:
            report["status"] = "skipped: the anthropic package is not installed (pip install anthropic)"
            return report
        client = anthropic.Anthropic()
        errors = (anthropic.APIStatusError, anthropic.APIConnectionError)

    for event in candidates[:budget]:
        item = evidence.get(star_to_evidence[event.id], {})
        if "star_before" not in item or "star_after" not in item:
            continue
        result = {"event_id": event.id, "ocr": [event.from_cur, event.to_cur], "status": "ok", "agrees": None}
        try:
            response = _ask(client, Path(out_dir) / item["star_before"], Path(out_dir) / item["star_after"])
        except errors as exc:  # auth, rate limit, server or network trouble: stop spending, keep what we have
            report["status"] = f"stopped: {type(exc).__name__}: {getattr(exc, 'message', exc)}"
            break
        usage = getattr(response, "usage", None)
        if usage is not None:
            report["usage"]["input_tokens"] += usage.input_tokens
            report["usage"]["output_tokens"] += usage.output_tokens
        report["events_checked"] += 1
        if response.stop_reason == "refusal":
            result["status"] = "refused"
        else:
            text = next((b.text for b in response.content if b.type == "text"), "{}")
            read = json.loads(text)
            result["vision"] = read
            if read.get("readable"):
                result["agrees"] = [read.get("before_value"), read.get("after_value")] == result["ocr"]
                if not result["agrees"]:
                    report["disagreements"].append(event.id)
        report["results"].append(result)
    return report
