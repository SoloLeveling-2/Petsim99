"""Synthetic Pet Simulator 99-style recording with exact ground truth.

It imitates what the analyzer has to cope with in real footage: a star counter that
changes only on quest completions, a three-row quest panel whose progress text ticks up
constantly, completion banners, a rank-up reset, a popup that briefly covers the
counter, and a big panel change that is *not* a completion.
"""
from __future__ import annotations

import json
import subprocess
import wave
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

VERSION = 4
W, H, FPS, SECONDS = 1280, 720, 30, 72.0

STAR_BOX = (30, 200, 220, 56)
RANK_BOX = (30, 160, 160, 36)
PANEL_BOX = (20, 270, 300, 220)
BANNER_BOX = (384, 56, 512, 90)

START = (12, 40)
COMPLETIONS = [  # (time, quest, stars, row, replacement)
    (6.0, "Break 300 Coins", 3, 0, "Earn 1M Coins"),
    (13.5, "Hatch 50 Eggs", 4, 1, "Use 3 Potions"),
    (30.5, "Collect 5 Diamonds", 5, 2, "Break 500 Coins"),
    (36.0, "Earn 1M Coins", 6, 0, "Hatch 100 Eggs"),
    (42.0, "Use 3 Potions", 10, 1, "Open 3 Gifts"),
    (55.0, "Break 500 Coins", 3, 2, "Catch 5 Fish"),
    (63.0, "Hatch 100 Eggs", 5, 0, "Tap 200 Coins"),
]
RANK_UP_T = 48.0          # banner appears
RANK_RESET_T = 48.8       # counter shows the new rank's total
NEW_TOTAL = 60
VISUAL_ONLY_T = 21.0      # progress jump with a flash, no stars
OCCLUSION = (26.0, 27.2)  # popup covers the counter
STAR_DELAY = 0.4          # counter updates this long after the completion moment


@dataclass
class FixtureInfo:
    path: Path
    truth: dict
    profile_path: Path


def _star_state(t: float) -> tuple[int, int]:
    cur, total = START
    for when, _, stars, _, _ in COMPLETIONS:
        if when >= RANK_UP_T:
            continue
        if t >= when + STAR_DELAY:
            cur += stars
    if t >= RANK_RESET_T:
        cur, total = 0, NEW_TOTAL
        for when, _, stars, _, _ in COMPLETIONS:
            if when > RANK_UP_T and t >= when + STAR_DELAY:
                cur += stars
    return cur, total


def _rows(t: float) -> tuple[list[str], int | None]:
    rows = ["Break 300 Coins", "Hatch 50 Eggs", "Collect 5 Diamonds"]
    completing = None
    for when, quest, _, row, replacement in COMPLETIONS:
        if t >= when + 0.8:
            rows[row] = replacement
        elif t >= when:
            completing = row
    return rows, completing


