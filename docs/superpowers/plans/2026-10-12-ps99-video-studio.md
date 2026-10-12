# PS99 Video Studio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A local pipeline that turns a PS99 Auto Ranking recording into verified, branded 1080×1920 Shorts/TikTok edits plus a review dashboard that gates publication.

**Architecture:** Python package `VideoStudio/studio` with pure analysis/planning cores, FFmpeg for all media I/O (one decode for analysis, one encode for output), a Remotion project for the animated transparent overlay, and a stdlib localhost dashboard.

**Tech Stack:** Python 3.10+, FFmpeg/FFprobe, OpenCV (headless), RapidOCR + onnxruntime, numpy, Remotion 4.0.534 (React/TS), Playwright 1.56 (tests), pytest.

**Spec:** `docs/superpowers/specs/2026-10-12-ps99-video-studio-design.md`

**Execution method:** Native (user asked for implementation in this session).

## Global Constraints

- Output: 1080×1920, 30 fps, H.264 High yuv420p, AAC 48 kHz, `+faststart`, loudness −14 LUFS ±1.5.
- Source files are opened read-only; fingerprint (size, mtime_ns, sha256) must match after every command.
- All outputs live under `VideoStudio/workspace/` (git-ignored).
- Star gain counts only if: ≥3 consecutive samples, same denominator, 1 ≤ delta ≤ `max_gain` (60), not reverted within 5 s.
- Disclosure text (brand `disclosure.short`) must appear on screen and in every platform caption.
- `brand.blocked_terms` must not appear in any generated text.
- No code path uploads, schedules, or edits profiles. Spending services (Claude API, vidIQ, Descript) only behind explicit flags.
- Encoder priority: h264_nvenc → h264_qsv → h264_amf → h264_videotoolbox → h264_vaapi → libx264.

## Review Focus

1. Recording path with spaces/unicode on Windows → every subprocess uses list args, never shell strings (test: `test_paths_with_spaces_and_unicode`).
2. Uncalibrated source (no `star_counter` ROI) → analysis still succeeds, counters disabled, titles carry no numbers (test: `test_uncalibrated_analysis_has_no_counts`, `test_titles_without_verified_stars_have_no_numbers`).
3. Counter briefly occluded by a popup → no phantom drop/gain (fixture includes an occlusion; asserted in `test_fixture_ground_truth`).
4. Video or metadata edited after approval → approval and authorization go stale (test: `test_edit_after_approval_makes_stale`).
5. Cross-site POST to the localhost dashboard → rejected without the session token (test: `test_post_without_token_rejected`).

---

### Task 1: Foundations — config, media, source guard, HW encoder choice, discovery

**Files:** Create `VideoStudio/studio/{__init__,config,media,hwaccel,discover}.py`, `VideoStudio/brand/brand.json`, `VideoStudio/profiles/ps99_default.json`, `VideoStudio/requirements.txt`, `VideoStudio/tests/conftest.py`, `VideoStudio/tests/test_foundations.py`

**Interfaces — Produces:**
- `config.ROI(x, y, w, h)` normalized floats; `config.load_profile(path) -> Profile`, `Profile.rois: dict[str, ROI]`, `Profile.star_pattern: str`, `Profile.sample_fps: float`, `Profile.max_gain: int`
- `config.load_brand(path=None) -> dict`
- `media.probe(path) -> MediaInfo(duration, width, height, fps, has_audio, vcodec, size)`
- `media.sha256_file(path) -> str`; `media.SourceGuard(path)` with `.fingerprint`, `.verify(full: bool=False)` (raises `SourceModifiedError`), `.check_output(path)` (raises `UnsafeOutputError` for the source itself or its folder)
- `media.run(cmd: list[str], log_path: Path|None=None) -> subprocess.CompletedProcess`
- `hwaccel.ENCODER_PRIORITY`, `hwaccel.probe_encoders() -> dict[str,bool]`, `hwaccel.choose_encoder(available, prefer=None) -> EncoderChoice(name, args, pre_filter, hw)`
- `discover.find_recordings(roots, min_s=480, max_s=900) -> list[Candidate(path, duration, size, score, reasons)]`, `discover.default_roots()`

