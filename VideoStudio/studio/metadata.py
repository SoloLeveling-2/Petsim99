"""Platform-specific titles, captions and hashtags built only from verified facts."""
from __future__ import annotations

import re

PLATFORMS = ("youtube_shorts", "tiktok")
YT_TITLE_MAX = 100
YT_DESCRIPTION_MAX = 5000
YT_TAGS_MAX_CHARS = 500
TIKTOK_CAPTION_MAX = 2200


class BlockedTermError(ValueError):
    pass


def guard_text(text: str, blocked_terms: list[str]) -> str:
    lowered = text.lower()
    for term in blocked_terms:
        if term and term.lower() in lowered:
            raise BlockedTermError(f"Generated text contains the blocked term '{term}': {text[:80]!r}")
    return text


def facts_from(analysis: dict) -> dict:
    totals = analysis.get("totals", {})
    duration = float(analysis.get("source", {}).get("duration") or 0)
    return {
        "stars_verified": totals.get("stars_verified"),
        "quests_confirmed": totals.get("quests_confirmed") or 0,
        "quests_probable": totals.get("quests_probable") or 0,
        "rank_ups": totals.get("rank_ups") or 0,
        "minutes": max(1, round(duration / 60)),
    }


def _fill(template: str, facts: dict) -> str | None:
    if "{stars}" in template and not facts["stars_verified"]:
        return None
    if "{quests}" in template and not facts["quests_confirmed"]:
        return None
    if "{rank_ups}" in template and not facts["rank_ups"]:
        return None
    text = template.format(stars=facts["stars_verified"], quests=facts["quests_confirmed"],
                           rank_ups=facts["rank_ups"], minutes=facts["minutes"])
    return re.sub(r"\b1 ([Mm])inutes\b", r"1 \1inute", text)


def _pick(templates: list[str], fallbacks: list[str], facts: dict, limit: int) -> str:
    for template in list(templates) + list(fallbacks):
        text = _fill(template, facts)
        if text and len(text) <= limit:
            return text
    return (_fill(fallbacks[0], facts) or fallbacks[0])[:limit].rstrip()


def _summary(facts: dict) -> str:
    if facts["stars_verified"] is None:
        return (f"Recorded run: {facts['minutes']} minutes. Star counts are not shown because this recording "
                f"has not been calibrated yet.")
    parts = [f"+{facts['stars_verified']} rank stars counted on screen"]
    if facts["quests_confirmed"]:
        parts.append(f"{facts['quests_confirmed']} confirmed quest completions")
    if facts["rank_ups"]:
        parts.append(f"{facts['rank_ups']} rank up{'s' if facts['rank_ups'] != 1 else ''}")
    return f"Recorded run: {facts['minutes']} minutes. " + ", ".join(parts) + "."


def _research_note(research: dict | None) -> str:
    if research and research.get("keywords"):
        return f"{research.get('source', 'vidIQ')} ({research.get('fetched_at', 'date unknown')}): " \
               f"{len(research['keywords'])} keywords"
    return "none: default keywords, not vidIQ-validated"


def _tags(brand: dict, research: dict | None) -> list[str]:
    base = [brand["game_name"].lower(), "ps99", "pet sim 99", "roblox", brand["product_name"].lower(), "rank quests"]
    extra = [k["keyword"] for k in sorted((research or {}).get("keywords", []), key=lambda k: -k.get("score", 0))[:10]]
    tags, used = [], 0
    for tag in dict.fromkeys(extra + base):
        if used + len(tag) + 1 > YT_TAGS_MAX_CHARS:
            break
        tags.append(tag)
        used += len(tag) + 1
    return tags


def build_metadata(analysis: dict, plan: dict | None, brand: dict, research: dict | None = None) -> dict:
    facts = facts_from(analysis)
    disclosure = brand["disclosure"]
    titles = brand["titles"]
    music = (plan or {}).get("music") or {}
    music_line = f"Music: {music['title']} ({music['license_type']})." if music else ""

    yt_title = _pick(titles["youtube_shorts"], titles["youtube_shorts_no_numbers"], facts, YT_TITLE_MAX)
    yt_hashtags = brand["hashtags"]["youtube_shorts"]
    yt_description = "\n\n".join(x for x in [disclosure["caption"], _summary(facts), brand["cta"], music_line,
                                             " ".join(yt_hashtags)] if x)[:YT_DESCRIPTION_MAX]

    tt_line = _pick(titles["tiktok"], titles["tiktok_no_numbers"], facts, 150)
    tt_hashtags = brand["hashtags"]["tiktok"]
    tt_caption = "\n".join([tt_line, disclosure["caption"], brand["cta"], " ".join(tt_hashtags)])[:TIKTOK_CAPTION_MAX]

    common = {"facts": facts, "disclosure": disclosure["caption"], "on_screen_disclosure": disclosure["short"],
              "research": _research_note(research), "variant": (plan or {}).get("variant")}
    meta = {
        "youtube_shorts": {
            **common,
            "title": yt_title,
            "description": yt_description,
            "tags": _tags(brand, research),
            "hashtags": yt_hashtags,
            "platform_settings": [
                "Paid promotion: tick it if anyone paid or rewarded you for showing Auto Ranking.",
                "Audience (made for kids or not): you must choose this yourself in YouTube Studio.",
                "Altered or synthetic content label: not needed for real gameplay with text overlays.",
            ],
        },
        "tiktok": {
            **common,
            "caption": tt_caption,
            "hashtags": tt_hashtags,
            "platform_settings": [
                "Content disclosure: turn it on and pick 'Your brand' (or 'Branded content' if a third party "
                "pays you), because Auto Ranking is a paid service.",
                "AI-generated content label: off (real gameplay).",
            ],
        },
    }
    for text in _strings(meta):
        guard_text(text, brand.get("blocked_terms", []))
    return meta


def _strings(obj):
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for value in obj.values():
            yield from _strings(value)
    elif isinstance(obj, (list, tuple)):
        for value in obj:
            yield from _strings(value)


def validate_metadata(meta: dict, brand: dict) -> list[str]:
    errors = []
    disclosure = brand["disclosure"]["caption"]
    for platform in PLATFORMS:
        if platform not in meta:
            errors.append(f"{platform}: missing")
            continue
        post = meta[platform]
        body = post.get("description") if platform == "youtube_shorts" else post.get("caption")
        if disclosure not in (body or ""):
            errors.append(f"{platform}: paid-service disclosure missing from the caption/description")
        if "gem" not in post.get("on_screen_disclosure", "").lower():
            errors.append(f"{platform}: on-screen disclosure must say Auto Ranking is paid in gems")
        for text in _strings(post):
            if re.search(r"\{[a-z_]+\}", text):
                errors.append(f"{platform}: unfilled placeholder in {text[:60]!r}")
            try:
                guard_text(text, brand.get("blocked_terms", []))
            except BlockedTermError as exc:
                errors.append(f"{platform}: {exc}")
    yt = meta.get("youtube_shorts", {})
    if not 0 < len(yt.get("title", "")) <= YT_TITLE_MAX:
        errors.append("youtube_shorts: title must be 1-100 characters")
    if len(yt.get("description", "")) > YT_DESCRIPTION_MAX:
        errors.append("youtube_shorts: description over 5000 characters")
    if sum(len(t) + 1 for t in yt.get("tags", [])) > YT_TAGS_MAX_CHARS:
        errors.append("youtube_shorts: tags over 500 characters")
    if len(meta.get("tiktok", {}).get("caption", "")) > TIKTOK_CAPTION_MAX:
        errors.append("tiktok: caption over 2200 characters")
    return errors
