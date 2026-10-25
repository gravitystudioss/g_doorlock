import { toast } from '../Hud';
import { t } from '../i18n';
import { nui } from '../nui';
import { settings } from '../settings';
import { DoorForm, Guide } from './DoorForm';
import { Modals } from './Modals';
import { editor, filteredDoors, newDraft, openModal, selectDoor } from './store';

export function Editor() {
  const state = editor.use();
  const { serverName, logo } = settings.use();
  if (!state.visible) return null;

  const list = filteredDoors();
  const activeId = state.draft && !state.draft.isNew ? state.draft.data.id : null;

  const togglePick = (id: string, checked: boolean) =>
    editor.set((current) => ({ picked: checked ? [...current.picked, id] : current.picked.filter((entry) => entry !== id) }));

  const findNearest = async () => {
    const id = await nui('editor:nearest');
    if (typeof id !== 'string' || !id) return toast('error', t('quick_none'));
    selectDoor(id);
  };

  return (
    <div id="editor" className="overlay">
      <div className="editor card" role="dialog" aria-modal="true" aria-labelledby="ed-title">
        <header className="ed-head">
          <div className="brand">
            {logo && <img src={logo} alt="" />}
            <div>
              {serverName && <b className="gradient-text" title={serverName}>{serverName}</b>}
              <small id="ed-title">{t('ed_title')}</small>
            </div>
          </div>
          <span className="grow" />
          <button onClick={() => openModal('guide')}>{t('guide_btn')}</button>
          <button className="icon-btn" title="ESC" aria-label={t('ed_close')} onClick={() => nui('close')}>&times;</button>
        </header>

        <div className="ed-body">
          <aside className="ed-side">
            <input
              type="text"
              autoComplete="off"
              placeholder={t('ed_search')}
              aria-label={t('ed_search')}
              value={state.search}
              onChange={(event) => editor.set({ search: event.target.value })}
            />
            <select aria-label={t('ed_group')} value={state.groupFilter} onChange={(event) => editor.set({ groupFilter: event.target.value })}>
              <option value="">{t('ed_all_groups')}</option>
              <GroupOptions />
            </select>
            <div className="side-actions side-primary">
              <button className="primary" onClick={() => newDraft()}>{t('ed_new')}</button>
            </div>
            <div className="side-actions">
              <button onClick={() => openModal('import')}>{t('ed_import')}</button>
              <button onClick={() => openModal('export')}>{t('ed_export')}</button>
            </div>
            <div className="side-actions">
              <button onClick={findNearest}>{t('ed_find')}</button>
              <button onClick={() => openModal('groups')}>{t('ed_groups')}</button>
            </div>
            {state.picked.length > 0 && (
              <div className="bulk-bar">
                <span>{t('ed_bulk_count', state.picked.length)}</span>
                <button className="small primary" onClick={() => openModal('bulk')}>{t('ed_bulk')}</button>
                <button className="small" aria-label={t('ed_cancel')} onClick={() => editor.set({ picked: [] })}>&times;</button>
              </div>
            )}
            <div className="ed-list">
              {list.length ? (
                list.map((door) => (
                  <div
                    key={door.id}
                    className={'door-item' + (door.id === activeId ? ' active' : '')}
                    tabIndex={0}
                    aria-label={door.name}
                    onClick={(event) => {
                      if (!(event.target as HTMLElement).classList.contains('pick')) selectDoor(door.id);
                    }}
                    onKeyDown={(event) => {
                      if (event.target === event.currentTarget && (event.key === 'Enter' || event.key === ' ')) {
                        event.preventDefault();
                        selectDoor(door.id);
                      }
                    }}
                  >
                    <input
                      type="checkbox"
                      className="pick"
                      aria-label={t('ed_bulk') + ': ' + door.name}
                      checked={state.picked.includes(door.id)}
                      onChange={(event) => togglePick(door.id, event.target.checked)}
                    />
                    <span className={'dot' + (door.state ? '' : ' open')} />
                    <div className="meta">
                      <b>{door.name}</b>
                      <small>{door.id}{door.group ? ' · ' + door.group : ''}</small>
                    </div>
                    <span className="tag">{t('ed_type_' + door.type)}</span>
                  </div>
                ))
              ) : (
                <div className="muted small">{t('ed_empty')}</div>
              )}
            </div>
            <div id="ed-count" className="muted small">{t('ed_count', list.length, state.doors.length)}</div>
          </aside>

          <section className="ed-main">
            {state.draft ? (
              <DoorForm />
            ) : (
              <div className="empty">
                <div className="guide-box">
                  <p className="muted">{t('ed_pick')}</p>
                  <Guide />
                </div>
              </div>
            )}
          </section>
        </div>
      </div>
      <datalist id="item-list">
        {state.items.map((item) => (
          <option key={item.name} value={item.name}>{item.label || ''}</option>
        ))}
      </datalist>
      <Modals />
    </div>
  );
}

export function GroupOptions() {
  const { groups } = editor.use();
  return groups.map((group) => (
    <option key={group.name} value={group.name}>
      {group.label}{group.label !== group.name ? ` (${group.name})` : ''}
    </option>
  ));
}