- [ ] Test: `test_choose_encoder_priority` (available nvenc+x264 → nvenc; nothing hw → libx264 with `-crf`), `test_probe_encoders_real` (libx264 True here), `test_source_guard_detects_change`, `test_source_guard_refuses_source_folder_output`, `test_paths_with_spaces_and_unicode`, `test_find_recordings_duration_window` (3 generated clips: 2 s, 9 s, 20 s with window 5–15 s → only the 9 s one).
- [ ] Run → fail; implement; run → pass; commit.

### Task 2: Synthetic ground-truth fixture

**Files:** Create `VideoStudio/tests/fixtures/synth.py`

**Interfaces — Produces:** `make_fixture(out_dir: Path, seconds=72) -> FixtureInfo(path, truth: dict, profile_path)`; truth has `star_gains: [{t, from, to}]`, `rank_ups: [{t}]`, `quest_names: [{t, name}]`, `visual_only: [{t}]`, `occlusions: [{start, end}]`.

Draw with OpenCV at 1280×720 30 fps: moving pets, star counter `★ cur/total` (white text, black outline), 3-line quest panel, green "QUEST COMPLETE!" banner on completions, a rank-up (40/40 → 0/60), a 1.2 s popup covering the counter, a progress-only panel change. Audio: tone blips at completions. Encode via FFmpeg pipe (libx264, AAC).

- [ ] Test: `test_fixture_is_valid_video` (probe duration 72±0.1, 1280×720, has audio).

### Task 3: Sampler + OCR

**Files:** Create `VideoStudio/studio/{sampler,ocr}.py`, test `VideoStudio/tests/test_sampler_ocr.py`

**Interfaces — Produces:** `sampler.MosaicLayout.from_rois(info, rois, overview=(320,180))`, `sampler.iter_samples(path, layout, fps=2.0, threads=None, hwaccel="auto") -> Iterator[Sample(t, regions: dict[str, np.ndarray])]`; `ocr.OcrEngine.read_line(img) -> (str, float)`, `.read_lines(img) -> list[(str, float)]`; `ocr.parse_star_text(text, pattern) -> tuple[int, int|None]|None`; `ocr.GatedReader(engine, diff_threshold=6.0, keepalive_s=8.0).read(t, img) -> OcrResult(t, text, conf, reused)`.

- [ ] Tests: `test_mosaic_regions_match_rois` (fixture frame crop equals mosaic slice within tolerance), `test_parse_star_text` (`"★ 45/90"`→(45,90), `"4S/9O"`→(45,90), `"abc"`→None), `test_gated_reader_skips_unchanged` (same image twice → second `reused=True`).

### Task 4: Pure detectors — stars, quests, highlights

**Files:** Create `VideoStudio/studio/{stars,quests,highlights}.py`, test `VideoStudio/tests/test_detectors.py`

**Interfaces — Produces:**
- `stars.Reading(t, cur, total, conf)`; `stars.detect_star_events(readings, *, min_conf=0.6, confirm_samples=3, max_gain=60, revert_window=5.0) -> StarTimeline(stable, events, verified_gain)`; `StarEvent(id, t, t_prev, kind: "gain"|"rank_up"|"review", from_cur, to_cur, from_total, to_total, delta, counted, reason)`
- `quests.find_peaks(series, k=4.0, min_gap=2.0, min_score=0.0) -> list[Peak(t, score)]`; `quests.diff_quest_names(before, after) -> list[str]`; `quests.classify_quests(star_events, panel_peaks, banner_peaks, panel_text, before=3.0, after=2.0) -> list[QuestEvent(id, t, status, stars, name, evidence)]`
- `highlights.score_windows(motion, audio, events, duration, pre=2.5, post=2.5) -> list[Window(start, end, score, reasons, event_ids)]`

- [ ] Tests: `test_simple_gains`, `test_flicker_ignored`, `test_revert_marks_review`, `test_implausible_jump_review`, `test_rank_up_not_counted`, `test_occlusion_none_readings_do_not_break_runs`, `test_confirmed_vs_probable_vs_visual_only`, `test_quest_name_diff`, `test_windows_prefer_events`.

### Task 5: Analyze orchestration

**Files:** Create `VideoStudio/studio/analyze.py`, test `VideoStudio/tests/test_analyze_fixture.py`

**Interfaces — Consumes:** Tasks 1, 3, 4. **Produces:** `analyze.analyze_source(src, profile, out_dir, *, sample_fps=None, vision=False) -> dict` writing `analysis.json` + `evidence/*.jpg`; keys `source`, `totals{stars_verified, quests_confirmed, quests_probable, rank_ups, review_items}`, `star_events`, `quests`, `highlights`, `activity`, `warnings`, `calibrated`.

