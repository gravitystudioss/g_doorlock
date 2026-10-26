import { useEffect, useState, type ReactNode } from 'react';
import type { DoorsResult, ReportResult, Result } from '../contracts';
import { toast } from '../Hud';
import { t } from '../i18n';
import { nui, nuiResult } from '../nui';
import { settings } from '../settings';
import type { ReportError, Template } from '../types';
import { Guide } from './DoorForm';
import {
  applyLists, buildDoor, closeModal, editor, errText, filteredDoors, groupLabel, restoreDoor, selectDoor, soundOptions,
} from './store';

interface Action {
  label: string;
  className?: string;
  disabled?: boolean;
  run: () => void;
}

function Modal({ title, actions, children }: { title: string; actions: Action[]; children: ReactNode }) {
  return (
    <div id="modal" className="overlay top">
      <div className="card modal" role="dialog" aria-modal="true" aria-labelledby="m-title">
        <h3 id="m-title">{title}</h3>
        <div id="m-body">{children}</div>
        <div className="form-actions" id="m-actions">
          {actions.map((action) => (
            <button key={action.label} type="button" className={action.className} disabled={action.disabled} onClick={action.run}>
              {action.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

const closeAction = (): Action => ({ label: t('ed_close'), run: closeModal });

// Runs one request at a time for the buttons of a modal
function useBusy() {
  const [busy, setBusy] = useState(false);
  const run = async (task: () => Promise<void>) => {
    if (busy) return;
    setBusy(true);
    try {
      await task();
    } finally {
      setBusy(false);
    }
  };
  return [busy, run] as const;
}

function errorLine(error: ReportError, key: number) {
  return (
    <div className="e" key={key}>
      ! {error.id || '#' + error.index} - {t(error.err)}{error.detail ? ` (${error.detail})` : ''}
    </div>
  );
}

function DeleteModal() {
  const [deletedId, setDeletedId] = useState<string | null>(null);
  const draft = editor.use().draft;
  const [busy, run] = useBusy();
  if (deletedId) return <Modal title={t('ed_deleted')} actions={[{ label: t('ed_undo'), run: () => { restoreDoor(deletedId); closeModal(); } }, { label: t('ed_cancel'), run: closeModal }]}><p>{t('ed_deleted')}</p></Modal>;
  if (!draft) return null;
  const { id, name } = draft.data;
  const remove = () =>
    run(async () => {
      const result = await nuiResult('editor:delete', { id });
      if (!result?.ok) return toast('error', errText(result));
      editor.set((current) => ({ doors: current.doors.filter((door) => door.id !== id), draft: null, picked: current.picked.filter((entry) => entry !== id) }));
      nui('editor:preview', { leaves: [] });
      toast('success', t('ed_deleted'));
      setDeletedId(id);
    });
  return (
    <Modal title={t('ed_delete')} actions={[{ label: t('ed_cancel'), run: closeModal }, { label: t('ed_delete'), className: 'danger', disabled: busy, run: remove }]}>
      <p>{t('ed_delete_q', name)}</p>
    </Modal>
  );
}

function ExportModal() {
  const [result, setResult] = useState<(Result & { json?: string; count?: number; file?: string }) | null>(null);
  useEffect(() => {
    let active = true;
    nuiResult<Result & { json?: string; count?: number; file?: string }>('editor:export', { ids: filteredDoors().map((door) => door.id) }).then((answer) => {
      if (!active) return;
      if (!answer?.json) {
        closeModal();
        return toast('error', errText(answer));
      }
      setResult(answer);
    });
    return () => {
      active = false;
    };
  }, []);
  if (!result?.json) return null;
  const json = result.json;
  return (
    <Modal
      title={t('ed_export_title', result.count)}
      actions={[
        closeAction(),
        { label: t('ed_copy'), className: 'primary', run: () => { nui('editor:copy', { text: json }); toast('success', t('ed_copied')); } },
      ]}
    >
      <textarea readOnly value={json} />
      <p className="muted small">{result.file ? t('ed_export_file', result.file) : t('ed_export_nofile')}</p>
    </Modal>
  );
}

function ImportModal() {
  const { packs } = editor.use();
  const [text, setText] = useState('');
  const [overwrite, setOverwrite] = useState(false);
  const [pack, setPack] = useState(packs[0]?.file || '');
  const [report, setReport] = useState<ReportResult | null>(null);
  const [busy, run] = useBusy();

  const send = (event: string, payload: object) =>
    run(async () => {
      const result = await nuiResult<ReportResult>(event, { ...payload, overwrite });
      if (!result?.ok) return toast('error', errText(result));
      setReport(result);
      applyLists(result);
    });

  return (
    <Modal
      title={t('ed_import_title')}
      actions={[closeAction(), { label: t('ed_import_run'), className: 'primary', disabled: busy, run: () => text.trim() && send('editor:import', { text: text.trim() }) }]}
    >
      <p className="muted small">{t('ed_import_ph')}</p>
      <textarea placeholder='{"doors":[...]}' value={text} onChange={(event) => setText(event.target.value)} />
      <label className="tg" style={{ marginTop: '.5rem' }}>
        <input type="checkbox" checked={overwrite} onChange={(event) => setOverwrite(event.target.checked)} />
        <span>{t('ed_overwrite')}</span>
      </label>
      <div className="row tight migrate">
        <span className="muted small">{t('ed_migrate')}</span>
        <button type="button" className="small" disabled={busy} onClick={() => send('editor:migrate', { from: 'ox' })}>ox_doorlock</button>
        <button type="button" className="small" disabled={busy} onClick={() => send('editor:migrate', { from: 'qb' })}>qb-doorlock</button>
      </div>
      <div className="row tight migrate">
        <span className="muted small">{t('ed_packs')}</span>
        <select value={pack} onChange={(event) => setPack(event.target.value)}>
          {packs.map((entry) => <option key={entry.file} value={entry.file}>{entry.label} ({entry.count})</option>)}
        </select>
        <button type="button" className="small" disabled={!packs.length || busy} onClick={() => send('editor:importPack', { file: pack })}>{t('ed_import_run')}</button>
      </div>
      <div className="report">
        {report && (
          <>
            <p><b>{t('ed_import_res', report.created.length, report.updated.length, report.skipped.length, report.errors.length)}</b></p>
            {report.created.map((id) => <div className="c" key={'c' + id}>+ {id} - {t('ed_created')}</div>)}
            {report.updated.map((id) => <div className="c" key={'u' + id}>~ {id} - {t('ed_updated')}</div>)}
            {report.skipped.map((entry) => <div className="s" key={'s' + entry.id}>= {entry.id} - {t(entry.err)}</div>)}
            {report.errors.map(errorLine)}
          </>
        )}
      </div>
    </Modal>
  );
}

function GroupsModal() {
  const { groups } = editor.use();
  const [name, setName] = useState('');
  const [label, setLabel] = useState('');
  const [confirmDelete, setConfirmDelete] = useState('');
  const [busy, run] = useBusy();

  const send = (event: string, payload: object, done: (result: DoorsResult & { count?: number }) => void) =>
    run(async () => {
      const result = await nuiResult<DoorsResult & { count?: number }>(event, payload);
      if (!result?.ok) return toast('error', errText(result));
      applyLists(result);
      // Keep the open draft in sync with group changes
      const draft = editor.get().draft;
      const door = draft && !draft.isNew && editor.get().doors.find((entry) => entry.id === draft.data.id);
      if (draft && door) editor.set({ draft: { ...draft, state: !!door.state, data: { ...draft.data, group: door.group } } });
      done(result);
    });

  const save = () => {
    const groupName = name.trim().toLowerCase();
    if (!groupName) return;
    send('editor:groupSave', { name: groupName, label: label.trim() }, () => {
      setName('');
      setLabel('');
      toast('success', t('ed_group_saved'));
    });
  };

  return (
    <Modal title={t('ed_groups')} actions={[closeAction()]}>
      <p className="muted small">{t('ed_groups_note')}</p>
      <div className="row tight group-new">
        <input type="text" maxLength={32} placeholder={t('ed_group_name_ph')} value={name} onChange={(event) => setName(event.target.value)} />
        <input type="text" maxLength={64} placeholder={t('ed_group_label_ph')} value={label} onChange={(event) => setLabel(event.target.value)} />
        <button type="button" className="primary small" disabled={busy} onClick={save}>{t('ed_save')}</button>
      </div>
      <div className="group-list">
        {groups.length ? (
          groups.map((group) => (
            <div className="group-row" key={group.name}>
              <div className="meta">
                <b>{group.label}</b>
                <small>{group.name} {'·'} {t('ed_group_doors', group.count)}</small>
              </div>
              {(['unlock', 'lock'] as const).map((act) => (
                <button
                  type="button"
                  className="small"
                  key={act}
                  disabled={busy}
                  onClick={() => send('editor:groupState', { name: group.name, locked: act === 'lock' }, (result) =>
                    toast('success', t(act === 'lock' ? 'ed_group_locked' : 'ed_group_unlocked', result.count || 0)))}
                >
                  {t('ed_group_' + act)}
                </button>
              ))}
              <button type="button" className="small" aria-label={t('ed_groups')} onClick={() => { setName(group.name); setLabel(groupLabel(group.name)); }}>{'✎'}</button>
              <button
                type="button"
                className="small danger-ghost"
                aria-label={t('ed_delete')}
                disabled={busy}
                onClick={() => {
                  // second click confirms
                  if (confirmDelete !== group.name) return setConfirmDelete(group.name);
                  send('editor:groupDelete', { name: group.name }, () => toast('success', t('ed_group_deleted')));
                }}
              >
                {confirmDelete === group.name ? t('ed_confirm') : '×'}
              </button>
            </div>
          ))
        ) : (
          <p className="muted small">{t('ed_group_empty')}</p>
        )}
      </div>
    </Modal>
  );
}

function TemplateSaveModal() {
  const [name, setName] = useState('');
  const [busy, run] = useBusy();
  const save = () =>
    run(async () => {
      const draft = editor.get().draft;
      if (!name.trim() || !draft) return;
      const result = await nuiResult<Result & { templates?: Template[] }>('editor:templateSave', { name: name.trim(), access: buildDoor(draft).access });
      if (!result?.ok) return toast('error', errText(result));
      editor.set({ templates: result.templates || [], modal: null });
      toast('success', t('ed_tpl_saved'));
    });
  return (
    <Modal title={t('ed_tpl_save')} actions={[{ label: t('ed_cancel'), run: closeModal }, { label: t('ed_save'), className: 'primary', disabled: busy, run: save }]}>
      <input type="text" maxLength={48} autoFocus placeholder={t('ed_tpl_name_ph')} value={name} onChange={(event) => setName(event.target.value)} />
    </Modal>
  );
}

const TOGGLES = [['lockpick', 'ed_lockpick'], ['breach', 'ed_breach'], ['hackable', 'ed_hack'], ['alarm', 'ed_alarm'], ['bell', 'ed_bell'], ['remote', 'ed_remote']] as const;

function BulkModal() {
  const { picked, groups, templates } = editor.use();
  const { sounds } = settings.use();
  const [form, setForm] = useState<Record<string, string>>({ group: '__keep', template: '', job: '', jobGrade: '0', jobRemove: '', soundLock: '__keep', soundUnlock: '__keep' });
  const [report, setReport] = useState<{ done: number; errors: ReportError[] } | null>(null);
  const [busy, run] = useBusy();
  const field = (key: string) => ({ value: form[key] ?? '', onChange: (event: { target: { value: string } }) => setForm({ ...form, [key]: event.target.value }) });

  const apply = () =>
    run(async () => {
      const patch: Record<string, unknown> = {};
      if (form.group !== '__keep') patch.group = form.group;
      if (form.template) patch.templateName = form.template;
      if (form.job.trim()) patch.addJob = { name: form.job.trim().toLowerCase(), grade: parseInt(form.jobGrade, 10) || 0 };
      if (form.jobRemove.trim()) patch.removeJob = form.jobRemove.trim().toLowerCase();
      const soundPatch: Record<string, string> = {};
      if (form.soundLock !== '__keep') soundPatch.lock = form.soundLock;
      if (form.soundUnlock !== '__keep') soundPatch.unlock = form.soundUnlock;
      if (Object.keys(soundPatch).length) patch.sounds = soundPatch;
      for (const [key] of TOGGLES) if (form[key]) patch[key] = form[key] === 'on';
      if (!Object.keys(patch).length) return;

      const result = await nuiResult<DoorsResult & { done: number; errors: ReportError[] }>('editor:bulk', { ids: picked, patch });
      if (!result?.ok) return toast('error', errText(result));
      setReport({ done: result.done, errors: result.errors || [] });
      applyLists(result);
      const draft = editor.get().draft;
      if (draft && !draft.isNew && picked.includes(draft.data.id)) selectDoor(draft.data.id);
    });

  const keep = <option value="__keep">{t('ed_bulk_keep')}</option>;
  const soundSelect = (key: string) => (
    <select {...field(key)}>
      {keep}
      {soundOptions(sounds).map((sound) => <option key={sound.key} value={sound.key}>{sound.label}</option>)}
    </select>
  );

  return (
    <Modal title={t('ed_bulk_title', picked.length)} actions={[closeAction(), { label: t('ed_bulk_apply'), className: 'primary', disabled: busy, run: apply }]}>
      <div className="bulk-grid">
        <label>
          <span>{t('ed_group')}</span>
          <select {...field('group')}>
            {keep}
            <option value="">{t('ed_no_group')}</option>
            {groups.map((group) => <option key={group.name} value={group.name}>{group.label}</option>)}
          </select>
        </label>
        <label>
          <span>{t('ed_tpl')}</span>
          <select {...field('template')}>
            <option value="">{t('ed_bulk_keep')}</option>
            {templates.map((template) => <option key={template.name} value={template.name}>{template.name}</option>)}
          </select>
        </label>
        <label>
          <span>{t('ed_bulk_add_job')}</span>
          <span className="row tight">
            <input type="text" placeholder="police" {...field('job')} />
            <input type="number" className="tiny" min={0} {...field('jobGrade')} />
          </span>
        </label>
        <label>
          <span>{t('ed_bulk_remove_job')}</span>
          <input type="text" placeholder="police" {...field('jobRemove')} />
        </label>
        <label><span>{t('ed_sound_unlock')}</span>{soundSelect('soundUnlock')}</label>
        <label><span>{t('ed_sound_lock')}</span>{soundSelect('soundLock')}</label>
        {TOGGLES.map(([key, label]) => (
          <label key={key}>
            <span>{t(label)}</span>
            <select {...field(key)}>
              <option value="">{t('ed_bulk_keep')}</option>
              <option value="on">{t('ed_bulk_on')}</option>
              <option value="off">{t('ed_bulk_off')}</option>
            </select>
          </label>
        ))}
      </div>
      <div className="report">
        {report && (
          <>
            <p><b>{t('ed_bulk_done', report.done)}</b></p>
            {report.errors.map(errorLine)}
          </>
        )}
      </div>
    </Modal>
  );
}

function GuideModal() {
  return (
    <Modal title={t('guide_title')} actions={[{ label: t('ed_close'), className: 'primary', run: closeModal }]}>
      <Guide />
    </Modal>
  );
}

const MODALS = {
  delete: DeleteModal,
  export: ExportModal,
  import: ImportModal,
  groups: GroupsModal,
  guide: GuideModal,
  templateSave: TemplateSaveModal,
  bulk: BulkModal,
};

export function Modals() {
  const { modal } = editor.use();
  if (!modal) return null;
  const View = MODALS[modal];
  return <View />;
}

