const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'g_doorlock';

let L = {};
let cfg = { pinMin: 4, pinMax: 8, indicator: true, defaults: {} };

const $ = (id) => document.getElementById(id);

function post(name, data) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => null);
}

// same placeholders as lua string.format (%s %d)
function t(key, ...args) {
    let s = L[key] || key;
    let i = 0;
    return s.replace(/%[sd]/g, () => (args[i] !== undefined ? args[i++] : ''));
}

function esc(str) {
    return String(str == null ? '' : str)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function clone(o) {
    return JSON.parse(JSON.stringify(o));
}

function applyI18n() {
    document.querySelectorAll('[data-i18n]').forEach((el) => { el.textContent = t(el.dataset.i18n); });
    document.querySelectorAll('[data-i18n-ph]').forEach((el) => { el.placeholder = t(el.dataset.i18nPh); });
}

let audioCtx = null;

function tone(freq, start, dur, type, vol, slideTo) {
    const ctx = audioCtx;
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, ctx.currentTime + start);
    if (slideTo) o.frequency.linearRampToValueAtTime(slideTo, ctx.currentTime + start + dur);
    g.gain.setValueAtTime(0.0001, ctx.currentTime + start);
    g.gain.exponentialRampToValueAtTime(vol, ctx.currentTime + start + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + start + dur);
    o.connect(g).connect(ctx.destination);
    o.start(ctx.currentTime + start);
    o.stop(ctx.currentTime + start + dur + 0.02);
}

function click(start, vol) {
    const ctx = audioCtx;
    const len = Math.floor(ctx.sampleRate * 0.04);
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 4);
    const src = ctx.createBufferSource();
    const g = ctx.createGain();
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = 2200;
    g.gain.value = vol;
    src.buffer = buf;
    src.connect(f).connect(g).connect(ctx.destination);
    src.start(ctx.currentTime + start);
}

const presets = {
    bolt: (v) => { click(0, v * 1.4); tone(140, 0, 0.09, 'square', v * 0.25, 90); click(0.09, v * 1.6); },
    unlock: (v) => { click(0, v * 1.2); tone(520, 0.02, 0.08, 'sine', v * 0.5); tone(780, 0.1, 0.1, 'sine', v * 0.5); },
    beep: (v) => { tone(880, 0, 0.12, 'sine', v * 0.6); },
    denied: (v) => { tone(220, 0, 0.14, 'square', v * 0.25); tone(160, 0.16, 0.2, 'square', v * 0.25); },
    chime: (v) => { tone(660, 0, 0.15, 'sine', v * 0.5); tone(880, 0.12, 0.15, 'sine', v * 0.5); tone(1320, 0.24, 0.25, 'sine', v * 0.4); },
    keycard: (v) => { tone(1200, 0, 0.06, 'square', v * 0.2); tone(1600, 0.08, 0.09, 'square', v * 0.2); click(0.2, v * 1.2); },
    heavy: (v) => { tone(70, 0, 0.35, 'sawtooth', v * 0.25, 45); click(0.05, v * 2); click(0.3, v * 2.2); },
    knock: (v) => { click(0, v * 2.5); click(0.18, v * 2.5); click(0.36, v * 2.5); },
    alarm: (v) => { tone(880, 0, 0.5, 'square', v * 0.22, 1320); tone(1320, 0.55, 0.5, 'square', v * 0.22, 880); },
    gate: (v) => { tone(90, 0, 0.9, 'sawtooth', v * 0.15, 110); tone(180, 0, 0.9, 'triangle', v * 0.12, 200); click(0.92, v * 1.5); },
};

function playSound(data) {
    const vol = Math.max(0, Math.min(1, data.volume || 0.3));
    if (data.type === 'file' && data.file) {
        const a = new Audio('sounds/' + data.file);
        a.volume = vol;
        a.play().catch(() => {});
        return;
    }
    if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    if (audioCtx.state === 'suspended') audioCtx.resume();
    const fn = presets[data.preset] || presets.beep;
    fn(vol);
}

function toast(type, text, action) {
    const el = document.createElement('div');
    el.className = 'toast ' + (type || '');
    el.textContent = text;
    if (action) {
        const b = document.createElement('button');
        b.className = 'small toast-btn';
        b.textContent = action.label;
        b.addEventListener('click', () => { el.remove(); action.fn(); });
        el.appendChild(b);
    }
    $('toasts').appendChild(el);
    setTimeout(() => el.remove(), action ? 8000 : 3200);
}

const ICON_LOCK = '<svg viewBox="0 0 24 24" fill="#fca5a5"><path d="M17 9V7A5 5 0 0 0 7 7v2H5v13h14V9h-2zM9 7a3 3 0 0 1 6 0v2H9V7z"/></svg>';
const ICON_OPEN = '<svg viewBox="0 0 24 24" fill="#4ade80"><path d="M17 9H9V7a3 3 0 0 1 5.8-1.1l1.9-.6A5 5 0 0 0 7 7v2H5v13h14V9h-2z"/></svg>';

function setIndicator(d) {
    const el = $('indicator');
    if (!cfg.indicator || !d.show) {
        el.classList.add('hidden');
        return;
    }
    el.classList.remove('hidden', 'denied');
    el.classList.toggle('open', !d.locked);
    $('ind-icon').innerHTML = d.locked ? ICON_LOCK : ICON_OPEN;
    $('ind-state').textContent = d.broken ? t('ed_broken') : (d.locked ? t('locked') : t('unlocked'));
    $('ind-name').textContent = d.name || '';
    if (d.key) {
        $('ind-key').textContent = d.key;
        $('ind-key').classList.remove('hidden');
    } else {
        $('ind-key').classList.add('hidden');
    }
    if (d.action) {
        $('ind-action-key').textContent = d.actionKey;
        $('ind-action-text').textContent = d.action;
        $('ind-action').classList.remove('hidden');
    } else {
        $('ind-action').classList.add('hidden');
    }
}

function flashDenied() {
    const el = $('indicator');
    el.classList.remove('denied');
    void el.offsetWidth;
    el.classList.add('denied');
    $('ind-state').textContent = t('access_denied');
    setTimeout(() => el.classList.remove('denied'), 1500);
}

