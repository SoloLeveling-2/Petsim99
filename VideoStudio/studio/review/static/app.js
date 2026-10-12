'use strict';

const TOKEN = document.querySelector('meta[name="studio-token"]').content;
const PLATFORM_LABEL = {youtube_shorts: 'YouTube Shorts', tiktok: 'TikTok'};
const CONFIRMATIONS = [
  ['watched_full_video', 'I watched the complete final video'],
  ['checked_post_text', 'I checked the exact title / caption / hashtags below'],
  ['checked_disclosure', 'The paid-in-gems disclosure is visible and correct'],
  ['checked_music_license', 'The music license covers this platform'],
];
const ROI_COLORS = {star_counter: '#ffc83d', quest_panel: '#3ddc97', completion_banner: '#7c5cff', rank_label: '#4fd1ff'};
const ROI_LABEL = {star_counter: 'Star counter', quest_panel: 'Quest panel', completion_banner: 'Completion banner', rank_label: 'Rank label'};

// --- tiny DOM helper (textContent only: no HTML injection) ---------------------------
function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (value === undefined || value === null || value === false) continue;
    if (key === 'class') el.className = value;
    else if (key === 'text') el.textContent = value;
    else if (key === 'testid') el.dataset.testid = value;
    else if (key === 'on') for (const [ev, fn] of Object.entries(value)) el.addEventListener(ev, fn);
    else if (key in el && typeof value !== 'string') el[key] = value;
    else el.setAttribute(key, value);
  }
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

async function api(path, body) {
  const opts = body === undefined ? {} : {
    method: 'POST',
    headers: {'Content-Type': 'application/json', 'X-Studio-Token': TOKEN},
    body: JSON.stringify(body),
  };
  const res = await fetch(path, opts);
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || res.statusText);
  return data;
}

const statusText = (s) => s.replace(/_/g, ' ');
const mmss = (t) => `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(Math.floor(t % 60)).padStart(2, '0')}`;
const app = () => document.getElementById('app');
const media = (id, file) => `/media/${encodeURIComponent(id)}/${file.split('/').map(encodeURIComponent).join('/')}`;

// --- list ---------------------------------------------------------------------------
async function renderList() {
  const items = await api('/api/renders');
  const root = app();
  root.replaceChildren(h('h1', {text: 'Finished edits'}), h('p', {class: 'muted',
    text: 'Watch each edit, check every detail, then approve or reject it. Publication is authorized per platform, one video at a time.'}));
  if (!items.length) {
    root.append(h('div', {class: 'empty', text: 'No renders yet. Run: python -m studio run "<your recording>"'}));
    return;
  }
  root.append(h('div', {class: 'grid'}, items.map((it) =>
    h('article', {class: 'card', testid: `render-card-${it.id}`, on: {click: () => { location.hash = `#/render/${it.id}`; }}},
      h('img', {src: media(it.id, it.cover || 'cover.jpg'), alt: `Cover of ${it.label}`, loading: 'lazy'}),
      h('div', {class: 'body'},
        h('span', {class: `chip ${it.status}`, testid: 'status', text: statusText(it.status)}),
        it.authorized.map((p) => h('span', {class: 'chip platform', text: `${PLATFORM_LABEL[p] || p} authorized`})),
        h('div', {class: 'title', text: it.title || it.label}),
        h('div', {class: 'meta', text: `${it.label} · ${it.duration.toFixed(1)} s · ${it.created_at || ''}`}))))));
}

// --- detail -------------------------------------------------------------------------
function kv(pairs) {
  return h('dl', {class: 'kv'}, pairs.filter(([, v]) => v !== undefined && v !== null && v !== '')
    .map(([k, v]) => [h('dt', {text: k}), h('dd', {text: String(v)})]));
}

