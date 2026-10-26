import { nui } from './nui';
import type { MessageOf } from './contracts';
import { t } from './i18n';
import { settings } from './settings';
import { createStore } from './store';

interface Toast {
  id: number;
  type: string;
  text: string;
  title?: string;
  action?: { label: string; run: () => void };
}


const hud = createStore({
  indicator: { show: false } as MessageOf<'indicator'>,
  deniedTick: 0,
  denied: false,
  selection: { show: false } as MessageOf<'selection'>,
});

let deniedTimer = 0;

export function toast(type: string, text: string, options: { title?: string; duration?: number; action?: Toast['action'] } = {}) {
  if (text) void nui('notify', { message: text, type, title: options.title, duration: options.duration });
}

export const setIndicator = (indicator: MessageOf<'indicator'>) => hud.set({ indicator, denied: false });
export const setSelection = (selection: MessageOf<'selection'>) => hud.set({ selection });

export function flashDenied() {
  hud.set((current) => ({ denied: true, deniedTick: current.deniedTick + 1 }));
  window.clearTimeout(deniedTimer);
  deniedTimer = window.setTimeout(() => hud.set({ denied: false }), 1500);
}

const IconLock = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><rect x="5" y="10" width="14" height="11" rx="1" /><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3" /></svg>
);
const IconOpen = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><rect x="5" y="10" width="14" height="11" rx="1" /><path d="M8 10V7a4 4 0 0 1 7.5-2M12 14v3" /></svg>
);

export function BrandMini({ product }: { product?: string }) {
  const { serverName, logo } = settings.use();
  if (!serverName && !logo && !product) return null;
  return (
    <div className="brand-mini">
      {logo && <img className="logo-sm" src={logo} alt="" />}
      {product ? (
        <span className="brand-mini-copy">
          {serverName && <span title={serverName}>{serverName}</span>}
          <small>{product}</small>
        </span>
      ) : (
        serverName && <span title={serverName}>{serverName}</span>
      )}
    </div>
  );
}

export function Hud() {
  const { indicator, denied, deniedTick, selection } = hud.use();
  const config = settings.use();
  const showIndicator = config.indicator && indicator.show;
  const stateText = denied ? t('access_denied') : indicator.broken ? t('ed_broken') : indicator.locked ? t('locked') : t('unlocked');
  const classes = ['indicator', indicator.locked ? '' : 'open', denied ? 'denied' : ''].filter(Boolean).join(' ');

  return (
    <>
      {showIndicator && (
        <div key={deniedTick} className={classes} data-position={config.textUIPosition}>
          <span className="ind-icon">{indicator.locked ? <IconLock /> : <IconOpen />}</span>
          <span className="ind-text">
            <b>{stateText}</b>
            <small>{indicator.name || ''}</small>
          </span>
          {indicator.key && <span className="ind-key">{indicator.key}</span>}
          {indicator.action && (
            <span className="ind-action">
              <span className="ind-key">{indicator.actionKey}</span>
              <small>{indicator.action}</small>
            </span>
          )}
        </div>
      )}

      {selection.show && (
        <div className="selection">
          <BrandMini product="DOORLOCK" />
          <div id="selection-text">{selection.text || ''}</div>
          <div id="selection-hint" className="muted small">{selection.hint || ''}</div>
          <div className="muted small">{t('sel_help')}</div>
        </div>
      )}
    </>
  );
}