let pin = '';

function renderPin() {
    $('kp-display').textContent = pin.length ? '•'.repeat(pin.length) : '';
}

function openKeypad(d) {
    pin = '';
    renderPin();
    $('kp-title').textContent = d.name || '';
    $('kp-sub').textContent = t('keypad_title');
    $('kp-error').textContent = '';
    $('keypad').classList.remove('hidden');
}

function closeKeypad() {
    $('keypad').classList.add('hidden');
    pin = '';
}

function keypadPress(k) {
    if (k === 'del') {
        pin = pin.slice(0, -1);
    } else if (k === 'ok') {
        if (pin.length < cfg.pinMin) {
            $('kp-error').textContent = t('pin_too_short', cfg.pinMin);
            return;
        }
        post('keypad:submit', { pin: pin });
        pin = '';
    } else if (pin.length < cfg.pinMax) {
        pin += k;
    }
    $('kp-error').textContent = '';
    renderPin();
}

document.querySelectorAll('.kp-grid button').forEach((b) => {
    b.addEventListener('click', () => { keypadPress(b.dataset.k); b.blur(); });
});
$('kp-cancel').addEventListener('click', () => { closeKeypad(); post('close'); });

const ed = {
    picked: new Set(),
    templates: [],
    packs: [],
    doors: [],
    draft: null,
    supportsGangs: true,
    supportsMetadata: true,
    pinClear: false,
};

function blankDoor(type) {
    const d = cfg.defaults || {};
    return {
        id: '', name: '', group: '', type: type || 'single', bucket: 0, doors: [],
        locked: d.locked !== false, persist: d.persist !== false, autoLock: d.autoLock || 0,
        interactDistance: d.interact || 2.0, autoDistance: d.auto || 0, hideIndicator: false,
        access: { mode: d.mode || 'any', public: false, admin: true, pin: false, jobs: [], gangs: [], identifiers: [], items: [] },
    };
}

function groupLabel(name) {
    const g = (ed.groups || []).find((x) => x.name === name);
    return g ? g.label : name;
}

function renderGroups() {
    const groups = ed.groups || [];
    const opts = groups.map((g) => `<option value="${esc(g.name)}">${esc(g.label)}${g.label !== g.name ? ' (' + esc(g.name) + ')' : ''}</option>`).join('');

    const filter = $('ed-group');
    const cur = filter.value;
    filter.innerHTML = `<option value="">${esc(t('ed_all_groups'))}</option>` + opts;
    if (groups.some((g) => g.name === cur)) filter.value = cur;

    const pick = $('f-group');
    const picked = pick.value;
    pick.innerHTML = `<option value="">${esc(t('ed_no_group'))}</option>` + opts;
    pick.value = picked;
}

function matchSearch(d, q) {
    const m = q.match(/^(job|gang|item|group|type|id):\s*(.+)$/);
    if (!m) {
        return d.id.toLowerCase().includes(q) || (d.name || '').toLowerCase().includes(q) || (d.group || '').toLowerCase().includes(q);
    }
    const v = m[2];
    const a = d.access || {};
    if (m[1] === 'job') return (a.jobs || []).some((j) => j.name.toLowerCase() === v);
    if (m[1] === 'gang') return (a.gangs || []).some((j) => j.name.toLowerCase() === v);
    if (m[1] === 'item') return (a.items || []).some((i) => i.name.toLowerCase() === v || (i.metadata || '').toLowerCase() === v);
    if (m[1] === 'group') return (d.group || '') === v;
    if (m[1] === 'type') return d.type === v;
    return d.id.toLowerCase() === v;
}

function filteredDoors() {
    const q = $('ed-search').value.trim().toLowerCase();
    const g = $('ed-group').value;
    return ed.doors.filter((d) => {
        if (g && d.group !== g) return false;
        return !q || matchSearch(d, q);
    });
}

function renderList() {
    const list = filteredDoors();
    const activeId = ed.draft && !ed.draft.isNew ? ed.draft.data.id : null;
    $('ed-list').innerHTML = list.map((d) => `
        <div class="door-item ${d.id === activeId ? 'active' : ''}" data-id="${esc(d.id)}">
            <input type="checkbox" class="pick" ${ed.picked.has(d.id) ? 'checked' : ''}>
            <span class="dot ${d.state ? '' : 'open'}"></span>
            <div class="meta"><b>${esc(d.name)}</b><small>${esc(d.id)}${d.group ? ' · ' + esc(d.group) : ''}</small></div>
            <span class="tag">${esc(t('ed_type_' + d.type))}</span>
        </div>`).join('');
    if (!list.length) $('ed-list').innerHTML = `<div class="muted small">${esc(t('ed_empty'))}</div>`;
    $('ed-count').textContent = t('ed_count', list.length, ed.doors.length);
    $('ed-list').querySelectorAll('.door-item').forEach((el) => {
        el.addEventListener('click', (e) => {
            if (e.target.classList.contains('pick')) return;
            selectDoor(el.dataset.id);
        });
        el.querySelector('.pick').addEventListener('change', (e) => {
            if (e.target.checked) ed.picked.add(el.dataset.id); else ed.picked.delete(el.dataset.id);
            renderBulkBar();
        });
    });
    renderBulkBar();
}

function selectDoor(id) {
    const door = ed.doors.find((d) => d.id === id);
    if (!door) return;
    ed.draft = { isNew: false, rev: door.rev, hasPin: door.hasPin, state: door.state, temp: door.tempAccess, broken: door.broken, data: clone(door) };
    ['rev', 'hasPin', 'state', 'tempAccess', 'broken'].forEach((k) => delete ed.draft.data[k]);
    ed.pinClear = false;
    renderForm();
    renderList();
    sendPreview();
}

function newDraft(template) {
    let data;
    if (template) {
        data = clone(template);
        data.id = (template.id + '_copy').slice(0, 64);
        data.name = template.name + ' (copy)';
        data.doors = [];
        data.access.pin = false;
    } else {
        data = blankDoor('single');
    }
    ed.draft = { isNew: true, rev: null, hasPin: false, state: data.locked, data: data };
    ed.pinClear = false;
    renderForm();
    renderList();
    post('editor:preview', { leaves: [] });
}

