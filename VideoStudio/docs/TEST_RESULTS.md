# Test results — 2026-10-12

Environment: Claude Code cloud container, Linux, 4 vCPU, 15 GiB RAM, **no GPU**, FFmpeg 6.1.1,
Python 3.13, Node 22, Remotion 4.0.534, Playwright 1.56 (Chromium 141).

**Your real recording was not available here** (see TOOL_AUDIT.md), so every detection result
below comes from a synthetic Pet Simulator 99-style recording with exact ground truth
(`tests/fixtures/synth.py`): a 72 s, 1280×720 clip with a star counter, a three-row quest panel
whose progress text ticks constantly, completion banners, a rank-up reset, a popup covering the
counter, and a large panel change that is *not* a completion.

## Automated tests: 83 passed, 0 failed (5 min 2 s)

| Area | Tests | What is proven |
|---|---|---|
| Foundations | 12 | encoder priority and real probe, source guard (append, same-size rewrite, writes next to original refused), paths with spaces/unicode, recording finder |
| Sampler + OCR | 8 | one-decode ROI mosaic matches the source pixels; OCR reads `12/40` and all quest names offline; misread icon no longer vetoes a confident number; single-digit change triggers a read; small-crop OCR < 250 ms |
| Detectors | 15 | gains, flicker, revert, implausible jump, rank-up, drop, occlusion, low confidence, counters without totals, quest corroboration and naming, highlight scoring |
| Analysis vs ground truth | 3 | see table below; uncalibrated runs count nothing |
| Music + metadata | 12 | original track 90 s, peak ≤ −1 dBFS, deterministic; unlicensed/platform-restricted tracks refused; disclosure in every caption; title ≤ 100; blocked terms; no numbers without verified stars |
| Planner | 10 | target lengths, segments inside the source, chronological body, counter monotonic and equal to running verified totals at the visible moment, hook hides counter, disclosure card then badge, layout inside safe area |
| Renderer | 4 | 1080×1920, 30 fps, H.264 yuv420p, AAC 48 kHz, duration ±0.15 s, −14 ±1.5 LUFS, file hash, source unchanged; Remotion overlay present; GPU-encoder failure falls back to libx264; audio/video read from separate inputs |
| Vision (fake client) | 4 | off without budget, budget cap, structured request on `claude-opus-5-5` with fallbacks, refusal handled |
| Review store + server | 7 | authorization requires approval + 4 confirmations + `AUTHORIZE`; per platform; stale after any video/text change; revoke; package only when authorized; token/origin/path-traversal protection; byte ranges |
| Dashboard (Playwright) | 4 | list → watch → inspect every post detail → approve → authorize TikTok only; reject flow; stale warning; calibration drag-and-save |
| CLI | 4 | audit, find, uncalibrated `run` stops (exit 2), full `run` on the fixture, `package` refused without authorization |

## Detection vs ground truth (synthetic recording)

| Event | Truth (counter visible) | Detected | Delta |
|---|---|---|---|
| Break 300 Coins | 6.4 s, 12→15 | 6.5 s, +3 | exact |
| Hatch 50 Eggs | 13.9 s, 15→19 | 14.0 s, +4 | exact |
| Collect 5 Diamonds | 30.9 s, 19→24 | 31.0 s, +5 | exact |
| Earn 1M Coins | 36.4 s, 24→30 | 36.5 s, +6 | exact |
| Use 3 Potions | 42.4 s, 30→40 | 42.5 s, +10 | exact |
| Rank up | 48.8 s, 40/40→0/60 | 49.0 s, rank_up (not counted) | — |
| Break 500 Coins | 55.4 s, 0→3 | 55.5 s, +3 | exact |
| Hatch 100 Eggs | 63.4 s, 3→8 | 63.5 s, +5 | exact |

- **Verified total 36 = truth 36.** All 7 completions `confirmed` and named exactly.
- Progress-only flash at 21.0 s → `visual_only` (not counted). Popup over the counter at
  26.0–27.2 s → no phantom gain or drop.
- Change-gated OCR: 13 counter reads for 144 samples; 31 quest-panel reads.

