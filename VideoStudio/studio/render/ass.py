"""Fallback overlay as an ASS subtitle script (libass), for machines without Node/Remotion.

Same timeline and the same facts as the Remotion overlay, with simpler animation.
"""
from __future__ import annotations

from pathlib import Path


def _c(hex_rgb: str, alpha: int = 0) -> str:
    h = hex_rgb.lstrip("#")
    return f"&H{alpha:02X}{h[4:6]}{h[2:4]}{h[0:2]}".upper()


def _t(seconds: float) -> str:
    seconds = max(0.0, seconds)
    cs = int(round(seconds * 100))
    return f"{cs // 360000}:{cs // 6000 % 60:02d}:{cs // 100 % 60:02d}.{cs % 100:02d}"


def _esc(text: str) -> str:
    return text.replace("\\", "/").replace("{", "(").replace("}", ")")


def _clock(seconds: float) -> str:
    s = max(0, int(seconds))
    return f"{s // 60:02d}:{s % 60:02d}"


def _balanced_lines(words: list[str], max_chars: int) -> list[list[str]]:
    """One line if short, otherwise two lines of similar length (libass would wrap unevenly)."""
    if len(" ".join(words)) <= max_chars or len(words) < 2:
        return [words]
    best = min(range(1, len(words)), key=lambda i: (abs(len(" ".join(words[:i])) - len(" ".join(words[i:]))), -i))
    return [words[:best], words[best:]]


def _src_time(clock: list[dict], t: float) -> float | None:
    best = None
    for a, b in zip(clock[::2], clock[1::2]):
        if a["t"] <= t <= b["t"] and b["t"] > a["t"]:
            best = a["src_t"] + (t - a["t"]) * (b["src_t"] - a["src_t"]) / (b["t"] - a["t"])
    return best


