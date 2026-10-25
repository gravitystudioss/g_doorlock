import type { DoorsResult, MessageOf, Result } from '../contracts';
import { toast } from '../Hud';
import { t } from '../i18n';
import { nui, nuiResult } from '../nui';
import { settings } from '../settings';
import { createStore } from '../store';
import type { Door, DoorEntry, DoorType, Group, Pack, Schedule, SoundChoice, Template } from '../types';

export type Tab = 'general' | 'behaviour' | 'access' | 'breakin';
export type ModalKind = 'delete' | 'export' | 'import' | 'groups' | 'guide' | 'templateSave' | 'bulk';

export interface Draft {
  isNew: boolean;
  rev?: number;
  hasPin: boolean;
  state: boolean;
  temp?: boolean;
  broken?: boolean;
  data: Door;
  // Form fields kept even while their option is off
  schedule: Schedule;
  difficulty: string;
  pin: string;
  pinClear: boolean;
}

export const editor = createStore({
  visible: false,
  doors: [] as DoorEntry[],
  groups: [] as Group[],
  templates: [] as Template[],
  packs: [] as Pack[],
  items: [] as { name: string; label?: string }[],
  supportsGangs: true,
  supportsMetadata: true,
  picked: [] as string[],
  search: '',
  groupFilter: '',
  draft: null as Draft | null,
  tab: 'general' as Tab,
  modal: null as ModalKind | null,
  saving: false,
});

const clone = <T,>(value: T): T => JSON.parse(JSON.stringify(value));

export const errText = (result: Result | null) =>
  result ? t(result.err || 'err_generic') + (result.detail ? ` (${String(result.detail)})` : '') : t('err_generic');

export const groupLabel = (name: string) => editor.get().groups.find((group) => group.name === name)?.label || name;

export function soundOptions(sounds: SoundChoice[]) {
  return [{ key: 'default', label: t('ed_sound_default') }, { key: 'none', label: t('ed_sound_none') }, ...sounds];
}

function blankDoor(type: DoorType): Door {
  const defaults = settings.get().defaults;
  return {
    id: '', name: '', group: '', type, bucket: 0, doors: [],
    locked: defaults.locked !== false, persist: defaults.persist !== false, autoLock: defaults.autoLock || 0,
    interactDistance: defaults.interact || 2.0, autoDistance: defaults.auto || 0, hideIndicator: false,
    access: { mode: defaults.mode || 'any', public: false, admin: true, pin: false, jobs: [], gangs: [], identifiers: [], items: [] },
  };
}

// Lua encodes empty lists as {}
const asList = <T,>(value: T[] | undefined): T[] => (Array.isArray(value) ? value : []);

function draftFrom(data: Door, extra: Partial<Draft>): Draft {
  const access = data.access || ({} as Door['access']);
  data.doors = asList(data.doors);
  data.access = {
    ...access,
    mode: access.mode || 'any',
    jobs: asList(access.jobs), gangs: asList(access.gangs), identifiers: asList(access.identifiers), items: asList(access.items),
  };
  return {
    isNew: false, hasPin: false, state: data.locked, ...extra, data,
    schedule: { enabled: true, open: data.schedule?.open || '08:00', close: data.schedule?.close || '20:00', days: asList(data.schedule?.days) },
    difficulty: data.lockpick?.difficulty || 'medium',
    pin: '',
    pinClear: false,
  };
}

export function matchSearch(door: DoorEntry, query: string) {
  const match = query.match(/^(job|gang|item|group|type|id):\s*(.+)$/);
  if (!match) {
    return door.id.toLowerCase().includes(query) || (door.name || '').toLowerCase().includes(query) || (door.group || '').toLowerCase().includes(query);
  }
  const value = match[2];
  const access = door.access || ({} as Door['access']);
  if (match[1] === 'job') return asList(access.jobs).some((job) => job.name.toLowerCase() === value);
  if (match[1] === 'gang') return asList(access.gangs).some((gang) => gang.name.toLowerCase() === value);
  if (match[1] === 'item') return asList(access.items).some((item) => item.name.toLowerCase() === value || (item.metadata || '').toLowerCase() === value);
  if (match[1] === 'group') return (door.group || '') === value;
  if (match[1] === 'type') return door.type === value;
  return door.id.toLowerCase() === value;
}