function postPanel(platform, post) {
  const isYT = platform === 'youtube_shorts';
  return h('section', {class: 'panel', testid: `post-${platform}`},
    h('h2', {text: `${PLATFORM_LABEL[platform] || platform} post`}),
    isYT ? h('div', {class: 'post-title', testid: 'post-title', text: post.title}) : null,
    isYT ? h('div', {class: 'muted', text: `${post.title.length}/100 characters`}) : null,
    h('h3', {text: isYT ? 'Description' : 'Caption'}),
    h('pre', {class: 'text', testid: isYT ? 'post-description' : 'post-caption', text: isYT ? post.description : post.caption}),
    h('h3', {text: 'Hashtags'}), h('div', {class: 'tags'}, post.hashtags.map((t) => h('span', {class: 'chip', text: t}))),
    isYT ? [h('h3', {text: 'Tags'}), h('div', {class: 'tags'}, post.tags.map((t) => h('span', {class: 'chip', text: t})))] : null,
    h('h3', {text: 'Disclosure'}),
    kv([['In caption', post.disclosure], ['On screen', post.on_screen_disclosure]]),
    h('h3', {text: 'Settings you choose on the platform'}),
    h('ul', {class: 'checklist'}, post.platform_settings.map((s) => h('li', {text: s}))),
    h('div', {class: 'muted', text: `Keyword research: ${post.research}`}));
}

function authPanel(detail, platform, rerender) {
  const auth = detail.authorizations[platform];
  const approved = detail.status === 'approved';
  let stateText = 'Not authorized';
  let stateClass = '';
  if (auth && auth.valid) {
    stateText = `Authorized (not published) · ${auth.at}${auth.scheduled_for ? ` · planned for ${auth.scheduled_for}` : ''}`;
    stateClass = 'valid';
  } else if (auth) {
    stateText = auth.revoked_at ? 'Authorization revoked' : 'Authorization no longer valid (video or post changed, or re-reviewed)';
    stateClass = 'invalid';
  }
  const boxes = CONFIRMATIONS.map(([key, label]) => h('input', {type: 'checkbox', testid: `confirm-${key}`, id: `${platform}-${key}`}));
  const phrase = h('input', {type: 'text', testid: 'confirm-text', placeholder: 'Type AUTHORIZE', autocomplete: 'off'});
  const when = h('input', {type: 'datetime-local', testid: 'scheduled-for'});
  const error = h('div', {class: 'error'});
  const button = h('button', {class: 'btn go', testid: `authorize-${platform}`, text: `Authorize ${PLATFORM_LABEL[platform] || platform}`});
  const refresh = () => {
    button.disabled = !(approved && boxes.every((b) => b.checked) && phrase.value.trim() === 'AUTHORIZE');
  };
  [...boxes, phrase].forEach((el) => el.addEventListener('input', refresh));
  boxes.forEach((el) => el.addEventListener('change', refresh));
  refresh();
  button.addEventListener('click', async () => {
    error.textContent = '';
    try {
      const confirmations = Object.fromEntries(CONFIRMATIONS.map(([key], i) => [key, boxes[i].checked]));
      rerender(await api(`/api/renders/${detail.id}/authorize`, {platform, confirmations, confirm_text: phrase.value,
        scheduled_for: when.value || null}));
    } catch (e) { error.textContent = e.message; }
  });
  return h('section', {class: 'panel', testid: `auth-panel-${platform}`},
    h('h2', {text: `Authorize ${PLATFORM_LABEL[platform] || platform}`}),
    h('div', {class: `auth-state ${stateClass}`, testid: 'auth-state', text: stateText}),
    !approved ? h('div', {class: 'muted', text: 'Approve the video first. Authorization is per platform and covers only this exact file and post text.'}) : null,
    CONFIRMATIONS.map(([key, label], i) => h('label', {class: 'confirm', for: `${platform}-${key}`}, boxes[i], label)),
    h('div', {class: 'row'}, phrase, h('label', {class: 'muted', text: 'Planned time (for your records only)'}), when),
    h('div', {class: 'row'}, button,
      auth && auth.valid ? h('button', {class: 'btn bad', testid: `revoke-${platform}`, text: 'Revoke', on: {click: async () => {
        rerender(await api(`/api/renders/${detail.id}/revoke`, {platform}));
      }}}) : null),
    error);
}

