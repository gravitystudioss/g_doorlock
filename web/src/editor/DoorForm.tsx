import { useRef, useState, type ReactNode } from 'react';
import type { Result } from '../contracts';
import { toast } from '../Hud';
import { t } from '../i18n';
import { nui, nuiResult } from '../nui';
import { settings } from '../settings';
import type { Draft, Tab } from './store';
import type { Access, DoorType, JobAccess } from '../types';
import { GroupOptions } from './Editor';
import {
  editor, errText, groupLabel, newDraft, openModal, saveDraft, sendPreview, setDoorState, soundOptions, updateDraft, buildDoor,
} from './store';

const GUIDE_STEPS = ['guide_1', 'guide_2', 'guide_3', 'guide_4', 'guide_5', 'guide_6', 'guide_7'];
const DAYS = [2, 3, 4, 5, 6, 7, 1]; // monday first, values are lua os.date wday
const TYPES: DoorType[] = ['single', 'double', 'gate', 'garage'];

export function Guide() {
  return (
    <>
      <ol className="guide">
        {GUIDE_STEPS.map((key) => <li key={key}>{t(key)}</li>)}
      </ol>
      <p className="muted small">{t('guide_tip')}</p>
    </>
  );
}

const TAB_ICONS: Record<Tab, ReactNode> = {
  general: <><path d="M4 21V5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v16" /><path d="M2 21h20" /><circle cx="15" cy="12" r="1" /></>,
  behaviour: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 3" /></>,
  access: <><rect x="4" y="10" width="16" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></>,
  breakin: <><path d="M14 4l6 6-9 9H5v-6z" /><path d="M12 6l6 6" /></>,
};

function tabDots(draft: Draft): Record<Tab, boolean> {
  const data = draft.data;
  return {
    general: false,
    behaviour: !!data.schedule || Number(data.autoLock) > 0 || !!data.sounds?.lock && data.sounds.lock !== 'default' || !!data.sounds?.unlock && data.sounds.unlock !== 'default',
    access: data.access.public || !!data.bell || (draft.hasPin && !draft.pinClear) || draft.pin !== '',
    breakin: !!data.lockpick || !!data.breach || !!data.alarm || !!data.hackable,
  };
}

function Switch({ label, checked, onChange }: { label: string; checked: boolean; onChange: (checked: boolean) => void }) {
  return (
    <label className="tg sw">
      <input type="checkbox" checked={checked} onChange={(event) => onChange(event.target.checked)} />
      <span>{label}</span>
    </label>
  );
}

function Section({ legend, hint, children }: { legend: string; hint?: string; children: ReactNode }) {
  return (
    <fieldset>
      <legend>{legend}</legend>
      {hint && <p className="hint">{hint}</p>}
      {children}
    </fieldset>
  );
}

const set = (change: (draft: Draft) => void) => updateDraft(change);
const setAccess = (change: (access: Access) => void) => updateDraft((draft) => change(draft.data.access));

