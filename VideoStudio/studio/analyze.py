"""Analyze one recording: star counter, quest completions, activity and highlights."""
from __future__ import annotations

import json
import math
import time
from collections import deque
from dataclasses import asdict
from pathlib import Path

import cv2
import numpy as np

from .config import Profile, profile_to_dict
from .highlights import score_windows
from .media import FFMPEG, MediaInfo, SourceGuard, popen, probe
from .ocr import GatedReader, OcrEngine, parse_star_text
from .quests import Peak, classify_quests, find_peaks
from .sampler import MosaicLayout, default_threads, iter_samples
from .stars import Reading, detect_star_events

ANALYSIS_VERSION = 1


def _gray_thumb(img: np.ndarray, width: int = 96) -> np.ndarray:
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    h = max(4, int(round(gray.shape[0] * width / gray.shape[1])))
    return cv2.resize(gray, (width, h), interpolation=cv2.INTER_AREA).astype(np.float32)


def audio_rms(path: Path, window: float = 0.5, rate: int = 8000) -> list[tuple[float, float]]:
    """Loudness per window from a cheap 8 kHz mono decode of the audio track."""
    proc = popen([FFMPEG, "-hide_banner", "-v", "error", "-nostdin", "-i", str(path), "-vn", "-ac", "1",
                  "-ar", str(rate), "-f", "s16le", "-"], stdout=-1, stderr=-3)
    step = int(window * rate) * 2
    out, i = [], 0
    while True:
        buf = proc.stdout.read(step)
        if not buf:
            break
        pcm = np.frombuffer(buf[: len(buf) // 2 * 2], np.int16).astype(np.float32) / 32768
        out.append((round(i * window, 3), float(np.sqrt(np.mean(pcm ** 2))) if pcm.size else 0.0))
        i += 1
    proc.stdout.close()
    proc.wait()
    return out


def extract_frame(path: Path, t: float) -> np.ndarray | None:
    info_cmd = [FFMPEG, "-hide_banner", "-v", "error", "-nostdin", "-ss", f"{max(0.0, t):.3f}", "-i", str(path),
                "-frames:v", "1", "-f", "image2pipe", "-vcodec", "png", "-"]
    proc = popen(info_cmd, stdout=-1, stderr=-3)
    data = proc.stdout.read()
    proc.stdout.close()
    proc.wait()
    if not data:
        return None
    return cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)


class _PanelSnapshots:
    """OCR the quest panel only around star-counter changes, using a short ring buffer."""

    def __init__(self, engine: OcrEngine | None, buffer_s: float, fps: float):
        self.engine = engine
        self.buffer: deque[tuple[float, np.ndarray]] = deque(maxlen=max(2, int(buffer_s * fps) + 1))
        self.pending: list[float] = []
        self.texts: dict[float, list[str]] = {}
        self.calls = 0

    def _ocr(self, t: float, img: np.ndarray) -> None:
        if self.engine is None or t in self.texts:
            return
        self.texts[t] = [text for text, conf in self.engine.read_lines(img) if conf >= 0.5]
        self.calls += 1

    def push(self, t: float, img: np.ndarray) -> None:
        self.buffer.append((t, img.copy()))
        for due in [d for d in self.pending if t >= d]:
            self._ocr(t, img)
            self.pending.remove(due)

    def trigger(self, t: float) -> None:
        for back in (1.0, 3.0):
            target = [(bt, img) for bt, img in self.buffer if bt <= t - back]
            if target:
                self._ocr(*target[-1])
        self.pending += [t + 1.5, t + 3.0]

    def as_list(self) -> list[tuple[float, list[str]]]:
        return sorted(self.texts.items())


def analyze_source(src: Path, profile: Profile, out_dir: Path, *, sample_fps: float | None = None,
                   threads: int | None = None, vision: bool = False, vision_budget: int = 0,
                   progress=None) -> dict:
    started = time.monotonic()
    src = Path(src)
    out_dir = Path(out_dir)
    guard = SourceGuard(src)
    guard.check_output(out_dir / "analysis.json")
    out_dir.mkdir(parents=True, exist_ok=True)
    info: MediaInfo = probe(src)
    fps = sample_fps or profile.sample_fps
    threads = threads or default_threads()
    warnings: list[str] = []

    calibrated = profile.calibrated
    if not calibrated:
        warnings.append("Not calibrated: no star_counter region saved for this recording, so star and quest "
                        "counts are disabled. Open the dashboard's Calibrate page to mark the regions.")
    rois = dict(profile.rois)
    layout = MosaicLayout.from_rois(info, rois)
    engine = OcrEngine(threads=threads) if calibrated else None
    star_reader = GatedReader(engine) if calibrated else None
    panel = _PanelSnapshots(engine if "quest_panel" in rois else None, buffer_s=4.0, fps=fps)

    readings: list[Reading] = []
    raw_readings: list[dict] = []
    motion, panel_change, banner_change = [], [], []
    prev_overview = None
    panel_history: deque[np.ndarray] = deque(maxlen=max(2, int(round(fps)) + 1))
    banner_bg = None
    last_value = None
    n = 0
    for sample in iter_samples(src, layout, fps=fps, threads=threads):
        n += 1
        t = sample.t
        ov = _gray_thumb(sample.regions["overview"], 160)
        motion.append((t, float(np.abs(ov - prev_overview).mean()) if prev_overview is not None else 0.0))
        prev_overview = ov

        if star_reader is not None:
            res = star_reader.read(t, sample.regions["star_counter"])
            parsed = parse_star_text(res.text, profile.star_pattern) if res.conf >= profile.ocr_min_conf else None
            cur, total = parsed if parsed else (None, None)
            readings.append(Reading(t, cur, total, res.conf))
            raw_readings.append({"t": t, "text": res.text, "cur": cur, "total": total,
                                 "conf": round(res.conf, 3), "reused": res.reused})
            if parsed and last_value is not None and parsed != last_value:
                panel.trigger(t)
            if parsed:
                last_value = parsed

        if "quest_panel" in sample.regions:
            thumb = _gray_thumb(sample.regions["quest_panel"])
            ref = panel_history[0] if panel_history else thumb
            panel_change.append((t, float(np.abs(thumb - ref).mean())))
            panel_history.append(thumb)
            panel.push(t, sample.regions["quest_panel"])

        if "completion_banner" in sample.regions:
            thumb = _gray_thumb(sample.regions["completion_banner"])
            banner_bg = thumb if banner_bg is None else banner_bg
            score = float(np.abs(thumb - banner_bg).mean())
            banner_change.append((t, score))
            banner_bg = 0.95 * banner_bg + 0.05 * thumb

        if progress and n % 20 == 0:
            progress(t, info.duration)

    guard.verify()
    audio = audio_rms(src) if info.has_audio else []

    timeline = detect_star_events(readings, min_conf=profile.ocr_min_conf, confirm_samples=profile.confirm_samples,
                                  max_gain=profile.max_gain, revert_window=profile.revert_window)
    panel_peaks = find_peaks(panel_change, k=6.0, min_gap=2.0) if panel_change else []
    banner_peaks = find_peaks(banner_change, k=6.0, min_gap=2.0) if banner_change else []
    quests = classify_quests(timeline.events, panel_peaks, banner_peaks, panel.as_list()) if calibrated else []
    # rank-up banners/panel resets are explained by the rank-up, not unexplained visual changes
    rank_times = [e.t for e in timeline.events if e.kind == "rank_up"]
    quests = [q for q in quests if not (q.status == "visual_only" and any(-3.0 <= rt - q.t <= 3.0 for rt in rank_times))]
    for i, q in enumerate(quests, start=1):
        q.id = f"q{i}"

    events = []
    for q in quests:
        if q.status in ("confirmed", "probable"):
            weight = (6.0 if q.status == "confirmed" else 4.0) + math.log1p(q.stars)
            events.append({"id": q.id, "t": q.t, "weight": weight, "kind": f"quest ({q.status})"})
    for e in timeline.events:
        if e.kind == "rank_up":
            events.append({"id": e.id, "t": e.t, "weight": 9.0, "kind": "rank up"})
    highlights = score_windows(motion, audio, events, info.duration)

    review_items = [e for e in timeline.events if e.kind == "review"]
    for e in review_items:
        warnings.append(f"Star counter {e.from_cur}->{e.to_cur} at {e.t:.1f}s not counted: {e.reason}.")

    evidence = _write_evidence(src, info, profile, out_dir, quests, timeline.events)
    if vision:
        from .vision import verify_events
        vision_report = verify_events(out_dir, evidence, timeline.events, budget=vision_budget)
    else:
        vision_report = {"enabled": False}
    guard.verify()

    result = {
        "version": ANALYSIS_VERSION,
        "source": {**asdict(info), "sha256": guard.fingerprint.sha256},
        "profile": profile_to_dict(profile),
        "calibrated": calibrated,
        "sample_fps": fps,
        "stats": {"samples": n, "ocr_calls_star": star_reader.calls if star_reader else 0,
                  "ocr_calls_panel": panel.calls, "seconds": round(time.monotonic() - started, 2),
                  "threads": threads},
        "star_readings": raw_readings,
        "star_stable": [asdict(s) for s in timeline.stable],
        "star_events": [e.to_dict() for e in timeline.events],
        "quests": [q.to_dict() for q in quests],
        "panel_text": [{"t": t, "lines": lines} for t, lines in panel.as_list()],
        "highlights": [w.to_dict() for w in highlights],
        "activity": {"motion": motion, "audio": audio, "panel": panel_change, "banner": banner_change},
        "totals": {
            "stars_verified": timeline.verified_gain if calibrated else None,
            "quests_confirmed": sum(q.status == "confirmed" for q in quests),
            "quests_probable": sum(q.status == "probable" for q in quests),
            "rank_ups": len(rank_times),
            "review_items": len(review_items),
        },
        "evidence": evidence,
        "vision": vision_report,
        "warnings": warnings,
    }
    (out_dir / "analysis.json").write_text(json.dumps(result, indent=1), encoding="utf-8")
    return result


def _write_evidence(src: Path, info: MediaInfo, profile: Profile, out_dir: Path, quests, star_events) -> dict:
    """Before/after crops of the counter and a full frame at each event, for human review."""
    ev_dir = out_dir / "evidence"
    ev_dir.mkdir(exist_ok=True)
    star_box = profile.rois["star_counter"].to_pixels(info.width, info.height) if profile.calibrated else None
    evidence: dict[str, dict] = {}

    def save(name: str, img: np.ndarray, width: int | None = None) -> str:
        if width and img.shape[1] != width:
            img = cv2.resize(img, (width, int(img.shape[0] * width / img.shape[1])), interpolation=cv2.INTER_AREA)
        cv2.imwrite(str(ev_dir / name), img, [cv2.IMWRITE_JPEG_QUALITY, 85])
        return f"evidence/{name}"

    def crop(img, box):
        x, y, w, h = box
        return cv2.resize(img[y:y + h, x:x + w], None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)

    by_id = {e.id: e for e in star_events}
    items = [(q.id, q.t, by_id.get(q.star_event)) for q in quests if q.status != "visual_only"]
    items += [(e.id, e.t, e) for e in star_events if e.kind in ("rank_up", "review")]
    for item_id, t, star_event in items:
        entry = {}
        frame = extract_frame(src, t)
        if frame is not None:
            entry["frame"] = save(f"{item_id}_frame.jpg", frame, 640)
        if star_event is not None and star_box is not None:
            before = extract_frame(src, star_event.t_prev)
            after = extract_frame(src, star_event.t + 0.5)
            if before is not None:
                entry["star_before"] = save(f"{item_id}_star_before.jpg", crop(before, star_box))
            if after is not None:
                entry["star_after"] = save(f"{item_id}_star_after.jpg", crop(after, star_box))
        evidence[item_id] = entry
    return evidence


def load_analysis(out_dir: Path) -> dict:
    return json.loads((Path(out_dir) / "analysis.json").read_text(encoding="utf-8"))