function eventsTable(detail) {
  const events = detail.events || [];
  if (!events.length) return h('p', {class: 'muted', text: 'No verified events in this edit.'});
  return h('table', {},
    h('thead', {}, h('tr', {}, ['Recording time', 'Event', 'Quest', 'Stars', 'Status', 'Evidence'].map((t) => h('th', {text: t})))),
    h('tbody', {}, events.map((e) => h('tr', {},
      h('td', {text: mmss(e.t)}), h('td', {text: e.kind}), h('td', {text: e.name || '—'}),
      h('td', {text: e.stars ? `+${e.stars}` : '—'}), h('td', {text: e.status || ''}),
      h('td', {}, Object.entries(e.evidence || {}).map(([k, path]) =>
        h('a', {href: media(detail.id, path), target: '_blank', title: k}, h('img', {src: media(detail.id, path), alt: k}))))))));
}

// Plays the exact final MP4. Browsers without an H.264 decoder get a clearly labelled,
// low-res VP9 review copy instead (approval still binds to the final file's hash).
function player(id, d) {
  const video = h('video', {testid: 'player', controls: true, preload: 'metadata', poster: media(id, d.cover || 'cover.jpg')});
  const note = h('div', {class: 'muted'});
  const wrap = h('div', {}, video, note,
    h('a', {testid: 'download-final', href: media(id, d.video.file), download: '', text: 'Download the exact final file'}));
  if (video.canPlayType('video/mp4; codecs="avc1.640028, mp4a.40.2"')) {
    video.src = media(id, d.video.file);
  } else {
    note.textContent = 'Preparing a review preview: this browser cannot play H.264…';
    api(`/api/renders/${encodeURIComponent(id)}/preview`, {}).then((res) => {
      video.src = res.url;
      note.dataset.testid = 'preview-note';
      note.textContent = 'Review preview (540×960 VP9) because this browser has no H.264 decoder. ' +
        'Watch the final MP4 in Chrome, Edge, Firefox or Safari before authorizing.';
    }).catch((e) => { note.textContent = `Preview failed: ${e.message}`; });
  }
  return wrap;
}

async function renderDetail(id) {
  const root = app();
  const draw = (d) => {
    const meta = d.metadata || {};
    const facts = d.facts || (meta.youtube_shorts || {}).facts || {};
    const v = d.video;
    const notes = h('textarea', {testid: 'decision-notes', placeholder: 'Notes (what you checked, what to change)…'});
    const decide = async (decision) => draw(await api(`/api/renders/${id}/decision`, {decision, notes: notes.value}));
    root.replaceChildren(
      h('div', {class: 'detail-head'},
        h('button', {class: 'btn', testid: 'back', text: '← All edits', on: {click: () => { location.hash = '#/'; }}}),
        h('h1', {text: d.label}),
        h('span', {class: `chip ${d.status}`, testid: 'detail-status', text: statusText(d.status)})),
      d.status === 'stale' ? h('div', {class: 'panel warning', testid: 'stale-warning',
        text: 'The video file or post text changed after your last decision. Watch and review it again.'}) : '',
      h('div', {class: 'layout'},
        h('div', {class: 'player-col'},
          player(id, d),
          h('section', {class: 'panel', testid: 'technical'}, h('h2', {text: 'Technical'}), kv([
            ['Resolution', `${v.width} × ${v.height}`], ['Frame rate', `${v.fps} fps`], ['Codec', v.vcodec],
            ['Duration', `${v.duration.toFixed(2)} s`], ['File size', `${(v.size / 1e6).toFixed(1)} MB`],
            ['Loudness', v.loudness_lufs !== null && v.loudness_lufs !== undefined ? `${v.loudness_lufs} LUFS` : 'n/a'],
            ['Encoder', `${d.encoder.name}${d.encoder.hw ? ' (hardware)' : ''}${d.encoder.fallback_from ? ` · fell back from ${d.encoder.fallback_from}` : ''}`],
            ['Overlay', d.overlay_engine], ['Video SHA-256', v.sha256.slice(0, 16) + '…']]))),
        h('div', {},
          h('section', {class: 'panel notice', testid: 'no-upload-notice'},
            h('strong', {text: 'Nothing is published from here. '}),
            'Approving and authorizing only record your decision for this exact video and post text. ' +
            'Upload it yourself from the prepared package (python -m studio package <id> <platform>) or ask Claude to, after you confirm.'),
          h('section', {class: 'panel'}, h('h2', {text: 'Your decision'}), notes,
            h('div', {class: 'row'},
              h('button', {class: 'btn good', testid: 'approve', text: 'Approve edit', on: {click: () => decide('approve')}}),
              h('button', {class: 'btn bad', testid: 'reject', text: 'Reject edit', on: {click: () => decide('reject')}}))),
          h('div', {class: 'two'}, Object.keys(meta).map((p) => authPanel(d, p, draw))),
          h('div', {class: 'two'}, Object.entries(meta).map(([p, post]) => postPanel(p, post))),
          h('section', {class: 'panel', testid: 'facts'}, h('h2', {text: 'Verified facts (counted on screen)'}), kv([
            ['Rank stars gained', facts.stars_verified === null || facts.stars_verified === undefined ? 'not calibrated' : `+${facts.stars_verified}`],
            ['Confirmed quests', facts.quests_confirmed], ['Rank ups', facts.rank_ups], ['Recording length', `${facts.minutes} min`]])),
          h('section', {class: 'panel', testid: 'events'}, h('h2', {text: 'Events in this edit'}), eventsTable(d)),
          h('section', {class: 'panel', testid: 'music'}, h('h2', {text: 'Music & license'}), kv([
            ['Track', d.music.title], ['License type', d.music.license_type], ['License', d.music.license], ['Proof', d.music.proof]])),
          h('section', {class: 'panel'}, h('h2', {text: 'Source recording'}), kv([
            ['File', d.source.path], ['SHA-256', d.source.sha256], ['Unchanged after render', d.source.verified_unchanged ? 'yes (verified)' : 'NO']])),
          (d.warnings || []).length ? h('section', {class: 'panel warning'}, h('h2', {text: 'Warnings'}),
            h('ul', {}, d.warnings.map((w) => h('li', {text: w})))) : '',
          h('section', {class: 'panel', testid: 'history'}, h('h2', {text: 'History'}),
            d.history.length ? h('ul', {class: 'history'}, d.history.map((e) => h('li', {text:
              `${e.at} · ${e.type}${e.decision ? `: ${e.decision}` : ''}${e.platform ? ` · ${PLATFORM_LABEL[e.platform] || e.platform}` : ''}${e.notes ? ` · “${e.notes}”` : ''}`})))
              : h('p', {class: 'muted', text: 'No decisions yet.'})))));
  };
  draw(await api(`/api/renders/${encodeURIComponent(id)}`));
}