export function DoorForm() {
  const { draft, tab, saving, supportsGangs, supportsMetadata, templates } = editor.use();
  const { sounds } = settings.use();
  const [identTarget, setIdentTarget] = useState('');
  const [templateName, setTemplateName] = useState('');
  const [confirmTemplateDelete, setConfirmTemplateDelete] = useState(false);
  const contentRef = useRef<HTMLDivElement>(null);
  if (!draft) return null;

  const data = draft.data;
  const access = data.access;
  const dots = tabDots(draft);
  const hasPin = draft.hasPin && !draft.pinClear;
  const selectedTemplate = templates.some((template) => template.name === templateName) ? templateName : templates[0]?.name || '';
  const subtitle = [data.id, t('ed_type_' + data.type), data.group ? groupLabel(data.group) : ''].filter(Boolean).join('  ·  ');

  const showTab = (name: Tab) => {
    editor.set({ tab: name });
    if (contentRef.current) contentRef.current.scrollTop = 0;
  };

  const pickLeaves = () => {
    const min = data.type === 'double' ? 2 : 1;
    const max = data.type === 'double' || data.type === 'gate' ? 2 : 1;
    nui('editor:select', { min, max });
  };

  const fetchIdentifier = async (target: string | null) => {
    const result = (await nui('editor:identifier', { target })) as { identifier?: string; name?: string } | null;
    if (!result || typeof result !== 'object' || !result.identifier) return toast('error', t('ed_id_not_found'));
    setAccess((next) => {
      next.identifiers = [...next.identifiers, result.identifier!];
    });
    toast('success', t('ed_ident_added', result.name || '', result.identifier));
  };

  const applyTemplate = () => {
    const template = templates.find((entry) => entry.name === selectedTemplate);
    if (!template) return;
    set((next) => {
      const copy = JSON.parse(JSON.stringify(template.access)) as Access;
      for (const key of ['jobs', 'gangs', 'identifiers', 'items'] as const) if (!Array.isArray(copy[key])) copy[key] = [];
      next.data.access = { ...copy, pin: next.data.access.pin };
    });
    toast('success', t('ed_tpl_applied', template.name));
  };

  const deleteTemplate = async () => {
    if (!confirmTemplateDelete) {
      setConfirmTemplateDelete(true);
      window.setTimeout(() => setConfirmTemplateDelete(false), 3000);
      return;
    }
    setConfirmTemplateDelete(false);
    const result = await nuiResult<Result & { templates?: typeof templates }>('editor:templateDelete', { name: selectedTemplate });
    if (!result?.ok) return toast('error', errText(result));
    editor.set({ templates: result.templates || [] });
  };

  const goTo = async () => {
    if (await nui('editor:goto', { id: data.id })) nui('close');
    else toast('error', t('err_generic'));
  };

  const updateRow = <K extends 'jobs' | 'gangs'>(kind: K, index: number, patch: Partial<JobAccess>) =>
    setAccess((next) => {
      next[kind] = next[kind].map((row, at) => (at === index ? { ...row, ...patch } : row));
    });

  const jobRows = (kind: 'jobs' | 'gangs') =>
    access[kind].map((row, index) => (
      <div className="r" key={index}>
        <input className="n" value={row.name} placeholder={t('ed_name_ph')} onChange={(event) => updateRow(kind, index, { name: event.target.value })} />
        <input className="g" type="number" min={0} value={row.grade} title={t('ed_grade_ph')} onChange={(event) => updateRow(kind, index, { grade: event.target.value })} />
        <RemoveRow onClick={() => setAccess((next) => { next[kind] = next[kind].filter((_, at) => at !== index); })} />
      </div>
    ));

  const soundSelect = (kind: 'lock' | 'unlock') => (
    <label>
      <span>{t('ed_sound_' + kind)}</span>
      <span className="row tight">
        <select
          className="sound-select"
          value={data.sounds?.[kind] || 'default'}
          onChange={(event) => set((next) => { next.data.sounds = { ...next.data.sounds, [kind]: event.target.value }; })}
        >
          {soundOptions(sounds).map((sound) => <option key={sound.key} value={sound.key}>{sound.label}</option>)}
        </select>
        <button type="button" className="small" aria-label={t('ed_sound_' + kind)} onClick={() => nui('editor:testSound', { kind, key: data.sounds?.[kind] || 'default' })}>{'▶'}</button>
      </span>
    </label>
  );

  const toggle = (key: 'alarm' | 'bell' | 'remote' | 'hackable' | 'hideIndicator' | 'locked' | 'persist', label: string) => (
    <Switch label={t(label)} checked={!!data[key]} onChange={(checked) => set((next) => { next.data[key] = checked; })} />
  );

  return (
    <form
      id="ed-form"
      autoComplete="off"
      onSubmit={(event) => {
        event.preventDefault();
        saveDraft();
      }}
    >
      <div className="form-top">
        <div className="form-head">
          <div className="form-title">
            <h2>{draft.isNew ? t('ed_new_draft') : data.name}</h2>
            <small>{subtitle}</small>
          </div>
          <span className={'badge' + (draft.isNew ? '' : draft.state ? ' bad' : ' ok')}>
            {draft.isNew ? t('ed_unsaved') : draft.state ? t('locked') : t('unlocked')}
          </span>
          {draft.temp && <span className="badge">{t('ed_temp')}</span>}
          {draft.broken && <span className="badge bad">{t('ed_broken')}</span>}
        </div>
        <nav className="tabs">
          {(Object.keys(TAB_ICONS) as Tab[]).map((name) => (
            <button
              type="button"
              key={name}
              className={'tab' + (tab === name ? ' active' : '') + (dots[name] ? ' on' : '')}
              aria-current={tab === name ? 'page' : 'false'}
              onClick={() => showTab(name)}
            >
              <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">{TAB_ICONS[name]}</svg>
              <span>{t('tab_' + name)}</span>
              <i className="dot" />
            </button>
          ))}
        </nav>
      </div>

      <div className="form-content" ref={contentRef}>
        {tab === 'general' && (
          <>
            <Section legend={t('ed_general')} hint={t('hint_general')}>
              <div className="grid3">
                <label>
                  <span>{t('ed_id')}</span>
                  <input type="text" autoComplete="off" maxLength={64} value={data.id} disabled={!draft.isNew} onChange={(event) => set((next) => { next.data.id = event.target.value; })} />
                </label>
                <label>
                  <span>{t('ed_name')}</span>
                  <input type="text" autoComplete="off" maxLength={64} value={data.name} onChange={(event) => set((next) => { next.data.name = event.target.value; })} />
                </label>
                <label>
                  <span>{t('ed_group')}</span>
                  <select value={data.group || ''} onChange={(event) => set((next) => { next.data.group = event.target.value; })}>
                    <option value="">{t('ed_no_group')}</option>
                    <GroupOptions />
                  </select>
                </label>
                <label>
                  <span>{t('ed_type')}</span>
                  <select value={data.type} onChange={(event) => set((next) => { next.data.type = event.target.value as DoorType; })}>
                    {TYPES.map((type) => <option key={type} value={type}>{t('ed_type_' + type)}</option>)}
                  </select>
                </label>
                <label>
                  <span>{t('ed_bucket')}</span>
                  <input type="number" min={0} step={1} value={data.bucket} onChange={(event) => set((next) => { next.data.bucket = event.target.value; })} />
                </label>
              </div>
            </Section>

            <Section legend={t('ed_leaves')} hint={t('hint_leaves')}>
              <div className="leaves">
                {data.doors.length ? (
                  data.doors.map((leaf, index) => (
                    <div className="leaf" key={index}>
                      <b>#{index + 1}</b> model {String(leaf.model)} {'·'} {(+leaf.coords.x).toFixed(2)}, {(+leaf.coords.y).toFixed(2)}, {(+leaf.coords.z).toFixed(2)} {'·'} h {(+leaf.heading).toFixed(1)}
                    </div>
                  ))
                ) : (
                  <div className="leaf">{t('ed_need_leaves')}</div>
                )}
              </div>
              <div className="row">
                <button type="button" onClick={pickLeaves}>{t('ed_reselect')}</button>
                <button type="button" onClick={sendPreview}>{t('ed_preview')}</button>
              </div>
            </Section>
          </>
        )}

        {tab === 'behaviour' && (
          <>
            <Section legend={t('ed_behaviour')} hint={t('hint_behaviour')}>
              <div className="grid3">
                <label>
                  <span>{t('ed_interact')}</span>
                  <input type="number" min={0.5} step={0.1} value={data.interactDistance} onChange={(event) => { set((next) => { next.data.interactDistance = event.target.value; }); sendPreview(); }} />
                </label>
                <label>
                  <span>{t('ed_autodist')}</span>
                  <input type="number" min={0} step={0.5} value={data.autoDistance} onChange={(event) => { set((next) => { next.data.autoDistance = event.target.value; }); sendPreview(); }} />
                </label>
                <label>
                  <span>{t('ed_autolock')}</span>
                  <input type="number" min={0} max={3600} step={1} value={data.autoLock} onChange={(event) => set((next) => { next.data.autoLock = event.target.value; })} />
                </label>
              </div>
              <div className="toggles">
                {toggle('locked', 'ed_locked')}
                {toggle('persist', 'ed_persist')}
                {toggle('hideIndicator', 'ed_hide_ind')}
                {toggle('remote', 'ed_remote')}
              </div>
            </Section>

            <Section legend={t('ed_sounds')} hint={t('hint_sounds')}>
              <div className="grid3">
                {soundSelect('unlock')}
                {soundSelect('lock')}
              </div>
            </Section>

            <Section legend={t('ed_schedule')} hint={t('hint_schedule')}>
              <div className="row">
                <Switch
                  label={t('ed_sched_enable')}
                  checked={!!data.schedule}
                  onChange={(checked) => set((next) => { next.data.schedule = checked ? next.schedule : undefined; })}
                />
                <label className="inline">
                  <span>{t('ed_sched_open')}</span>
                  <input type="time" className="time" value={draft.schedule.open} onChange={(event) => set((next) => { next.schedule = { ...next.schedule, open: event.target.value }; })} />
                </label>
                <label className="inline">
                  <span>{t('ed_sched_close')}</span>
                  <input type="time" className="time" value={draft.schedule.close} onChange={(event) => set((next) => { next.schedule = { ...next.schedule, close: event.target.value }; })} />
                </label>
              </div>
              <div className="row days">
                {DAYS.map((day) => (
                  <label className="tg day" key={day}>
                    <input
                      type="checkbox"
                      checked={draft.schedule.days.includes(day)}
                      onChange={(event) => set((next) => {
                        const days = next.schedule.days.filter((entry) => entry !== day);
                        next.schedule = { ...next.schedule, days: event.target.checked ? [...days, day] : days };
                      })}
                    />
                    <span>{t('day_' + day)}</span>
                  </label>
                ))}
              </div>
              <p className="muted small">{t('ed_sched_note')}</p>
            </Section>
          </>
        )}

        {tab === 'access' && (
          <>
            <Section legend={t('ed_access')} hint={t('hint_access')}>
              <div className="row">
                <label className="inline">
                  <span>{t('ed_mode')}</span>
                  <select value={access.mode} onChange={(event) => setAccess((next) => { next.mode = event.target.value as Access['mode']; })}>
                    <option value="any">{t('ed_mode_any')}</option>
                    <option value="all">{t('ed_mode_all')}</option>
                  </select>
                </label>
                <Switch label={t('ed_public')} checked={access.public} onChange={(checked) => setAccess((next) => { next.public = checked; })} />
                <Switch label={t('ed_admin')} checked={access.admin} onChange={(checked) => setAccess((next) => { next.admin = checked; })} />
                {toggle('bell', 'ed_bell')}
              </div>

              <div className="row tight tpl-row">
                <span className="muted small">{t('ed_tpl')}</span>
                <select value={selectedTemplate} onChange={(event) => setTemplateName(event.target.value)}>
                  {templates.length ? templates.map((template) => <option key={template.name} value={template.name}>{template.name}</option>) : <option value="">{t('ed_tpl_none')}</option>}
                </select>
                <button type="button" className="small" disabled={!templates.length} onClick={applyTemplate}>{t('ed_tpl_apply')}</button>
                <button type="button" className="small" onClick={() => openModal('templateSave')}>{t('ed_tpl_save')}</button>
                <button type="button" className="small danger-ghost" aria-label={t('ed_delete')} disabled={!templates.length} onClick={deleteTemplate}>
                  {confirmTemplateDelete ? t('ed_confirm') : '×'}
                </button>
              </div>

              <div className="sub">
                <div className="sub-head"><b>{t('ed_jobs')}</b><AddRow label={t('ed_jobs')} onClick={() => setAccess((next) => { next.jobs = [...next.jobs, { name: '', grade: 0 }]; })} /></div>
                <div className="rows">{jobRows('jobs')}</div>
              </div>
              <div className="sub">
                <div className="sub-head"><b>{t('ed_gangs')}</b><AddRow label={t('ed_gangs')} onClick={() => setAccess((next) => { next.gangs = [...next.gangs, { name: '', grade: 0 }]; })} /></div>
                {!supportsGangs && <div className="muted small">{t('ed_gangs_na')}</div>}
                <div className="rows">{jobRows('gangs')}</div>
              </div>
              <div className="sub">
                <div className="sub-head">
                  <b>{t('ed_identifiers')}</b>
                  <span className="row tight">
                    <input type="number" className="tiny" placeholder={t('ed_sid_prompt')} value={identTarget} onChange={(event) => setIdentTarget(event.target.value)} />
                    <button type="button" className="small" onClick={() => (identTarget ? fetchIdentifier(identTarget) : toast('error', t('ed_id_not_found')))}>{t('ed_add_id')}</button>
                    <button type="button" className="small" onClick={() => fetchIdentifier(null)}>{t('ed_add_me')}</button>
                    <AddRow label={t('ed_identifiers')} onClick={() => setAccess((next) => { next.identifiers = [...next.identifiers, '']; })} />
                  </span>
                </div>
                <div className="rows">
                  {access.identifiers.map((value, index) => (
                    <div className="r" key={index}>
                      <input className="n" value={value} placeholder={t('ed_ident_ph')} onChange={(event) => setAccess((next) => { next.identifiers = next.identifiers.map((entry, at) => (at === index ? event.target.value : entry)); })} />
                      <RemoveRow onClick={() => setAccess((next) => { next.identifiers = next.identifiers.filter((_, at) => at !== index); })} />
                    </div>
                  ))}
                </div>
              </div>
              <div className="sub">
                <div className="sub-head"><b>{t('ed_items')}</b><AddRow label={t('ed_items')} onClick={() => setAccess((next) => { next.items = [...next.items, { name: '' }]; })} /></div>
                {!supportsMetadata && <div className="muted small">{t('ed_meta_na')}</div>}
                <div className="rows">
                  {access.items.map((item, index) => {
                    const updateItem = (patch: Partial<typeof item>) =>
                      setAccess((next) => { next.items = next.items.map((entry, at) => (at === index ? { ...entry, ...patch } : entry)); });
                    return (
                      <div className="r" key={index}>
                        <input className="n" list="item-list" value={item.name} placeholder={t('ed_item_name')} onChange={(event) => updateItem({ name: event.target.value })} />
                        <input className="m" value={item.metadata || ''} placeholder={t('ed_item_meta')} onChange={(event) => updateItem({ metadata: event.target.value })} />
                        <label className="tg">
                          <input type="checkbox" checked={!!item.remove} onChange={(event) => updateItem({ remove: event.target.checked })} />
                          <span>{t('ed_item_remove')}</span>
                        </label>
                        <RemoveRow onClick={() => setAccess((next) => { next.items = next.items.filter((_, at) => at !== index); })} />
                      </div>
                    );
                  })}
                </div>
              </div>
            </Section>

            <Section legend={t('ed_pin')} hint={t('hint_pin')}>
              <div className="row">
                <span className={'badge' + (hasPin ? ' ok' : '')}>{hasPin ? t('ed_pin_set') : t('ed_pin_none')}</span>
                <input
                  type="password"
                  id="f-pin"
                  autoComplete="new-password"
                  inputMode="numeric"
                  maxLength={8}
                  placeholder={t('ed_pin_new')}
                  value={draft.pin}
                  onChange={(event) => set((next) => { next.pin = event.target.value; })}
                />
                <button type="button" className="danger-ghost" disabled={!hasPin} onClick={() => set((next) => { next.pinClear = true; next.pin = ''; })}>
                  {t('ed_pin_remove')}
                </button>
              </div>
            </Section>
          </>
        )}

        {tab === 'breakin' && (
          <Section legend={t('ed_breakin')} hint={t('hint_breakin')}>
            <div className="opt-cards">
              <div className={'opt-card' + (data.lockpick ? ' on' : '')}>
                <Switch label={t('ed_lockpick')} checked={!!data.lockpick} onChange={(checked) => set((next) => { next.data.lockpick = checked ? { enabled: true, difficulty: next.difficulty } : undefined; })} />
                <p className="hint">{t('opt_lockpick')}</p>
                <label>
                  <span>{t('ed_difficulty')}</span>
                  <select value={draft.difficulty} disabled={!data.lockpick} onChange={(event) => set((next) => { next.difficulty = event.target.value; })}>
                    {['easy', 'medium', 'hard'].map((level) => <option key={level} value={level}>{t('ed_diff_' + level)}</option>)}
                  </select>
                </label>
              </div>
              <div className={'opt-card' + (data.breach ? ' on' : '')}>
                <Switch label={t('ed_breach')} checked={!!data.breach} onChange={(checked) => set((next) => { next.data.breach = checked ? { enabled: true } : undefined; })} />
                <p className="hint">{t('opt_breach')}</p>
              </div>
              <div className={'opt-card' + (data.hackable ? ' on' : '')}>
                {toggle('hackable', 'ed_hack')}
                <p className="hint">{t('opt_hack')}</p>
              </div>
              <div className={'opt-card' + (data.alarm ? ' on' : '')}>
                {toggle('alarm', 'ed_alarm')}
                <p className="hint">{t('opt_alarm')}</p>
              </div>
            </div>
          </Section>
        )}
      </div>

      <div className="form-actions">
        <button type="submit" className="primary" disabled={saving} aria-busy={saving || undefined}>{t('ed_save')}</button>
        <button type="button" disabled={draft.isNew} onClick={() => newDraft(buildDoor(draft))}>{t('ed_duplicate')}</button>
        <button type="button" disabled={draft.isNew} onClick={goTo}>{t('ed_goto')}</button>
        <button type="button" disabled={draft.isNew} onClick={setDoorState}>{draft.state ? t('ed_unlock_now') : t('ed_lock_now')}</button>
        <span className="grow" />
        <button type="button" className="danger" disabled={draft.isNew} onClick={() => openModal('delete')}>{t('ed_delete')}</button>
      </div>
    </form>
  );
}

function AddRow({ label, onClick }: { label: string; onClick: () => void }) {
  return <button type="button" className="small" aria-label={label} onClick={onClick}>+</button>;
}

function RemoveRow({ onClick }: { onClick: () => void }) {
  return <button type="button" className="x" aria-label={t('ed_delete')} onClick={onClick}>&times;</button>;
}