function rowHtml(kind, v) {
    if (kind === 'jobs' || kind === 'gangs') {
        return `<div class="r"><input class="n" value="${esc(v.name || '')}" placeholder="${esc(t('ed_name_ph'))}">
            <input class="g" type="number" min="0" value="${esc(v.grade || 0)}" title="${esc(t('ed_grade_ph'))}">
            <button type="button" class="x">&times;</button></div>`;
    }
    if (kind === 'identifiers') {
        return `<div class="r"><input class="n" value="${esc(v || '')}" placeholder="${esc(t('ed_ident_ph'))}">
            <button type="button" class="x">&times;</button></div>`;
    }
    return `<div class="r"><input class="n" list="item-list" value="${esc(v.name || '')}" placeholder="${esc(t('ed_item_name'))}">
        <input class="m" value="${esc(v.metadata || '')}" placeholder="${esc(t('ed_item_meta'))}">
        <label class="tg"><input type="checkbox" class="rm" ${v.remove ? 'checked' : ''}><span>${esc(t('ed_item_remove'))}</span></label>
        <button type="button" class="x">&times;</button></div>`;
}

function renderRows(kind, values) {
    const box = $('l-' + kind);
    box.innerHTML = values.map((v) => rowHtml(kind, v)).join('');
    box.querySelectorAll('.x').forEach((b) => b.addEventListener('click', () => b.parentElement.remove()));
}

function addRow(kind, value) {
    const box = $('l-' + kind);
    const tmp = document.createElement('div');
    tmp.innerHTML = rowHtml(kind, value || (kind === 'identifiers' ? '' : {}));
    const row = tmp.firstElementChild;
    row.querySelector('.x').addEventListener('click', () => row.remove());
    box.appendChild(row);
    return row;
}

function renderLeaves() {
    const leaves = ed.draft.data.doors || [];
    $('f-leaves').innerHTML = leaves.length
        ? leaves.map((l, i) => `<div class="leaf"><b>#${i + 1}</b> model ${esc(l.model)} · ${(+l.coords.x).toFixed(2)}, ${(+l.coords.y).toFixed(2)}, ${(+l.coords.z).toFixed(2)} · h ${(+l.heading).toFixed(1)}</div>`).join('')
        : `<div class="leaf">${esc(t('ed_need_leaves'))}</div>`;
}

function renderPinStatus() {
    const st = $('f-pin-status');
    const has = ed.draft.hasPin && !ed.pinClear;
    st.textContent = has ? t('ed_pin_set') : t('ed_pin_none');
    st.className = 'badge ' + (has ? 'ok' : '');
    $('f-pin-clear').disabled = !has;
}

let currentTab = 'general';

function showTab(name) {
    currentTab = name;
    document.querySelectorAll('.tab').forEach((b) => b.classList.toggle('active', b.dataset.tab === name));
    document.querySelectorAll('#ed-form fieldset[data-tab]').forEach((fs) => fs.classList.toggle('hidden', fs.dataset.tab !== name));
    $('ed-main').scrollTop = 0;
}

document.querySelectorAll('.tab').forEach((b) => b.addEventListener('click', () => showTab(b.dataset.tab)));

// small dot on the tabs that have something turned on
function updateTabDots() {
    $('f-lockpick-diff').disabled = !$('f-lockpick').checked;
    document.querySelectorAll('.opt-card').forEach((c) => c.classList.toggle('on', c.querySelector('input[type=checkbox]').checked));
    const on = {
        general: false,
        behaviour: $('f-sched').checked || $('f-autolock').value > 0 || $('f-sound-lock').value !== 'default' || $('f-sound-unlock').value !== 'default',
        access: $('f-public').checked || $('f-bell').checked || (ed.draft && ed.draft.hasPin && !ed.pinClear) || $('f-pin').value !== '',
        breakin: $('f-lockpick').checked || $('f-breach').checked || $('f-alarm').checked || $('f-hack').checked,
    };
    document.querySelectorAll('.tab').forEach((b) => b.classList.toggle('on', !!on[b.dataset.tab]));
}

$('ed-form').addEventListener('change', updateTabDots);
$('ed-form').addEventListener('input', updateTabDots);

function renderSub() {
    const d = ed.draft.data;
    const parts = [];
    if (d.id) parts.push(d.id);
    parts.push(t('ed_type_' + d.type));
    if (d.group) parts.push(groupLabel(d.group));
    $('f-sub').textContent = parts.join('  ·  ');
}