// --- calibration -------------------------------------------------------------------
async function renderSources() {
  const sources = await api('/api/sources');
  app().replaceChildren(h('h1', {text: 'Calibrate recordings'}),
    h('p', {class: 'muted', text: 'Mark where the star counter and quest panel are once per recording layout. Nothing is counted until you do.'}),
    sources.length ? h('table', {}, h('tbody', {}, sources.map((s) => h('tr', {},
      h('td', {}, h('a', {href: `#/calibrate/${s.id}`, text: s.path.split(/[\\/]/).pop()})),
      h('td', {text: `${(s.info.duration / 60).toFixed(1)} min`}),
      h('td', {text: s.calibrated ? 'calibrated' : 'not calibrated'}), h('td', {text: s.analyzed ? 'analyzed' : ''})))))
      : h('div', {class: 'empty', text: 'No recordings registered. Run: python -m studio ingest "<recording>"'}));
}

async function renderCalibrate(sid) {
  const data = await api(`/api/sources/${encodeURIComponent(sid)}`);
  const rois = {...data.rois};
  let active = 'star_counter';
  let dragging = null;
  const img = h('img', {testid: 'calib-image', alt: 'Frame from the recording'});
  const canvas = h('canvas', {testid: 'calib-canvas'});
  const message = h('div', {class: 'muted', testid: 'calib-message'});
  const slider = h('input', {type: 'range', min: '0', max: String(Math.max(0, data.source.info.duration - 0.1)), step: '0.5',
    value: String((data.source.info.duration * 0.25).toFixed(1))});
  const timeLabel = h('span', {class: 'muted'});
  const ctx = canvas.getContext('2d');

  const draw = () => {
    canvas.width = img.clientWidth;
    canvas.height = img.clientHeight;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const all = Object.keys(ROI_LABEL).map((name) => [name, rois[name] || data.suggested[name], !rois[name]]);
    for (const [name, r, suggested] of all) {
      if (!r) continue;
      ctx.setLineDash(suggested ? [6, 6] : []);
      ctx.lineWidth = name === active ? 3 : 2;
      ctx.strokeStyle = ROI_COLORS[name];
      ctx.strokeRect(r.x * canvas.width, r.y * canvas.height, r.w * canvas.width, r.h * canvas.height);
      ctx.fillStyle = ROI_COLORS[name];
      ctx.font = '600 13px system-ui';
      ctx.fillText(`${ROI_LABEL[name]}${suggested ? ' (suggested)' : ''}`, r.x * canvas.width + 4, r.y * canvas.height - 6);
    }
  };
  const loadFrame = async () => {
    const t = Number(slider.value);
    timeLabel.textContent = mmss(t);
    const res = await api(`/api/sources/${sid}/frame`, {t});
    img.src = res.url;
  };
  img.addEventListener('load', draw);
  window.addEventListener('resize', draw);
  const pos = (ev) => {
    const b = canvas.getBoundingClientRect();
    return [Math.min(1, Math.max(0, (ev.clientX - b.left) / b.width)), Math.min(1, Math.max(0, (ev.clientY - b.top) / b.height))];
  };
  canvas.addEventListener('mousedown', (ev) => { dragging = pos(ev); });
  canvas.addEventListener('mousemove', (ev) => {
    if (!dragging) return;
    const [x, y] = pos(ev);
    rois[active] = {x: Math.min(x, dragging[0]), y: Math.min(y, dragging[1]), w: Math.abs(x - dragging[0]), h: Math.abs(y - dragging[1])};
    draw();
  });
  window.addEventListener('mouseup', () => { dragging = null; });

  const buttons = Object.keys(ROI_LABEL).map((name) => h('button', {class: `btn${name === active ? ' active' : ''}`, testid: `roi-${name}`,
    text: ROI_LABEL[name], on: {click: () => {
      active = name;
      buttons.forEach((b) => b.classList.toggle('active', b.dataset.testid === `roi-${name}`));
      draw();
    }}}));
  app().replaceChildren(
    h('div', {class: 'detail-head'}, h('button', {class: 'btn', text: '← Recordings', on: {click: () => { location.hash = '#/calibrate'; }}}),
      h('h1', {text: data.source.path.split(/[\\/]/).pop()})),
    h('section', {class: 'panel'},
      h('p', {class: 'muted', text: 'Pick a region, then drag a box over it on the frame. The star counter must include the full number (e.g. 19/40). Scrub to a moment where the HUD is clearly visible.'}),
      h('div', {class: 'row'}, slider, timeLabel, h('button', {class: 'btn', text: 'Show frame', on: {click: loadFrame}})),
      h('div', {class: 'roi-buttons'}, buttons,
        h('button', {class: 'btn', text: 'Use suggestions for unset regions', on: {click: () => {
          for (const [k, v] of Object.entries(data.suggested)) if (!rois[k]) rois[k] = {...v};
          draw();
        }}}),
        h('button', {class: 'btn bad', text: 'Clear selected region', on: {click: () => { delete rois[active]; draw(); }}})),
      h('div', {class: 'calib-wrap'}, img, canvas),
      h('div', {class: 'row'},
        h('button', {class: 'btn go', testid: 'save-calibration', text: 'Save calibration', on: {click: async () => {
          try {
            const res = await api(`/api/sources/${sid}/profile`, {rois});
            message.textContent = `Saved ${Object.keys(res.rois).length} region(s). Now run: python -m studio analyze ${sid}`;
          } catch (e) { message.textContent = `Not saved: ${e.message}`; }
        }}}), message)));
  await loadFrame();
}

// --- router -------------------------------------------------------------------------
async function route() {
  const [, page, id] = (location.hash || '#/').slice(1).split('/');
  try {
    if (page === 'render' && id) await renderDetail(decodeURIComponent(id));
    else if (page === 'calibrate' && id) await renderCalibrate(decodeURIComponent(id));
    else if (page === 'calibrate') await renderSources();
    else await renderList();
  } catch (e) {
    app().replaceChildren(h('div', {class: 'panel warning', text: `Could not load: ${e.message}`}));
  }
  window.scrollTo(0, 0);
}
window.addEventListener('hashchange', route);
route();
