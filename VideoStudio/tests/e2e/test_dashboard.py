"""Playwright end-to-end tests of the review dashboard (real browser, real server)."""
import json
import threading
import time

import pytest
from playwright.sync_api import expect, sync_playwright

from tests.conftest import ARTIFACTS, make_clip
from tests.review_helpers import make_render

RID = "vyhub-run-recap-20261012-120000"
SHOTS = ARTIFACTS / "dashboard_screenshots"


@pytest.fixture
def server(tmp_path):
    from studio.review.server import make_server
    from studio.workspace import Workspace

    make_render(tmp_path)
    ws = Workspace(tmp_path)
    clip = make_clip(tmp_path / "recordings" / "VyHub Auto Ranking.mp4", 4, size="1280x720", audio=False)
    source = ws.register(clip)
    httpd, token = make_server(tmp_path, port=0)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    yield {"url": f"http://127.0.0.1:{httpd.server_address[1]}", "ws": ws, "source": source, "root": tmp_path}
    httpd.shutdown()


def wait_until(page, expression, timeout=10.0):
    """Poll via page.evaluate: Playwright's in-page polling needs eval, which the dashboard CSP forbids."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if page.evaluate(expression):
            return
        time.sleep(0.1)
    raise AssertionError(f"timed out waiting for {expression}")


@pytest.fixture
def ui():
    SHOTS.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch()
        context = browser.new_context(viewport={"width": 1400, "height": 1000})
        pg = context.new_page()
        errors = []
        pg.on("pageerror", lambda e: errors.append(str(e)))
        yield pg
        browser.close()
        assert not errors, errors


def test_watch_inspect_approve_authorize(server, ui):
    ui.goto(server["url"])
    card = ui.get_by_test_id(f"render-card-{RID}")
    expect(card).to_contain_text("Full-run recap")
    expect(card.get_by_test_id("status")).to_have_text("pending review")
    ui.screenshot(path=str(SHOTS / "01_list.png"), full_page=True)
    card.click()

    # watch: the video element loads and is seekable
    video = ui.get_by_test_id("player")
    expect(video).to_be_visible()
    expect(ui.get_by_test_id("download-final")).to_have_attribute("href", f"/media/{RID}/final.mp4")
    h264 = ui.evaluate("document.createElement('video').canPlayType('video/mp4; codecs=\"avc1.640028, mp4a.40.2\"')")
    if h264:
        expect(video).to_have_attribute("src", f"/media/{RID}/final.mp4")
    else:  # Playwright's open-source Chromium: no H.264 decoder, so a labelled review preview is used
        expect(ui.get_by_test_id("preview-note")).to_be_visible()
        expect(video).to_have_attribute("src", f"/media/{RID}/preview.webm")
    wait_until(ui, "document.querySelector('[data-testid=player]').readyState >= 1")
    assert abs(ui.evaluate("document.querySelector('[data-testid=player]').duration") - 3.0) < 0.2

    # inspect: every post detail for both platforms, plus facts, music and technical info
    yt = ui.get_by_test_id("post-youtube_shorts")
    expect(yt.get_by_test_id("post-title")).to_have_text("+36 Rank Stars in 11 Minutes with Auto Ranking | Pet Sim 99")
    expect(yt).to_contain_text("paid in Pet Simulator 99 gems")
    expect(yt).to_contain_text("#PetSimulator99")
    expect(yt).to_contain_text("Paid promotion")
    tt = ui.get_by_test_id("post-tiktok")
    expect(tt).to_contain_text("+36 rank stars in 11 minutes")
    expect(tt).to_contain_text("Content disclosure")
    expect(ui.get_by_test_id("facts")).to_contain_text("36")
    expect(ui.get_by_test_id("events")).to_contain_text("Hatch 50 Eggs")
    expect(ui.get_by_test_id("music")).to_contain_text("Rank Rush (original)")
    expect(ui.get_by_test_id("technical")).to_contain_text("1080 × 1920")
    expect(ui.get_by_test_id("no-upload-notice")).to_be_visible()

    # authorization is impossible before approval
    expect(ui.get_by_test_id("authorize-tiktok")).to_be_disabled()
    ui.get_by_test_id("decision-notes").fill("Counter and disclosure look right.")
    ui.get_by_test_id("approve").click()
    expect(ui.get_by_test_id("detail-status")).to_have_text("approved")

    panel = ui.get_by_test_id("auth-panel-tiktok")
    expect(ui.get_by_test_id("authorize-tiktok")).to_be_disabled()  # still needs every confirmation
    for box in ("watched_full_video", "checked_post_text", "checked_disclosure", "checked_music_license"):
        panel.get_by_test_id(f"confirm-{box}").check()
    panel.get_by_test_id("confirm-text").fill("AUTHORIZE")
    expect(ui.get_by_test_id("authorize-tiktok")).to_be_enabled()
    ui.screenshot(path=str(SHOTS / "02_detail_ready_to_authorize.png"), full_page=True)
    ui.get_by_test_id("authorize-tiktok").click()
    expect(panel.get_by_test_id("auth-state")).to_contain_text("Authorized (not published)")
    expect(ui.get_by_test_id("auth-panel-youtube_shorts").get_by_test_id("auth-state")).to_contain_text("Not authorized")
    ui.screenshot(path=str(SHOTS / "03_authorized_tiktok.png"), full_page=True)

    review = json.loads((server["root"] / "renders" / RID / "review.json").read_text())
    kinds = [h["type"] for h in review["history"]]
    assert kinds == ["decision", "authorization"]
    assert review["history"][1]["platform"] == "tiktok"
    assert review["history"][1]["content"]["video_sha256"] == json.loads(
        (server["root"] / "renders" / RID / "manifest.json").read_text())["video"]["sha256"]

    ui.get_by_test_id("back").click()
    expect(ui.get_by_test_id(f"render-card-{RID}").get_by_test_id("status")).to_have_text("approved")
    expect(ui.get_by_test_id(f"render-card-{RID}")).to_contain_text("TikTok")


def test_reject_flow(server, ui):
    ui.goto(f"{server['url']}/#/render/{RID}")
    ui.get_by_test_id("decision-notes").fill("Hook text too small")
    ui.get_by_test_id("reject").click()
    expect(ui.get_by_test_id("detail-status")).to_have_text("rejected")
    expect(ui.get_by_test_id("history")).to_contain_text("Hook text too small")
    panel = ui.get_by_test_id("auth-panel-youtube_shorts")
    for box in ("watched_full_video", "checked_post_text", "checked_disclosure", "checked_music_license"):
        panel.get_by_test_id(f"confirm-{box}").check()
    panel.get_by_test_id("confirm-text").fill("AUTHORIZE")
    expect(ui.get_by_test_id("authorize-youtube_shorts")).to_be_disabled()


def test_stale_after_change_shown(server, ui):
    from studio.review.store import ReviewStore

    ReviewStore(server["root"]).decide(RID, "approve", "")
    manifest_path = server["root"] / "renders" / RID / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["metadata"]["tiktok"]["caption"] += " edited"
    manifest_path.write_text(json.dumps(manifest))
    ui.goto(f"{server['url']}/#/render/{RID}")
    expect(ui.get_by_test_id("detail-status")).to_have_text("stale")
    expect(ui.get_by_test_id("stale-warning")).to_be_visible()


def test_calibration_save(server, ui):
    sid = server["source"]["id"]
    ui.goto(f"{server['url']}/#/calibrate/{sid}")
    canvas = ui.get_by_test_id("calib-canvas")
    expect(canvas).to_be_visible()
    wait_until(ui, "document.querySelector('[data-testid=calib-image]').naturalWidth > 0")
    ui.get_by_test_id("roi-star_counter").click()
    box = canvas.bounding_box()
    ui.mouse.move(box["x"] + box["width"] * 0.10, box["y"] + box["height"] * 0.20)
    ui.mouse.down()
    ui.mouse.move(box["x"] + box["width"] * 0.30, box["y"] + box["height"] * 0.30, steps=5)
    ui.mouse.up()
    ui.get_by_test_id("save-calibration").click()
    expect(ui.get_by_test_id("calib-message")).to_contain_text("Saved")
    ui.screenshot(path=str(SHOTS / "04_calibration.png"), full_page=True)
    roi = server["ws"].profile(sid).rois["star_counter"]
    assert abs(roi.x - 0.10) < 0.02 and abs(roi.y - 0.20) < 0.02
    assert abs(roi.w - 0.20) < 0.02 and abs(roi.h - 0.10) < 0.02