def build_ass(plan: dict) -> str:
    ov, colors = plan["overlay"], plan["brand"]["colors"]
    font = plan["brand"]["font"]["family"]
    main = plan["layout"]["main_rect"]
    ink, paper, primary = _c(colors["ink"]), _c(colors["paper"]), _c(colors["primary"])
    accent, highlight = _c(colors["accent"]), _c(colors["highlight"])
    box = _c(colors["ink"], 0x30)
    styles = [
        # Name, size, primary, outline(box) colour, border style, outline, shadow, alignment
        ("Hook", 104, paper, ink, 1, 9, 4, 8),
        ("Sub", 44, paper, highlight, 3, 10, 0, 8),
        ("Counter", 84, primary, ink, 1, 8, 3, 7),
        ("Label", 26, paper, ink, 1, 3, 0, 7),
        ("Clock", 44, paper, box, 3, 8, 0, 9),
        ("Pop", 72, paper, accent, 3, 16, 0, 5),
        ("PopName", 50, paper, ink, 1, 7, 3, 5),
        ("Card", 36, paper, box, 3, 18, 0, 2),
        ("Badge", 30, paper, box, 3, 10, 0, 2),
        ("Rank", 160, primary, ink, 1, 14, 5, 5),
        ("Outro", 180, primary, ink, 1, 14, 5, 5),
        ("Cta", 46, ink, accent, 3, 14, 0, 5),
    ]
    lines = [
        "[Script Info]", "ScriptType: v4.00+", "PlayResX: 1080", "PlayResY: 1920", "WrapStyle: 0",
        "ScaledBorderAndShadow: yes", "", "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, "
        "Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, "
        "MarginR, MarginV, Encoding",
    ]
    for name, size, fill, outline, border, width, shadow, align in styles:
        lines.append(f"Style: {name},{font},{size},{fill},{fill},{outline},&H80000000,0,0,0,0,100,100,1,0,"
                     f"{border},{width},{shadow},{align},60,60,60,1")
    lines += ["", "[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"]

    def ev(start: float, end: float, style: str, text: str, layer: int = 1) -> None:
        if end > start:
            lines.append(f"Dialogue: {layer},{_t(start)},{_t(end)},{style},,0,0,0,,{text}")

    hook = ov["hook"]
    lines_ = _balanced_lines(hook["text"].split(), max_chars=13)
    words = "\\N".join(" ".join(f"{{\\c{primary}}}{_esc(w)}{{\\c{paper}}}" if any(ch.isdigit() or ch == "+" for ch in w)
                                else _esc(w) for w in line) for line in lines_)
    size = 104 if len(lines_) == 1 else 88
    ev(hook["start"], hook["end"], "Hook",
       f"{{\\pos(540,150)\\fs{size}\\fad(0,200)\\fscx40\\fscy40\\t(0,220,\\fscx100\\fscy100)}}{words}")
    sub_y = 150 + int(size * 1.08 * len(lines_)) + 14
    ev(hook["start"] + 0.3, hook["end"], "Sub", f"{{\\pos(540,{sub_y})\\fad(150,200)}}{_esc(hook['sub'])}")

    d = ov["disclosure"]
    ev(d["card_start"], d["card_end"], "Card",
       f"{{\\pos(540,1530)\\fad(200,150)}}{{\\c{_c(colors['danger'])}}}{_esc(d['title'])}{{\\c{paper}}}\\N{_esc(d['body'])}")
    ev(d["badge_start"], d["badge_end"], "Badge", f"{{\\pos(540,1512)\\fad(200,0)}}{_esc(d['text'])}")

    outro_start = ov["outro"]["start"]
    keys = ov["counter"]
    for k, nxt in zip(keys, keys[1:] + [None]):
        end = min(nxt["t"] if nxt else outro_start, outro_start)
        pop = "\\fscx135\\fscy135\\t(0,300,\\fscx100\\fscy100)" if k.get("delta") else ""
        ev(k["t"], end, "Counter", f"{{\\pos({main['x'] + 40},{main['y'] + 24}){pop}}}+{k['value']}")
        if k.get("delta"):
            ev(k["t"], min(k["t"] + 1.2, end + 1.2), "Counter",
               f"{{\\c{accent}\\fs60\\move({main['x'] + 300},{main['y'] + 40},{main['x'] + 300},{main['y'] - 10})"
               f"\\fad(0,400)}}+{k['delta']}", layer=2)
    if keys:
        ev(keys[0]["t"], outro_start, "Label", f"{{\\pos({main['x'] + 44},{main['y'] + 112})}}RANK STARS THIS RUN")

    clock = ov["clock"]
    if clock:
        t, step, current, since = clock[0]["t"], 0.25, None, clock[0]["t"]
        while t < outro_start:
            src = _src_time(clock, t)
            text = _clock(src) if src is not None else None
            if text != current:
                if current:
                    ev(since, t, "Clock", f"{{\\pos({main['x'] + main['w'] - 40},{main['y'] + 30})}}{current}")
                current, since = text, t
            t += step
        if current:
            ev(since, outro_start, "Clock", f"{{\\pos({main['x'] + main['w'] - 40},{main['y'] + 30})}}{current}")
    for s in ov["speedups"]:
        ev(s["start"], s["end"], "Badge", f"{{\\an9\\pos({main['x'] + main['w'] - 40},{main['y'] + 110})\\c{ink}"
                                          f"\\3c{accent}}}{s['speed']:g}x SPEED")

    y_pop = int(main["y"] + main["h"] * 0.45)
    for pop in ov["quests"]:
        style_colour = "" if pop["status"] == "confirmed" else f"\\3c{highlight}"
        ev(pop["t"], pop["t"] + 1.9, "Pop",
           f"{{\\pos(540,{y_pop}){style_colour}\\fscx50\\fscy50\\t(0,180,\\fscx105\\fscy105)\\t(180,280,\\fscx100\\fscy100)"
           f"\\fad(0,250)}}{_esc(pop['label'])}", layer=3)
        name = f"{_esc(pop['name'])}  " if pop.get("name") else ""
        ev(pop["t"] + 0.15, pop["t"] + 1.9, "PopName",
           f"{{\\pos(540,{y_pop + 110})\\fad(120,250)}}{name}{{\\c{primary}}}+{pop['stars']} STARS", layer=3)
    for r in ov["rank_ups"]:
        ev(r["t"], r["t"] + 2.4, "Rank",
           f"{{\\pos(540,{main['y'] + 220})\\fscx30\\fscy30\\t(0,250,\\fscx110\\fscy110)\\t(250,400,\\fscx100\\fscy100)"
           f"\\fad(0,300)}}RANK UP!", layer=4)

    panel = plan["layout"].get("panel_rect")
    if panel:
        ev(hook["end"], ov["outro"]["end"], "Label", f"{{\\pos({panel['x'] + 10},{panel['y'] - 34})}}LIVE QUEST PANEL")

    o = ov["outro"]
    cy = main["y"] + main["h"] * 0.45
    if o["total"] is not None:
        ev(o["start"], o["end"], "PopName", f"{{\\pos(540,{int(cy - 170)})\\fad(200,0)}}WHOLE RUN TOTAL", layer=5)
        ev(o["start"], o["end"], "Outro", f"{{\\pos(540,{int(cy)})\\fscx40\\fscy40\\t(0,300,\\fscx100\\fscy100)}}+{o['total']}",
           layer=5)
    facts = [f"{o['quests']} QUESTS" if o["quests"] else "", f"{o['rank_ups']} RANK UP" if o["rank_ups"] else "",
             f"{o['minutes']} MIN RECORDING"]
    ev(o["start"] + 0.2, o["end"], "PopName", f"{{\\pos(540,{int(cy + 150)})\\fad(200,0)}}" +
       "  •  ".join(f for f in facts if f), layer=5)
    ev(o["start"] + 0.4, o["end"], "Cta", f"{{\\pos(540,{int(cy + 270)})\\fad(200,0)}}{_esc(o['cta'])}", layer=5)
    return "\n".join(lines) + "\n"


def write_ass(plan: dict, path: Path) -> Path:
    Path(path).write_text(build_ass(plan), encoding="utf-8")
    return Path(path)