- [ ] Tests: `test_fixture_ground_truth` (every truth gain detected within ±0.75 s, verified total equal, rank-up found, visual-only not counted, no event during occlusion), `test_uncalibrated_analysis_has_no_counts`, `test_source_unchanged_after_analysis`.

### Task 6: Music + metadata

**Files:** Create `VideoStudio/studio/{music,metadata}.py`, `VideoStudio/music/library.json`, test `VideoStudio/tests/test_music_metadata.py`

**Interfaces — Produces:** `music.generate_track(path, seconds=90.0, bpm=124, seed=7) -> Path`, `music.load_library(path) -> list[dict]`, `music.validate_track(track) -> list[str]`, `music.pick_track(library, platforms) -> dict`; `metadata.build_metadata(analysis, plan, brand, research=None) -> dict[str, dict]` (keys `youtube_shorts`, `tiktok`), `metadata.validate_metadata(meta, brand) -> list[str]`, `metadata.guard_text(text, blocked_terms)` raises `BlockedTermError`.

- [ ] Tests: `test_generated_track_length_and_level` (90 s ±0.05, peak ≤ −1 dBFS), `test_library_rejects_unlicensed`, `test_disclosure_in_every_platform`, `test_youtube_title_limit_100`, `test_blocked_terms_rejected`, `test_titles_without_verified_stars_have_no_numbers`, `test_numbers_match_analysis`.

### Task 7: Planner

**Files:** Create `VideoStudio/studio/planner.py`, test `VideoStudio/tests/test_planner.py`

**Interfaces — Produces:** `planner.plan_variant(analysis, brand, variant: dict, info: MediaInfo) -> dict` with `segments[{src_start, src_end, speed, out_start, out_end, role}]`, `duration`, `fps`, `xfade`, `overlay{hook, counter[{t,value}], clock[{t,src_t}], quests[{t,label,stars,status}], rank_ups[{t}], disclosure{card_end}, outro{start,total,...}}`.

- [ ] Tests: `test_plan_duration_within_target`, `test_counter_monotonic_and_matches_verified_total`, `test_segments_within_source`, `test_quest_pops_inside_segments`, `test_hook_counter_hidden`.

### Task 8: Renderer (Remotion overlay + ASS fallback + single FFmpeg pass)

**Files:** Create `VideoStudio/studio/render/{__init__,graph,ass,remotion_overlay,run}.py`, `VideoStudio/remotion/*`, test `VideoStudio/tests/test_render.py`

**Interfaces — Produces:** `render.run.render_plan(plan, source, out_dir, *, overlay="auto"|"remotion"|"ass", encoder=None) -> dict` (manifest with `video{path, sha256, ...}`), `render.graph.build_command(...) -> list[str]`.

- [ ] Tests: `test_render_ass_output_spec` (1080×1920, 30 fps, h264, yuv420p, aac, duration = plan ±0.15 s, loudness −14±1.5), `test_render_remotion_overlay_present` (slow), `test_source_unchanged_after_render`.

### Task 9: Review dashboard + CLI

**Files:** Create `VideoStudio/studio/review/{__init__,store,server}.py`, `VideoStudio/studio/review/static/{index.html,app.js,style.css}`, `VideoStudio/studio/{cli,__main__}.py`, tests `VideoStudio/tests/test_review_store.py`, `VideoStudio/tests/e2e/test_dashboard.py`

**Interfaces — Produces:** `store.ReviewStore(root)` with `list()`, `get(id)`, `decide(id, decision, notes)`, `authorize(id, platform, action, confirmations)`, `revoke(id, platform)`; `server.make_server(root, host="127.0.0.1", port=0) -> (httpd, token)`; CLI `python -m studio {audit,find,ingest,analyze,plan,render,run,review,music,verify-source,package}`.

- [ ] Tests: `test_edit_after_approval_makes_stale`, `test_authorize_requires_approval`, `test_post_without_token_rejected`, Playwright `test_watch_inspect_approve_authorize`, `test_reject_flow`, `test_calibration_save`.

### Task 10: End-to-end evidence

- [ ] `python -m studio run <fixture>`; inspect frames visually; write `VideoStudio/docs/TEST_RESULTS.md`; README with Windows quickstart; commit and push.