function renderForm() {
    const d = ed.draft.data;
    $('ed-empty').classList.add('hidden');
    $('ed-form').classList.remove('hidden');
    $('f-title').textContent = ed.draft.isNew ? t('ed_new_draft') : d.name;
    $('f-badge').textContent = ed.draft.isNew ? t('ed_unsaved') : (ed.draft.state ? t('locked') : t('unlocked'));
    $('f-badge').className = 'badge ' + (ed.draft.isNew ? '' : (ed.draft.state ? 'bad' : 'ok'));
    $('f-id').value = d.id;
    $('f-id').disabled = !ed.draft.isNew;
    $('f-name').value = d.name || '';
    $('f-group').value = d.group || '';
    $('f-lockpick').checked = !!d.lockpick;
    $('f-lockpick-diff').value = (d.lockpick && d.lockpick.difficulty) || 'medium';
    $('f-breach').checked = !!d.breach;
    $('f-alarm').checked = !!d.alarm;
    $('f-bell').checked = !!d.bell;
    $('f-remote').checked = !!d.remote;
    $('f-hack').checked = !!d.hackable;
    const sc = d.schedule || {};
    $('f-sched').checked = !!d.schedule;
    $('f-sched-open').value = sc.open || '08:00';
    $('f-sched-close').value = sc.close || '20:00';
    renderDays(sc.days || []);
    $('f-broken').classList.toggle('hidden', !ed.draft.broken);
    $('f-type').value = d.type;
    $('f-bucket').value = d.bucket || 0;
    $('f-interact').value = d.interactDistance;
    $('f-auto').value = d.autoDistance;
    $('f-autolock').value = d.autoLock;
    $('f-locked').checked = d.locked;
    $('f-persist').checked = d.persist;
    $('f-hide').checked = !!d.hideIndicator;
    $('f-mode').value = d.access.mode;
    $('f-public').checked = d.access.public;
    $('f-admin').checked = d.access.admin;
    renderRows('jobs', d.access.jobs || []);
    renderRows('gangs', d.access.gangs || []);
    renderRows('identifiers', d.access.identifiers || []);
    renderRows('items', d.access.items || []);
    $('gangs-note').classList.toggle('hidden', ed.supportsGangs);
    $('items-note').classList.toggle('hidden', ed.supportsMetadata);
    const snd = d.sounds || {};
    $('f-sound-lock').value = snd.lock || 'default';
    $('f-sound-unlock').value = snd.unlock || 'default';
    $('f-pin').value = '';
    $('f-temp').classList.toggle('hidden', !ed.draft.temp);
    renderPinStatus();
    renderLeaves();
    ['f-duplicate', 'f-goto', 'f-state', 'f-delete'].forEach((id) => { $(id).disabled = ed.draft.isNew; });
    $('f-state').textContent = ed.draft.state ? t('ed_unlock_now') : t('ed_lock_now');
    renderSub();
    showTab(ed.draft.isNew ? 'general' : currentTab);
    updateTabDots();
}

function readRows(kind) {
    const out = [];
    $('l-' + kind).querySelectorAll('.r').forEach((r) => {
        const name = r.querySelector('.n').value.trim();
        if (!name) return;
        if (kind === 'jobs' || kind === 'gangs') out.push({ name: name, grade: parseInt(r.querySelector('.g').value, 10) || 0 });
        else if (kind === 'identifiers') out.push(name);
        else out.push({ name: name, metadata: r.querySelector('.m').value.trim() || undefined, remove: r.querySelector('.rm').checked });
    });
    return out;
}

function readForm() {
    const d = ed.draft.data;
    if (ed.draft.isNew) d.id = $('f-id').value.trim().toLowerCase();
    d.name = $('f-name').value.trim();
    d.group = $('f-group').value || undefined;
    d.lockpick = $('f-lockpick').checked ? { enabled: true, difficulty: $('f-lockpick-diff').value } : undefined;
    d.breach = $('f-breach').checked ? { enabled: true } : undefined;
    d.alarm = $('f-alarm').checked || undefined;
    d.bell = $('f-bell').checked || undefined;
    d.remote = $('f-remote').checked || undefined;
    d.hackable = $('f-hack').checked || undefined;
    d.schedule = $('f-sched').checked ? {
        enabled: true,
        open: $('f-sched-open').value,
        close: $('f-sched-close').value,
        days: [...document.querySelectorAll('#f-sched-days input:checked')].map((c) => parseInt(c.value, 10)),
    } : undefined;
    d.type = $('f-type').value;
    d.bucket = parseInt($('f-bucket').value, 10) || 0;
    d.interactDistance = parseFloat($('f-interact').value) || 2.0;
    d.autoDistance = parseFloat($('f-auto').value) || 0;
    d.autoLock = parseInt($('f-autolock').value, 10) || 0;
    d.locked = $('f-locked').checked;
    d.persist = $('f-persist').checked;
    d.hideIndicator = $('f-hide').checked;
    d.access.mode = $('f-mode').value;
    d.access.public = $('f-public').checked;
    d.access.admin = $('f-admin').checked;
    d.access.jobs = readRows('jobs');
    d.access.gangs = readRows('gangs');
    d.access.identifiers = readRows('identifiers');
    d.access.items = readRows('items');
    d.sounds = {};
    ['lock', 'unlock'].forEach((kind) => {
        const v = $('f-sound-' + kind).value;
        if (v !== 'default') d.sounds[kind] = v;
    });
    return d;
}

function upsertDoor(door) {
    const i = ed.doors.findIndex((d) => d.id === door.id);
    if (i >= 0) ed.doors[i] = door; else ed.doors.push(door);
    ed.doors.sort((a, b) => a.id.localeCompare(b.id));
}

function errText(res) {
    if (!res) return t('err_generic');
    return t(res.err || 'err_generic') + (res.detail ? ` (${res.detail})` : '');
}

let saving = false;

async function saveDraft(e) {
    e.preventDefault();
    if (saving || !ed.draft) return;
    const data = readForm();
    if (!data.id) data.id = slug(data.name);
    if (!data.id) { toast('error', t('err_invalid_id')); return; }
    if (!data.doors || !data.doors.length) { toast('error', t('ed_need_leaves')); return; }

    let pinAction = null;
    const newPin = $('f-pin').value.trim();
    if (newPin) {
        if (!/^\d+$/.test(newPin) || newPin.length < cfg.pinMin || newPin.length > cfg.pinMax) {
            toast('error', t('err_pin_format') + ` (${cfg.pinMin}-${cfg.pinMax})`);
            return;
        }
        pinAction = { set: newPin };
    } else if (ed.pinClear) {
        pinAction = { clear: true };
    }
    data.access.pin = !!pinAction && !!pinAction.set || (ed.draft.hasPin && !ed.pinClear);

    saving = true;
    const res = await post('editor:save', { door: data, isNew: ed.draft.isNew, rev: ed.draft.rev, pin: pinAction });
    saving = false;
    if (!res || !res.ok) {
        toast('error', errText(res));
        return;
    }
    upsertDoor(res.door);
    ed.groups = res.groups || ed.groups;
    renderGroups();
    toast('success', t('ed_saved'));
    selectDoor(res.door.id);
}

function slug(s) {
    return String(s || '').toLowerCase().replace(/[^a-z0-9_-]+/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '').slice(0, 48);
}