export function filteredDoors() {
  const { doors, search, groupFilter } = editor.get();
  const query = search.trim().toLowerCase();
  return doors.filter((door) => (!groupFilter || door.group === groupFilter) && (!query || matchSearch(door, query)));
}

export function updateDraft(change: (draft: Draft) => void) {
  const current = editor.get().draft;
  if (!current) return;
  const next = { ...current, data: { ...current.data, access: { ...current.data.access } } };
  change(next);
  editor.set({ draft: next });
}

export function sendPreview() {
  const draft = editor.get().draft;
  if (!draft) return;
  nui('editor:preview', {
    leaves: draft.data.doors || [],
    interact: parseFloat(String(draft.data.interactDistance)) || 0,
    auto: parseFloat(String(draft.data.autoDistance)) || 0,
  });
}

export function selectDoor(id: string) {
  const door = editor.get().doors.find((entry) => entry.id === id);
  if (!door) return;
  const { rev, hasPin, state, tempAccess, broken, ...data } = clone(door);
  editor.set({ draft: draftFrom(data, { rev, hasPin: !!hasPin, state: !!state, temp: tempAccess, broken }) });
  sendPreview();
}

export function newDraft(template?: Door) {
  let data: Door;
  if (template) {
    data = clone(template);
    data.id = (template.id + '_copy').slice(0, 64);
    data.name = template.name + ' (copy)';
    data.doors = [];
    data.access.pin = false;
  } else {
    data = blankDoor('single');
  }
  editor.set({ draft: { ...draftFrom(data, { isNew: true, state: data.locked }) }, tab: 'general' });
  nui('editor:preview', { leaves: [] });
}

const slug = (value: string) =>
  String(value || '').toLowerCase().replace(/[^a-z0-9_-]+/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '').slice(0, 48);

// The door as the server expects it: empty rows dropped, off options removed
export function buildDoor(draft: Draft): Door {
  const data = clone(draft.data);
  const access = data.access;
  data.id = draft.isNew ? data.id.trim().toLowerCase() : data.id;
  data.name = data.name.trim();
  data.group = data.group || undefined;
  data.lockpick = data.lockpick ? { enabled: true, difficulty: draft.difficulty } : undefined;
  data.schedule = data.schedule ? { ...draft.schedule, enabled: true } : undefined;
  data.bucket = parseInt(String(data.bucket), 10) || 0;
  data.interactDistance = parseFloat(String(data.interactDistance)) || 2.0;
  data.autoDistance = parseFloat(String(data.autoDistance)) || 0;
  data.autoLock = parseInt(String(data.autoLock), 10) || 0;
  for (const key of ['alarm', 'bell', 'remote', 'hackable'] as const) data[key] = data[key] || undefined;
  access.jobs = access.jobs.filter((job) => job.name.trim()).map((job) => ({ name: job.name.trim(), grade: parseInt(String(job.grade), 10) || 0 }));
  access.gangs = access.gangs.filter((gang) => gang.name.trim()).map((gang) => ({ name: gang.name.trim(), grade: parseInt(String(gang.grade), 10) || 0 }));
  access.identifiers = access.identifiers.map((value) => value.trim()).filter(Boolean);
  access.items = access.items
    .filter((item) => item.name.trim())
    .map((item) => ({ name: item.name.trim(), metadata: item.metadata?.trim() || undefined, remove: !!item.remove }));
  const sounds: Door['sounds'] = {};
  if (data.sounds?.lock && data.sounds.lock !== 'default') sounds.lock = data.sounds.lock;
  if (data.sounds?.unlock && data.sounds.unlock !== 'default') sounds.unlock = data.sounds.unlock;
  data.sounds = sounds;
  return data;
}

