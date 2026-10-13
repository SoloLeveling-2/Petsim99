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

    def __init__(self, threads: int | None = None):
        from rapidocr import RapidOCR

        logging.getLogger("RapidOCR").setLevel(logging.WARNING)
        params = {
            "Global.log_level": "warning",
            "Global.use_cls": False,  # HUD text is never rotated
            # The default ("min", 736) upscales a 220x56 counter crop to ~2900x736 before
            # text detection; capping the long side keeps small crops at native size.
            "Det.limit_type": "max",
            "Det.limit_side_len": 960,
        }
        if threads:
            params["EngineConfig.onnxruntime.intra_op_num_threads"] = threads
        self._engine = RapidOCR(params=params)

    @staticmethod
    def _prep(img: np.ndarray) -> np.ndarray:
        if img.shape[0] < 40:
            scale = 40 / img.shape[0]
            img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
        return np.ascontiguousarray(img)

    def _boxes(self, img: np.ndarray) -> list[tuple[float, float, str, float]]:
        # RapidOCR keeps use_det/use_cls/use_rec from the previous call, so after read_line's
        # recognition-only fallback a bare call would skip detection; always ask explicitly.
        result = self._engine(self._prep(img), use_det=True, use_cls=False, use_rec=True)
        if result is None or not getattr(result, "txts", None):
            return []
        boxes = []
        for box, text, score in zip(result.boxes, result.txts, result.scores):
            pts = np.asarray(box)
            boxes.append((float(pts[:, 1].mean()), float(pts[:, 0].min()), text, float(score)))
        return boxes

    def read_line(self, img: np.ndarray) -> tuple[str, float]:
        """Text left-to-right, with the confidence of the boxes that contain digits.

        Icons next to a counter (a star, a gem) are often misread with low confidence;
        that must not veto a confidently read number beside them.
        """
        boxes = sorted(self._boxes(img), key=lambda b: b[1])
        if not boxes:
            result = self._engine(self._prep(img), use_det=False, use_cls=False, use_rec=True)
            if result is None or not getattr(result, "txts", None):
                return "", 0.0
            return " ".join(result.txts), float(min(result.scores))
        numeric = [b[3] for b in boxes if any(c.isdigit() for c in b[2])]
        return " ".join(b[2] for b in boxes), min(numeric) if numeric else max(b[3] for b in boxes)

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
    """Runs OCR only when the region visibly changed (or after `keepalive_s`).

    "Changed" means at least `changed_fraction` of pixels moved by more than
    `pixel_threshold` grey levels: a single digit flip touches ~2% of a counter's pixels
    strongly, while video compression noise stays far below the pixel threshold.
    """

    def __init__(self, engine, pixel_threshold: int = 40, changed_fraction: float = 0.005, keepalive_s: float = 8.0):
        self.engine = engine
        self.pixel_threshold = pixel_threshold
        self.changed_fraction = changed_fraction
        self.keepalive_s = keepalive_s
        self._last_thumb: np.ndarray | None = None
        self._last: OcrResult | None = None
        self.calls = 0

    @staticmethod
    def _thumb(img: np.ndarray) -> np.ndarray:
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if img.ndim == 3 else img
        if gray.shape[1] > 256:
            h = max(4, int(round(gray.shape[0] * 256 / gray.shape[1])))
            gray = cv2.resize(gray, (256, h), interpolation=cv2.INTER_AREA)
        return gray.astype(np.int16)

    def read(self, t: float, img: np.ndarray) -> OcrResult:
        thumb = self._thumb(img)
        if self._last is not None and self._last_thumb is not None and thumb.shape == self._last_thumb.shape:
            changed = float((np.abs(thumb - self._last_thumb) > self.pixel_threshold).mean())
            if changed < self.changed_fraction and t - self._last.t < self.keepalive_s:
                return OcrResult(t, self._last.text, self._last.conf, True)
        text, conf = self.engine.read_line(img)
        self.calls += 1
        self._last_thumb = thumb
        self._last = OcrResult(t, text, conf, False)
        return self._last