function modal(title, bodyHtml, actions) {
    $('m-title').textContent = title;
    $('m-body').innerHTML = bodyHtml;
    const box = $('m-actions');
    box.innerHTML = '';
    actions.forEach((a) => {
        const b = document.createElement('button');
        b.type = 'button';
        b.textContent = a.label;
        if (a.cls) b.className = a.cls;
        b.addEventListener('click', a.fn);
        box.appendChild(b);
    });
    $('modal').classList.remove('hidden');
}

function closeModal() {
    $('modal').classList.add('hidden');
}

function confirmDelete() {
    const d = ed.draft.data;
    modal(t('ed_delete'), `<p>${esc(t('ed_delete_q', d.name))}</p>`, [
        { label: t('ed_cancel'), fn: closeModal },
        {
            label: t('ed_delete'), cls: 'danger', fn: async () => {
                const res = await post('editor:delete', { id: d.id });
                closeModal();
                if (!res || !res.ok) { toast('error', errText(res)); return; }
                ed.doors = ed.doors.filter((x) => x.id !== d.id);
                ed.draft = null;
                $('ed-form').classList.add('hidden');
                $('ed-empty').classList.remove('hidden');
                post('editor:preview', { leaves: [] });
                renderGroups();
                renderList();
                toast('success', t('ed_deleted'), { label: t('ed_undo'), fn: () => restoreDoor(d.id) });
            },
        },
    ]);
}

async function openExport() {
    const ids = filteredDoors().map((d) => d.id);
    const res = await post('editor:export', { ids: ids });
    if (!res || !res.json) { toast('error', errText(res)); return; }
    modal(t('ed_export_title', res.count), `
        <textarea id="m-json" readonly>${esc(res.json)}</textarea>
        <p class="muted small">${res.file ? esc(t('ed_export_file', res.file)) : esc(t('ed_export_nofile'))}</p>`, [
        { label: t('ed_close'), fn: closeModal },
        { label: t('ed_copy'), cls: 'primary', fn: () => { post('editor:copy', { text: res.json }); toast('success', t('ed_copied')); } },
    ]);
}

function openImport() {
    modal(t('ed_import_title'), `
        <p class="muted small">${esc(t('ed_import_ph'))}</p>
        <textarea id="m-json" placeholder='{"doors":[...]}'></textarea>
        <label class="tg" style="margin-top:8px"><input type="checkbox" id="m-overwrite"><span>${esc(t('ed_overwrite'))}</span></label>
        <div class="row tight migrate">
            <span class="muted small">${esc(t('ed_migrate'))}</span>
            <button type="button" class="small" data-migrate="ox">ox_doorlock</button>
            <button type="button" class="small" data-migrate="qb">qb-doorlock</button>
        </div>
        <div class="row tight migrate">
            <span class="muted small">${esc(t('ed_packs'))}</span>
            <select id="m-pack">${ed.packs.map((p) => `<option value="${esc(p.file)}">${esc(p.label)} (${p.count})</option>`).join('')}</select>
            <button type="button" class="small" id="m-pack-run" ${ed.packs.length ? '' : 'disabled'}>${esc(t('ed_import_run'))}</button>
        </div>
        <div id="m-report" class="report"></div>`, [
        { label: t('ed_close'), fn: closeModal },
        {
            label: t('ed_import_run'), cls: 'primary', fn: async () => {
                const text = $('m-json').value.trim();
                if (!text) return;
                const res = await post('editor:import', { text: text, overwrite: $('m-overwrite').checked });
                showReport(res);
            },
        },
    ]);
    $('m-pack-run').addEventListener('click', async () => {
        const res = await post('editor:importPack', { file: $('m-pack').value, overwrite: $('m-overwrite').checked });
        showReport(res);
    });
    document.querySelectorAll('[data-migrate]').forEach((b) => b.addEventListener('click', async () => {
        b.disabled = true;
        const res = await post('editor:migrate', { from: b.dataset.migrate, overwrite: $('m-overwrite').checked });
        b.disabled = false;
        showReport(res);
    }));
}

function showReport(res) {
    if (!res || !res.ok) { toast('error', errText(res)); return; }
    const lines = [];
    res.created.forEach((id) => lines.push(`<div class="c">+ ${esc(id)} — ${esc(t('ed_created'))}</div>`));
    res.updated.forEach((id) => lines.push(`<div class="c">~ ${esc(id)} — ${esc(t('ed_updated'))}</div>`));
    res.skipped.forEach((x) => lines.push(`<div class="s">= ${esc(x.id)} — ${esc(t(x.err))}</div>`));
    res.errors.forEach((e) => lines.push(`<div class="e">! ${esc(e.id || '#' + e.index)} — ${esc(t(e.err))}${e.detail ? ' (' + esc(e.detail) + ')' : ''}</div>`));
    $('m-report').innerHTML = `<p><b>${esc(t('ed_import_res', res.created.length, res.updated.length, res.skipped.length, res.errors.length))}</b></p>` + lines.join('');
    ed.doors = res.doors || ed.doors;
    ed.groups = res.groups || ed.groups;
    renderGroups();
    renderList();
}

$('ed-form').addEventListener('submit', saveDraft);
$('ed-search').addEventListener('input', renderList);
$('ed-group').addEventListener('change', renderList);
$('ed-new').addEventListener('click', () => newDraft(null));
$('ed-import').addEventListener('click', openImport);
$('ed-export').addEventListener('click', openExport);
$('ed-close').addEventListener('click', () => post('close'));

document.querySelectorAll('[data-add]').forEach((b) => b.addEventListener('click', () => addRow(b.dataset.add)));

$('f-pick').addEventListener('click', () => {
    readForm();
    const type = $('f-type').value;
    const min = type === 'double' ? 2 : 1;
    const max = (type === 'double' || type === 'gate') ? 2 : 1;
    post('editor:select', { min: min, max: max });
});
function sendPreview() {
    if (!ed.draft) return;
    post('editor:preview', {
        leaves: ed.draft.data.doors || [],
        interact: parseFloat($('f-interact').value) || 0,
        auto: parseFloat($('f-auto').value) || 0,
    });
}
$('f-preview').addEventListener('click', sendPreview);
$('f-interact').addEventListener('input', sendPreview);
$('f-auto').addEventListener('input', sendPreview);
$('f-duplicate').addEventListener('click', () => newDraft(readForm()));
$('f-goto').addEventListener('click', async () => {
    const ok = await post('editor:goto', { id: ed.draft.data.id });
    if (ok) post('close'); else toast('error', t('err_generic'));
});
$('f-delete').addEventListener('click', confirmDelete);
$('f-pin-clear').addEventListener('click', () => { ed.pinClear = true; $('f-pin').value = ''; renderPinStatus(); });

