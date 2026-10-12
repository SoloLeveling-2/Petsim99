# PS99 Video Studio — design

Date: 2026-10-12 · Status: approved by request ("do not stop at a written plan") · Path: architectural

## Intent (what the user said)

- Turn the ~11 min **VyHub Auto Ranking** Pet Simulator 99 recording (and later ones)
  into professionally edited **1080×1920** YouTube Shorts and TikTok videos.
- Detect **real** quest completions and **observable** rank-star changes; counters must be
  accurate. Find the strongest footage automatically.
- Reusable branded template: hooks, star counter, quest highlights, text animation,
  licensed music, smooth editing, platform-specific titles/captions, and a clear
  disclosure that **Auto Ranking is paid in gems**.
- Local processing, hardware acceleration where available, originals never modified,
  low CPU/RAM.
- A review dashboard: watch, inspect every post detail, approve/reject, authorize
  publication per video and per platform.
- Hard limits: no publishing, scheduling, profile changes or spending without the user's
  approval of the exact content and action. No new promotion of the previous PS99 event
  script.

## Assumptions (not stated by the user)

- The pipeline runs on the user's computer (Windows most likely) with Python ≥ 3.10,
  Node ≥ 18 and FFmpeg on PATH. The cloud session cannot see that disk.
- The game HUD layout is unknown until calibrated, so screen regions (ROIs) are data in a
  per-source profile, set once in the dashboard's calibration page.
- "Observable" means: a number is counted only when it was read on screen and stayed
  stable. Anything ambiguous is surfaced for review, never silently counted.

## Architecture

```
recording ──► ingest (fingerprint, read-only) ──► analyze ──► plan ──► render ──► review dashboard
                                                   │            │         │
                       one FFmpeg decode @2 fps ───┘   EDL+overlay │   Remotion PNG overlay
                       ROI mosaic → OCR / OpenCV        timeline   │   + single FFmpeg pass (HW encode)
```

`VideoStudio/studio/` is a Python package; each module has one job and a pure core
that is unit-tested without video:

| Unit | Job | Depends on |
|---|---|---|
| `media` | ffprobe, hashing, `SourceGuard` (fingerprint before/after, refuses writes to the source) | ffprobe |
| `hwaccel` | probe encoders with a real test encode; pick NVENC → QSV → AMF → VideoToolbox → VAAPI → libx264 | ffmpeg |
| `discover` | find candidate recordings on the local disk by duration/name | ffprobe |
| `sampler` | **single decode**: FFmpeg crops all ROIs + a 320×180 overview into one mosaic frame per sample, streamed as raw BGR (O(1) memory) | ffmpeg |
| `ocr` | RapidOCR backend (offline), digit normalisation, change-gated (only OCR when the ROI changed) | rapidocr |
| `stars` | pure: readings → stable values → `gain` / `rank_up` / `review` events; flicker and revert rejection | — |
| `quests` | pure: star events + panel-change + banner evidence → `confirmed` / `probable` / `visual_only`; quest names from panel text diff | — |
| `highlights` | pure: motion + audio + events → scored windows | — |
| `analyze` | orchestrates the above → `analysis.json` + evidence thumbnails | all above |
| `planner` | pure: analysis + brand + variant → `plan.json` (segments, speed, transitions, overlay timeline) | — |
| `music` | original track generator (owned, no third-party rights) + license manifest validation | numpy |
| `metadata` | platform titles/captions/hashtags, disclosure enforcement, blocked-term guard, length limits | — |
| `render` | Remotion overlay (transparent PNG sequence) or ASS fallback, then one FFmpeg pass: cut, layout, xfade, overlay, music mix, loudnorm, encode | ffmpeg, node |
| `vision` | optional Claude verification of event frames; off by default (costs money) | anthropic |
| `review` | localhost dashboard + approval store bound to content hashes; calibration UI | stdlib |

## Key decisions

1. **Accuracy over recall.** A star gain counts only when the new value is read in ≥3
   consecutive samples (≥1 s), the step is +1…+max_gain with the same denominator, and it
   is not reverted within 5 s. Drops become `rank_up` (denominator/rank changed) or
   `review`. The on-video counter shows only the sum of counted gains.
2. **Quest completion = star gain + visual corroboration.** Panel change or banner
   within −3 s/+2 s → `confirmed`; star gain alone → `probable`; visual change without
   a gain → `visual_only` (never shown as a completion).
3. **Single decode, low resolution.** Analysis decodes once at 2 fps; ROIs are cropped
   in FFmpeg before scaling so OCR sees native pixels. `-threads` is capped, HW decode
   is attempted with automatic software fallback.
4. **Single encode.** The overlay is rendered first (Remotion, transparent PNGs), then
   one FFmpeg graph does trim → layout → crossfades → overlay → audio → encode. No
   intermediate re-encode.
5. **Music must carry a license record.** The default track is generated locally by
   `studio.music` (original, owned). User tracks need source, license and proof fields;
   rendering refuses tracks without them.
6. **Disclosure is enforced, not optional.** On screen (full card for the first 3 s,
   persistent badge after), in every caption/description, and validated before a render
   is marked ready.
7. **Approvals are bound to bytes.** Approval and publication authorization store the
   SHA-256 of the video and of the canonical metadata; any change makes them stale.
   The dashboard has no code path that uploads, schedules or edits profiles.
8. **Blocked promotion terms.** `brand.json → blocked_terms` is checked against every
   generated text; the build fails if one appears.

## Layout (1080×1920, platform safe area x 60–920, y 150–1530)

- y 160–390 hook / segment caption · y 400–1210 gameplay (zoomed crop)
- star counter widget top-left over gameplay, run clock top-right
- y 1230–1430 real quest-panel inset (when calibrated) with completion pulse
- y 1450–1510 disclosure badge · bottom 390 px left to platform UI

## Error handling

- Every FFmpeg/Node call is logged with its command line into the render folder.
- HW encoder failure mid-render → retry once with libx264.
- Missing calibration → analysis still runs (activity highlights), but star/quest
  counters are disabled and titles omit numbers; the dashboard shows why.
- Source fingerprint mismatch after any command → hard error.

## Testing

- Unit: `stars`, `quests`, `highlights`, `planner`, `metadata`, `music`, `hwaccel`
  selection, `review.store`.
- Integration: a synthetic PS99-like video with known ground truth (star gains, a rank
  up, an occluded counter, a progress-only panel change) through analyze → plan → render;
  ffprobe checks of the output; source fingerprint unchanged.
- E2E: Playwright against the dashboard (play video, inspect details, approve/reject,
  authorize, stale-after-change, calibration save, CSRF rejection).

## Out of scope for this iteration

- Uploading/scheduling through Metricool, YouTube or TikTok APIs (blocked and requires
  approval anyway); the dashboard records authorizations and builds manual-upload
  packages only.
- vidIQ/Descript calls (network-blocked here; spend credits).
