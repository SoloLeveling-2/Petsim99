"""On-screen text reading (RapidOCR, fully offline) with change gating."""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass

import cv2
import numpy as np

_DIGIT_LOOKALIKES = str.maketrans({"O": "0", "o": "0", "D": "0", "Q": "0", "I": "1", "l": "1", "|": "1",
                                   "i": "1", "S": "5", "s": "5", "B": "8", "Z": "2", "z": "2"})


def _normalize(text: str) -> str:
    out = []
    for token in text.split():
        if any(c.isdigit() for c in token):
            token = token.translate(_DIGIT_LOOKALIKES)
            token = re.sub(r"(?<=\d)[,.](?=\d{3}\b)", "", token)
        out.append(token)
    return " ".join(out)


def parse_star_text(text: str, pattern: str) -> tuple[int, int | None] | None:
    if not text:
        return None
    match = re.search(pattern, _normalize(text))
    if not match:
        return None
    groups = match.groupdict()
    total = groups.get("total")
    return int(groups["cur"]), (int(total) if total is not None else None)


class OcrEngine:
    """Thin wrapper around RapidOCR. Models ship inside the wheel; no network is used."""

    def __init__(self):
        from rapidocr import RapidOCR

        logging.getLogger("RapidOCR").setLevel(logging.WARNING)
        self._engine = RapidOCR()

    @staticmethod
    def _prep(img: np.ndarray) -> np.ndarray:
        if img.shape[0] < 40:
            scale = 40 / img.shape[0]
            img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
        return np.ascontiguousarray(img)

    def _boxes(self, img: np.ndarray) -> list[tuple[float, float, str, float]]:
        result = self._engine(self._prep(img))
        if result is None or not getattr(result, "txts", None):
            return []
        boxes = []
        for box, text, score in zip(result.boxes, result.txts, result.scores):
            pts = np.asarray(box)
            boxes.append((float(pts[:, 1].mean()), float(pts[:, 0].min()), text, float(score)))
        return boxes

    def read_line(self, img: np.ndarray) -> tuple[str, float]:
        boxes = sorted(self._boxes(img), key=lambda b: b[1])
        if not boxes:
            result = self._engine(self._prep(img), use_det=False, use_cls=False, use_rec=True)
            if result is None or not getattr(result, "txts", None):
                return "", 0.0
            return " ".join(result.txts), float(min(result.scores))
        return " ".join(b[2] for b in boxes), min(b[3] for b in boxes)

    def read_lines(self, img: np.ndarray) -> list[tuple[str, float]]:
        boxes = sorted(self._boxes(img), key=lambda b: (round(b[0] / 12), b[1]))
        return [(b[2], b[3]) for b in boxes]


@dataclass
class OcrResult:
    t: float
    text: str
    conf: float
    reused: bool


class GatedReader:
    """Runs OCR only when the region visibly changed (or after `keepalive_s`)."""

    def __init__(self, engine, diff_threshold: float = 6.0, keepalive_s: float = 8.0):
        self.engine = engine
        self.diff_threshold = diff_threshold
        self.keepalive_s = keepalive_s
        self._last_thumb: np.ndarray | None = None
        self._last: OcrResult | None = None
        self.calls = 0

    @staticmethod
    def _thumb(img: np.ndarray) -> np.ndarray:
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if img.ndim == 3 else img
        h = max(4, int(round(gray.shape[0] * 96 / max(1, gray.shape[1]))))
        return cv2.resize(gray, (96, h), interpolation=cv2.INTER_AREA).astype(np.int16)

    def read(self, t: float, img: np.ndarray) -> OcrResult:
        thumb = self._thumb(img)
        if self._last is not None and self._last_thumb is not None and thumb.shape == self._last_thumb.shape:
            diff = float(np.abs(thumb - self._last_thumb).mean())
            if diff < self.diff_threshold and t - self._last.t < self.keepalive_s:
                return OcrResult(t, self._last.text, self._last.conf, True)
        text, conf = self.engine.read_line(img)
        self.calls += 1
        self._last_thumb = thumb
        self._last = OcrResult(t, text, conf, False)
        return self._last