$('f-state').addEventListener('click', async () => {
    const want = !ed.draft.state;
    const res = await post('editor:setState', { id: ed.draft.data.id, locked: want });
    if (!res || !res.ok) { toast('error', errText(res)); return; }
    ed.draft.state = want;
    const d = ed.doors.find((x) => x.id === ed.draft.data.id);
    if (d) d.state = want;
    renderForm();
    renderList();
});

async function fetchIdentifier(target) {
    const res = await post('editor:identifier', { target: target || null });
    if (!res || !res.identifier) { toast('error', t('ed_id_not_found')); return; }
    addRow('identifiers', res.identifier);
    toast('success', t('ed_ident_added', res.name || '', res.identifier));
}
$('f-ident-fetch').addEventListener('click', () => {
    const v = $('f-ident-target').value;
    if (!v) { toast('error', t('ed_id_not_found')); return; }
    fetchIdentifier(v);
});
$('f-ident-me').addEventListener('click', () => fetchIdentifier(null));

function fillSoundSelects() {
    const list = cfg.sounds || [];
    document.querySelectorAll('.sound-select').forEach((sel) => {
        sel.innerHTML = `<option value="default">${esc(t('ed_sound_default'))}</option>` +
            `<option value="none">${esc(t('ed_sound_none'))}</option>` +
            list.map((s) => `<option value="${esc(s.key)}">${esc(s.label)}</option>`).join('');
    });
}

document.querySelectorAll('[data-test]').forEach((b) => {
    b.addEventListener('click', () => {
        const kind = b.dataset.test;
        post('editor:testSound', { kind: kind, key: $('f-sound-' + kind).value });
    });
});

const GUIDE_STEPS = ['guide_1', 'guide_2', 'guide_3', 'guide_4', 'guide_5', 'guide_6', 'guide_7'];

function renderGuide(box) {
    box.innerHTML = '<ol class="guide">' +
        GUIDE_STEPS.map((k) => `<li>${esc(t(k))}</li>`).join('') +
        `</ol><p class="muted small">${esc(t('guide_tip'))}</p>`;
}

$('ed-help').addEventListener('click', () => {
    modal(t('guide_title'), '<div id="m-guide"></div>', [{ label: t('ed_close'), cls: 'primary', fn: closeModal }]);
    renderGuide($('m-guide'));
});

const DAYS = [2, 3, 4, 5, 6, 7, 1]; // monday first, values are lua os.date wday

function renderDays(selected) {
    $('f-sched-days').innerHTML = DAYS.map((d) => `<label class="tg day"><input type="checkbox" value="${d}" ${selected.includes(d) ? 'checked' : ''}><span>${esc(t('day_' + d))}</span></label>`).join('');
}

$('ed-find').addEventListener('click', async () => {
    const id = await post('editor:nearest', {});
    if (!id) { toast('error', t('quick_none')); return; }
    selectDoor(id);
});

function applyGroupResult(res) {
    if (!res || !res.ok) { toast('error', errText(res)); return false; }
    ed.groups = res.groups || ed.groups;
    ed.doors = res.doors || ed.doors;
    renderGroups();
    renderList();
    if (ed.draft && !ed.draft.isNew) {
        const door = ed.doors.find((x) => x.id === ed.draft.data.id);
        if (door) {
            ed.draft.data.group = door.group;
            ed.draft.state = door.state;
            $('f-group').value = door.group || '';
        }
    }
    renderGroupModal();
    return true;
}

function renderGroupModal() {
    const box = $('m-groups');
    if (!box) return;
    const groups = ed.groups || [];
    box.innerHTML = groups.length ? groups.map((g) => `
        <div class="group-row" data-name="${esc(g.name)}">
            <div class="meta"><b>${esc(g.label)}</b><small>${esc(g.name)} · ${esc(t('ed_group_doors', g.count))}</small></div>
            <button type="button" class="small" data-act="unlock">${esc(t('ed_group_unlock'))}</button>
            <button type="button" class="small" data-act="lock">${esc(t('ed_group_lock'))}</button>
            <button type="button" class="small" data-act="edit">&#9998;</button>
            <button type="button" class="small danger-ghost" data-act="delete">&times;</button>
        </div>`).join('') : `<p class="muted small">${esc(t('ed_group_empty'))}</p>`;

    box.querySelectorAll('.group-row').forEach((row) => {
        const name = row.dataset.name;
        row.querySelectorAll('[data-act]').forEach((b) => b.addEventListener('click', async () => {
            const act = b.dataset.act;
            if (act === 'lock' || act === 'unlock') {
                const res = await post('editor:groupState', { name: name, locked: act === 'lock' });
                if (applyGroupResult(res)) toast('success', t(act === 'lock' ? 'ed_group_locked' : 'ed_group_unlocked', res.count || 0));
            } else if (act === 'edit') {
                $('m-group-name').value = name;
                $('m-group-label').value = groupLabel(name);
                $('m-group-label').focus();
            } else if (act === 'delete') {
                // second click confirms
                if (b.dataset.confirm !== '1') {
                    b.dataset.confirm = '1';
                    b.textContent = t('ed_confirm');
                    return;
                }
                const res = await post('editor:groupDelete', { name: name });
                if (applyGroupResult(res)) toast('success', t('ed_group_deleted'));
            }
        }));
    });
}