function upsertDoor(door: DoorEntry) {
  const doors = editor.get().doors.filter((entry) => entry.id !== door.id);
  doors.push(door);
  doors.sort((a, b) => a.id.localeCompare(b.id));
  editor.set({ doors });
}

// Lists returned after group, import and bulk operations
export function applyLists(result: DoorsResult) {
  const current = editor.get();
  const doors = result.doors || current.doors;
  editor.set({
    doors,
    groups: result.groups || current.groups,
    picked: current.picked.filter((id) => doors.some((door) => door.id === id)),
  });
}

export async function saveDraft() {
  const { draft, saving } = editor.get();
  if (saving || !draft) return;
  const { pinMin, pinMax } = settings.get();
  const data = buildDoor(draft);
  if (!data.id) data.id = slug(data.name);
  if (!data.id) return toast('error', t('err_invalid_id'));
  if (!data.doors.length) return toast('error', t('ed_need_leaves'));

  let pin: { set?: string; clear?: boolean } | null = null;
  const newPin = draft.pin.trim();
  if (newPin) {
    if (!/^\d+$/.test(newPin) || newPin.length < pinMin || newPin.length > pinMax) {
      return toast('error', t('err_pin_format') + ` (${pinMin}-${pinMax})`);
    }
    pin = { set: newPin };
  } else if (draft.pinClear) {
    pin = { clear: true };
  }
  data.access.pin = !!pin?.set || (draft.hasPin && !draft.pinClear);

  editor.set({ saving: true });
  const result = await nuiResult<DoorsResult & { door?: DoorEntry }>('editor:save', { door: data, isNew: draft.isNew, rev: draft.rev, pin });
  editor.set({ saving: false });
  if (!result?.ok || !result.door) return toast('error', errText(result));
  upsertDoor(result.door);
  if (result.groups) editor.set({ groups: result.groups });
  toast('success', t('ed_saved'));
  selectDoor(result.door.id);
}

export async function restoreDoor(id: string) {
  const result = await nuiResult<DoorsResult>('editor:restore', { id });
  if (!result?.ok) return toast('error', errText(result));
  applyLists(result);
  selectDoor(id);
  toast('success', t('ed_restored'));
}

export async function setDoorState() {
  const draft = editor.get().draft;
  if (!draft) return;
  const locked = !draft.state;
  const result = await nuiResult('editor:setState', { id: draft.data.id, locked });
  if (!result?.ok) return toast('error', errText(result));
  updateDraft((next) => {
    next.state = locked;
  });
  editor.set((current) => ({ doors: current.doors.map((door) => (door.id === draft.data.id ? { ...door, state: locked } : door)) }));
}

export function openEditor(data: MessageOf<'editor:open'>) {
  const doors = data.doors || [];
  const draft = editor.get().draft;
  editor.set({
    visible: true,
    doors,
    groups: data.groups || [],
    templates: data.templates || [],
    packs: data.packs || [],
    items: data.items || [],
    supportsGangs: data.supportsGangs !== false,
    supportsMetadata: data.supportsMetadata !== false,
    picked: [],
    draft: draft && !draft.isNew && !doors.some((door) => door.id === draft.data.id) ? null : draft,
  });
}

export function showEditor(data: MessageOf<'editor:show'>) {
  editor.set({ visible: true });
  if (data.leaves && editor.get().draft) {
    updateDraft((draft) => {
      draft.data.doors = data.leaves!;
    });
    sendPreview();
  }
  if (data.selectId) selectDoor(data.selectId);
}

export const closeEditor = () => editor.set({ visible: false, modal: null });
export const hideEditor = () => editor.set({ visible: false });
export const openModal = (modal: ModalKind) => editor.set({ modal });
export const closeModal = () => editor.set({ modal: null });