## Rendered edits (Remotion overlay, libx264 on CPU)

| Edit | Length | Size | Loudness | Events shown | Render time |
|---|---|---|---|---|---|
| Full-run recap | 44.5 s | 12.4 MB | −13.7 LUFS | 7 quests + rank up | 187 s |
| Best moment | 20.0 s | 5.9 MB | −13.7 LUFS | 2 quests + rank up | 95 s |

Visual check of the final frames (`evidence/recap_contact_sheet.jpg`): the counter climbs
+0 → +3 → +7 → +12 → +18 → +28 → +31 → +36 in step with the real in-game inset (15/40 … 40/40 →
0/60 → 8/60), the clock advances 00:03 → 01:03, the disclosure is on screen in every frame, and
the outro shows "WHOLE RUN TOTAL +36 · 7 QUESTS · 1 RANK UP". The game audio is still in the
final mix (spectrogram shows the 110 Hz bed and completion chimes under the music).

## Resource use and the two optimisations made

| Measurement | Before | After |
|---|---|---|
| Analysis of the 72 s clip | 55.0 s (text detector upscaled a 220×56 crop to ~2900×736) | **18.7–20.1 s** (detector capped at native size: 1827 → 47 ms per read) |
| FFmpeg composite peak RAM, 10 segments + overlay | 4231 MB (audio crossfade pulled every segment's video early) | **1618 MB** (separate audio/video inputs) |
| Whole `run` (analyse + 2 renders) peak RAM, all processes | 4407 MB | **1830 MB** |
| Whole `run` wall / CPU time | 336 s / 469 s | **303 s / 451 s** |

Remotion's share: ~93 s and 1.3 GB peak for the 44.5 s recap at concurrency 2 (200 MB of
temporary PNGs, deleted after compositing). On a GPU encoder the FFmpeg part gets faster; the
analysis of an 11-minute 1080p60 recording is expected to take a few minutes on 4 cores
(estimate, not measured: decode cost scales with length and resolution).

## Not functional yet / not verified — please read

1. **Your recording has not been processed.** It is on your computer; this cloud session cannot
   reach it. Real PS99 HUD fonts, animations and the exact star-counter format have not been
   seen by the detector. First real run: calibrate, then check the dashboard's events table
   (before/after crops for each star change) before trusting the counts. If the counter shows
   only a number (no `/required`), set `star_pattern` to `(?P<cur>\d{1,6})` in that recording's
   `profile.json`.
2. **Hardware acceleration is unverified.** The NVENC / Quick Sync / AMF / VideoToolbox / VAAPI paths
   are probed with a real test encode on your machine, but none could open here (no GPU). Only
   the automatic fallback to libx264 was exercised.
3. **vidIQ, Metricool and Descript are not connected or authenticated.** Their servers are blocked
   from this environment and no sign-in has happened. The studio only reads a `research/vidiq.json`
   file if you provide one; titles currently say "not vidIQ-validated".
4. **Publishing is deliberately not implemented.** The dashboard records approvals and
   per-platform authorizations; `package` prepares a folder; you upload. No scheduling exists.
5. **Claude vision double-check never called the real API** (no key here, and it costs money).
   Tested only with a fake client.
6. **Windows was not tested directly.** The code avoids shell strings and POSIX-only calls, but
   every test ran on Linux.
7. **Dashboard playback of the H.264 final file** was tested through the VP9 review-preview
   fallback (Playwright's Chromium has no H.264 decoder). Chrome, Edge, Firefox and Safari play
   `final.mp4` directly; that path was not exercised here.
8. **Music has not been listened to by a person.** Structure and loudness were verified
   (spectrogram, −14.7 LUFS), but taste needs your ears. Add licensed tracks to
   `music/library.json` with their license record if you prefer.
9. **The previous event script's name is unknown**, so `blocked_terms` only holds generic terms
   ("event script", "event hub"). Add its exact name.
10. **Remotion's first-run Chrome download** on your computer was not tested (a preinstalled
    Chromium was used here).
11. **Known cosmetic gaps:** both variants currently get the same title template; calibration
    labels can overlap when regions touch.