def _outlined(img, text, org, scale, color, thick=2, outline=6, font=cv2.FONT_HERSHEY_DUPLEX):
    # Hershey glyph advance grows with stroke thickness, so the outline is drawn as offset
    # copies at the fill's thickness (a thicker stroke would run past the text's end).
    r = max(1, (outline - thick) // 2)
    for dx in range(-r, r + 1):
        for dy in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r:
                cv2.putText(img, text, (org[0] + dx, org[1] + dy), font, scale, (0, 0, 0), thick, cv2.LINE_AA)
    cv2.putText(img, text, org, font, scale, color, thick, cv2.LINE_AA)


def _star_icon(img, cx, cy, r, color=(61, 200, 255)):
    pts = []
    for i in range(10):
        ang = -np.pi / 2 + i * np.pi / 5
        rad = r if i % 2 == 0 else r * 0.45
        pts.append((cx + rad * np.cos(ang), cy + rad * np.sin(ang)))
    pts = np.array(pts, np.int32)
    cv2.fillPoly(img, [pts], color, cv2.LINE_AA)
    cv2.polylines(img, [pts], True, (0, 0, 0), 2, cv2.LINE_AA)


def _draw_frame(t: float, rng_pets: np.ndarray) -> np.ndarray:
    img = np.empty((H, W, 3), np.uint8)
    # grass gradient world
    grad = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    img[:, :, 0] = (60 + 30 * grad).astype(np.uint8)
    img[:, :, 1] = (150 + 50 * grad).astype(np.uint8)
    img[:, :, 2] = (70 + 20 * grad).astype(np.uint8)
    # tiles scrolling slowly
    off = int(t * 20) % 80
    for x in range(-80 + off, W, 80):
        cv2.line(img, (x, 0), (x, H), (70, 175, 85), 1)
    # pets: speed bursts around completions make "action" footage
    burst = max([np.exp(-((t - c[0]) ** 2) / 2.0) for c in COMPLETIONS] + [0.0])
    for i, (bx, by, sp, col) in enumerate(rng_pets):
        speed = sp * (1 + 4 * burst)
        x = int((bx + t * speed * 60) % (W - 400)) + 380
        y = int(by + 40 * np.sin(t * (1 + i % 3) + i))
        color = tuple(int(c) for c in col)
        cv2.circle(img, (x, y), 26, color, -1, cv2.LINE_AA)
        cv2.circle(img, (x - 8, y - 6), 5, (255, 255, 255), -1)
        cv2.circle(img, (x + 8, y - 6), 5, (255, 255, 255), -1)
    # rank label
    rank = 8 if t < RANK_RESET_T else 9
    x, y, w, h = RANK_BOX
    cv2.rectangle(img, (x, y), (x + w, y + h), (40, 30, 30), -1)
    _outlined(img, f"Rank {rank}", (x + 10, y + 27), 0.8, (255, 255, 255), 2, 5)
    # star counter
    cur, total = _star_state(t)
    x, y, w, h = STAR_BOX
    cv2.rectangle(img, (x, y), (x + w, y + h), (45, 30, 25), -1)
    cv2.rectangle(img, (x, y), (x + w, y + h), (0, 0, 0), 2)
    _star_icon(img, x + 30, y + 28, 20)
    _outlined(img, f"{cur}/{total}", (x + 62, y + 41), 1.15, (255, 255, 255), 2, 7)
    # quest panel
    x, y, w, h = PANEL_BOX
    overlay = img.copy()
    cv2.rectangle(overlay, (x, y), (x + w, y + h), (40, 25, 20), -1)
    img[:] = cv2.addWeighted(overlay, 0.82, img, 0.18, 0)
    _outlined(img, "QUESTS", (x + 12, y + 30), 0.8, (61, 200, 255), 2, 5)
    rows, completing = _rows(t)
    for r, name in enumerate(rows):
        ry = y + 50 + r * 56
        flash = abs(t - VISUAL_ONLY_T - 0.5) < 0.5 and r == 2
        if completing == r:
            cv2.rectangle(img, (x + 6, ry - 4), (x + w - 6, ry + 48), (60, 200, 60), -1)
        elif flash:
            cv2.rectangle(img, (x + 6, ry - 4), (x + w - 6, ry + 48), (40, 200, 230), -1)
        _outlined(img, name, (x + 14, ry + 20), 0.62, (255, 255, 255), 1, 4)
        if completing == r:
            label = "COMPLETE!"
        elif r == 2 and name == "Collect 5 Diamonds":
            label = "4/5" if t >= VISUAL_ONLY_T else "1/5"
        else:
            label = f"{int((t * 7 + r * 13) % 90) + 10}/100"  # constantly ticking progress
        _outlined(img, label, (x + 14, ry + 42), 0.55, (200, 230, 255), 1, 4)
    # banners
    bx, by, bw, bh = BANNER_BOX
    for when, *_ in COMPLETIONS:
        if when <= t < when + 1.5:
            cv2.rectangle(img, (bx, by), (bx + bw, by + bh), (60, 190, 60), -1)
            cv2.rectangle(img, (bx, by), (bx + bw, by + bh), (0, 0, 0), 3)
            _outlined(img, "QUEST COMPLETE!", (bx + 60, by + 60), 1.5, (255, 255, 255), 3, 8)
    if RANK_UP_T <= t < RANK_UP_T + 2.0:
        cv2.rectangle(img, (bx, by), (bx + bw, by + bh), (200, 60, 150), -1)
        cv2.rectangle(img, (bx, by), (bx + bw, by + bh), (0, 0, 0), 3)
        _outlined(img, "RANK UP!", (bx + 150, by + 62), 1.7, (255, 255, 255), 3, 8)
    # popup that covers the counter
    if OCCLUSION[0] <= t < OCCLUSION[1]:
        cv2.rectangle(img, (10, 190), (330, 280), (230, 230, 240), -1)
        cv2.rectangle(img, (10, 190), (330, 280), (0, 0, 0), 3)
        _outlined(img, "Lootbag!", (60, 248), 1.3, (60, 120, 255), 2, 6)
    return img


def _write_audio(path: Path) -> None:
    sr = 48000
    n = int(SECONDS * sr)
    t = np.arange(n) / sr
    rng = np.random.default_rng(3)
    audio = 0.02 * np.sin(2 * np.pi * 110 * t) + 0.004 * rng.standard_normal(n)
    for start in np.arange(0.7, SECONDS, 0.9):  # coin blips
        i = int(start * sr)
        seg = np.arange(int(0.06 * sr)) / sr
        audio[i:i + seg.size] += 0.08 * np.sin(2 * np.pi * 1400 * seg) * np.exp(-seg * 50)
    for when, *_ in COMPLETIONS + [(RANK_UP_T,)]:
        i = int(when * sr)
        seg = np.arange(int(0.6 * sr)) / sr
        chord = sum(np.sin(2 * np.pi * f * seg) for f in (523, 659, 784))
        audio[i:i + seg.size] += 0.18 * chord * np.exp(-seg * 4)
    audio = np.clip(audio, -1, 1)
    pcm = (audio * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sr)
        wav.writeframes(pcm.tobytes())


def _norm(box):
    x, y, w, h = box
    return {"x": x / W, "y": y / H, "w": w / W, "h": h / H}


def truth() -> dict:
    gains = []
    for when, quest, stars, _, _ in COMPLETIONS:
        before = _star_state(when + STAR_DELAY - 0.01)
        after = _star_state(when + STAR_DELAY + 0.01)
        gains.append({"t": when + STAR_DELAY, "quest_t": when, "quest": quest, "from": before[0], "to": after[0]})
    return {
        "version": VERSION,
        "duration": SECONDS,
        "star_gains": gains,
        "verified_total": sum(g["to"] - g["from"] for g in gains),
        "rank_ups": [{"t": RANK_RESET_T, "from": _star_state(RANK_RESET_T - 0.01), "to": _star_state(RANK_RESET_T + 0.01)}],
        "visual_only": [{"t": VISUAL_ONLY_T}],
        "occlusions": [{"start": OCCLUSION[0], "end": OCCLUSION[1]}],
    }


def make_fixture(out_dir: Path) -> FixtureInfo:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    video = out_dir / "VyHub Auto Ranking fixture.mp4"
    truth_path = out_dir / "truth.json"
    profile_path = out_dir / "profile.json"
    data = truth()
    if video.exists() and truth_path.exists() and json.loads(truth_path.read_text()).get("version") == VERSION:
        return FixtureInfo(video, data, profile_path)

    rng = np.random.default_rng(11)
    pets = [(rng.uniform(0, 800), rng.uniform(300, 650), rng.uniform(0.6, 1.4), rng.integers(40, 255, 3))
            for _ in range(9)]
    wav = out_dir / "audio.wav"
    _write_audio(wav)
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{W}x{H}", "-r", str(FPS),
           "-i", "-", "-i", str(wav), "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "128k", "-shortest", str(video)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for i in range(int(SECONDS * FPS)):
        proc.stdin.write(_draw_frame(i / FPS, pets).tobytes())
    proc.stdin.close()
    if proc.wait() != 0:
        raise RuntimeError("fixture encode failed")
    wav.unlink()

    profile = {
        "name": "synthetic_fixture",
        "rois": {"star_counter": _norm(STAR_BOX), "quest_panel": _norm(PANEL_BOX),
                 "completion_banner": _norm(BANNER_BOX), "rank_label": _norm(RANK_BOX)},
        "star_pattern": r"(?P<cur>\d{1,5})\s*/\s*(?P<total>\d{1,5})",
    }
    profile_path.write_text(json.dumps(profile, indent=2))
    truth_path.write_text(json.dumps(data, indent=2))
    return FixtureInfo(video, data, profile_path)