function openGroups() {
    modal(t('ed_groups'), `
        <p class="muted small">${esc(t('ed_groups_note'))}</p>
        <div class="row tight group-new">
            <input type="text" id="m-group-name" maxlength="32" placeholder="${esc(t('ed_group_name_ph'))}">
            <input type="text" id="m-group-label" maxlength="64" placeholder="${esc(t('ed_group_label_ph'))}">
            <button type="button" class="primary small" id="m-group-save">${esc(t('ed_save'))}</button>
        </div>
        <div id="m-groups" class="group-list"></div>`, [{ label: t('ed_close'), fn: closeModal }]);
    renderGroupModal();
    $('m-group-save').addEventListener('click', async () => {
        const name = $('m-group-name').value.trim().toLowerCase();
        if (!name) return;
        const res = await post('editor:groupSave', { name: name, label: $('m-group-label').value.trim() });
        if (applyGroupResult(res)) {
            $('m-group-name').value = '';
            $('m-group-label').value = '';
            toast('success', t('ed_group_saved'));
        }
    });
}

$('ed-groups').addEventListener('click', openGroups);

async function restoreDoor(id) {
    const res = await post('editor:restore', { id: id });
    if (!res || !res.ok) { toast('error', errText(res)); return; }
    ed.doors = res.doors || ed.doors;
    ed.groups = res.groups || ed.groups;
    renderGroups();
    renderList();
    selectDoor(id);
    toast('success', t('ed_restored'));
}

// permission templates
function renderTemplates() {
    const sel = $('f-tpl');
    sel.innerHTML = ed.templates.length
        ? ed.templates.map((tp) => `<option value="${esc(tp.name)}">${esc(tp.name)}</option>`).join('')
        : `<option value="">${esc(t('ed_tpl_none'))}</option>`;
    $('f-tpl-apply').disabled = !ed.templates.length;
    $('f-tpl-del').disabled = !ed.templates.length;
}

$('f-tpl-apply').addEventListener('click', () => {
    const tp = ed.templates.find((x) => x.name === $('f-tpl').value);
    if (!tp || !ed.draft) return;
    const d = readForm();
    const keepPin = d.access.pin;
    d.access = clone(tp.access);
    d.access.pin = keepPin;
    renderForm();
    toast('success', t('ed_tpl_applied', tp.name));
});

$('f-tpl-save').addEventListener('click', () => {
    if (!ed.draft) return;
    modal(t('ed_tpl_save'), `<input type="text" id="m-tpl-name" maxlength="48" placeholder="${esc(t('ed_tpl_name_ph'))}">`, [
        { label: t('ed_cancel'), fn: closeModal },
        {
            label: t('ed_save'), cls: 'primary', fn: async () => {
                const name = $('m-tpl-name').value.trim();
                if (!name) return;
                const res = await post('editor:templateSave', { name: name, access: readForm().access });
                if (!res || !res.ok) { toast('error', errText(res)); return; }
                ed.templates = res.templates;
                renderTemplates();
                $('f-tpl').value = name;
                closeModal();
                toast('success', t('ed_tpl_saved'));
            },
        },
    ]);
    $('m-tpl-name').focus();
});

$('f-tpl-del').addEventListener('click', async (e) => {
    const b = e.currentTarget;
    if (b.dataset.confirm !== '1') {
        b.dataset.confirm = '1';
        b.textContent = t('ed_confirm');
        setTimeout(() => { b.dataset.confirm = ''; b.innerHTML = '&times;'; }, 3000);
        return;
    }
    const res = await post('editor:templateDelete', { name: $('f-tpl').value });
    b.dataset.confirm = '';
    b.innerHTML = '&times;';
    if (!res || !res.ok) { toast('error', errText(res)); return; }
    ed.templates = res.templates;
    renderTemplates();
});

// bulk edit
function renderBulkBar() {
    // forget doors that don't exist anymore
    [...ed.picked].forEach((id) => { if (!ed.doors.some((d) => d.id === id)) ed.picked.delete(id); });
    $('ed-bulk-bar').classList.toggle('hidden', ed.picked.size === 0);
    $('ed-bulk-count').textContent = t('ed_bulk_count', ed.picked.size);
}

$('ed-bulk-clear').addEventListener('click', () => { ed.picked.clear(); renderList(); });

function triSelect(id) {
    return `<select id="${id}"><option value="">${esc(t('ed_bulk_keep'))}</option><option value="on">${esc(t('ed_bulk_on'))}</option><option value="off">${esc(t('ed_bulk_off'))}</option></select>`;
}

$('ed-bulk').addEventListener('click', () => {
    const groupOpts = `<option value="__keep">${esc(t('ed_bulk_keep'))}</option><option value="">${esc(t('ed_no_group'))}</option>` +
        (ed.groups || []).map((g) => `<option value="${esc(g.name)}">${esc(g.label)}</option>`).join('');
    const soundOpts = `<option value="__keep">${esc(t('ed_bulk_keep'))}</option><option value="default">${esc(t('ed_sound_default'))}</option><option value="none">${esc(t('ed_sound_none'))}</option>` +
        (cfg.sounds || []).map((x) => `<option value="${esc(x.key)}">${esc(x.label)}</option>`).join('');
    const tplOpts = `<option value="">${esc(t('ed_bulk_keep'))}</option>` + ed.templates.map((tp) => `<option value="${esc(tp.name)}">${esc(tp.name)}</option>`).join('');

    modal(t('ed_bulk_title', ed.picked.size), `
        <div class="bulk-grid">
            <label><span>${esc(t('ed_group'))}</span><select id="b-group">${groupOpts}</select></label>
            <label><span>${esc(t('ed_tpl'))}</span><select id="b-tpl">${tplOpts}</select></label>
            <label><span>${esc(t('ed_bulk_add_job'))}</span><span class="row tight"><input type="text" id="b-job" placeholder="police"><input type="number" id="b-job-grade" class="tiny" min="0" value="0"></span></label>
            <label><span>${esc(t('ed_bulk_remove_job'))}</span><input type="text" id="b-job-remove" placeholder="police"></label>
            <label><span>${esc(t('ed_sound_unlock'))}</span><select id="b-sound-unlock">${soundOpts}</select></label>
            <label><span>${esc(t('ed_sound_lock'))}</span><select id="b-sound-lock">${soundOpts}</select></label>
            <label><span>${esc(t('ed_lockpick'))}</span>${triSelect('b-lockpick')}</label>
            <label><span>${esc(t('ed_breach'))}</span>${triSelect('b-breach')}</label>
            <label><span>${esc(t('ed_hack'))}</span>${triSelect('b-hack')}</label>
            <label><span>${esc(t('ed_alarm'))}</span>${triSelect('b-alarm')}</label>
            <label><span>${esc(t('ed_bell'))}</span>${triSelect('b-bell')}</label>
            <label><span>${esc(t('ed_remote'))}</span>${triSelect('b-remote')}</label>
        </div>
        <div id="m-report" class="report"></div>`, [
        { label: t('ed_close'), fn: closeModal },
        {
            label: t('ed_bulk_apply'), cls: 'primary', fn: async () => {
                const patch = {};
                if ($('b-group').value !== '__keep') patch.group = $('b-group').value;
                if ($('b-tpl').value) patch.templateName = $('b-tpl').value;
                if ($('b-job').value.trim()) patch.addJob = { name: $('b-job').value.trim().toLowerCase(), grade: parseInt($('b-job-grade').value, 10) || 0 };
                if ($('b-job-remove').value.trim()) patch.removeJob = $('b-job-remove').value.trim().toLowerCase();
                const snd = {};
                if ($('b-sound-lock').value !== '__keep') snd.lock = $('b-sound-lock').value;
                if ($('b-sound-unlock').value !== '__keep') snd.unlock = $('b-sound-unlock').value;
                if (Object.keys(snd).length) patch.sounds = snd;
                [['b-lockpick', 'lockpick'], ['b-breach', 'breach'], ['b-hack', 'hackable'], ['b-alarm', 'alarm'], ['b-bell', 'bell'], ['b-remote', 'remote']].forEach(([el, key]) => {
                    const v = $(el).value;
                    if (v) patch[key] = v === 'on';
                });
                if (!Object.keys(patch).length) return;
                const res = await post('editor:bulk', { ids: [...ed.picked], patch: patch });
                if (!res || !res.ok) { toast('error', errText(res)); return; }
                $('m-report').innerHTML = `<p><b>${esc(t('ed_bulk_done', res.done))}</b></p>` +
                    res.errors.map((e) => `<div class="e">! ${esc(e.id)} — ${esc(t(e.err))}${e.detail ? ' (' + esc(e.detail) + ')' : ''}</div>`).join('');
                ed.doors = res.doors || ed.doors;
                ed.groups = res.groups || ed.groups;
                renderGroups();
                renderList();
                if (ed.draft && !ed.draft.isNew && ed.picked.has(ed.draft.data.id)) selectDoor(ed.draft.data.id);
            },
        },
    ]);
});

function openEditor(data) {
    ed.doors = data.doors || [];
    ed.groups = data.groups || [];
    ed.templates = data.templates || [];
    ed.packs = data.packs || [];
    ed.picked.clear();
    renderTemplates();
    ed.supportsGangs = data.supportsGangs !== false;
    ed.supportsMetadata = data.supportsMetadata !== false;
    $('item-list').innerHTML = (data.items || []).map((i) => `<option value="${esc(i.name)}">${esc(i.label || '')}</option>`).join('');
    renderGroups();
    renderList();
    if (ed.draft && !ed.draft.isNew && !ed.doors.find((d) => d.id === ed.draft.data.id)) ed.draft = null;
    if (!ed.draft) {
        $('ed-form').classList.add('hidden');
        $('ed-empty').classList.remove('hidden');
    } else {
        renderForm();
    }
    $('editor').classList.remove('hidden');
}

window.addEventListener('message', (ev) => {
    const msg = ev.data || {};
    const d = msg.data || {};
    switch (msg.action) {
        case 'init':
            L = d.locale || {};
            cfg = Object.assign(cfg, d);
            document.documentElement.lang = L._lang || 'en';
            applyI18n();
            fillSoundSelects();
            renderGuide($('guide-inline'));
            break;
        case 'indicator': setIndicator(d); break;
        case 'indicatorDenied': flashDenied(); break;
        case 'toast': toast(d.type, d.text); break;
        case 'sound': playSound(d); break;
        case 'keypad:open': openKeypad(d); break;
        case 'keypad:close': closeKeypad(); break;
        case 'keypad:error':
            $('kp-error').textContent = d.text || '';
            pin = '';
            renderPin();
            document.querySelector('.keypad').classList.remove('shake');
            void document.querySelector('.keypad').offsetWidth;
            document.querySelector('.keypad').classList.add('shake');
            break;
        case 'editor:open': openEditor(d); break;
        case 'editor:close':
            $('editor').classList.add('hidden');
            closeModal();
            break;
        case 'editor:hide': $('editor').classList.add('hidden'); break;
        case 'editor:show':
            $('editor').classList.remove('hidden');
            if (d.leaves && ed.draft) {
                ed.draft.data.doors = d.leaves;
                renderLeaves();
                sendPreview();
            }
            if (d.selectId) selectDoor(d.selectId);
            break;
        case 'selection':
            $('selection').classList.toggle('hidden', !d.show);
            $('selection-text').textContent = d.text || '';
            $('selection-hint').textContent = d.hint || '';
            break;
    }
});

window.addEventListener('keydown', (e) => {
    const keypadOpen = !$('keypad').classList.contains('hidden');
    if (e.key === 'Escape') {
        if (!$('modal').classList.contains('hidden')) { closeModal(); return; }
        if (keypadOpen) closeKeypad();
        if (keypadOpen || !$('editor').classList.contains('hidden')) post('close');
        return;
    }
    if (keypadOpen) {
        // preventDefault so enter/space don't also "click" the last focused button
        if (/^[0-9]$/.test(e.key)) { e.preventDefault(); keypadPress(e.key); }
        else if (e.key === 'Backspace') { e.preventDefault(); keypadPress('del'); }
        else if (e.key === 'Enter') { e.preventDefault(); keypadPress('ok'); }
        else if (e.key === ' ') e.preventDefault();
    }
});

post('ready');
