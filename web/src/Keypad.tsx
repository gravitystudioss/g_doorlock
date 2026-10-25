import { t } from './i18n';
import { BrandMini } from './Hud';
import { nui } from './nui';
import { settings } from './settings';
import { createStore } from './store';

const keypad = createStore({ open: false, name: '', pin: '', error: '', shakeTick: 0 });

export const openKeypad = (name = '') => keypad.set({ open: true, name, pin: '', error: '' });
export const closeKeypad = () => keypad.set({ open: false, pin: '' });
export const isKeypadOpen = () => keypad.get().open;

export function keypadError(text = '') {
  keypad.set((current) => ({ error: text, pin: '', shakeTick: current.shakeTick + 1 }));
}

export function keypadPress(key: string) {
  const { pin } = keypad.get();
  const { pinMin, pinMax } = settings.get();
  if (key === 'del') {
    keypad.set({ pin: pin.slice(0, -1), error: '' });
  } else if (key === 'ok') {
    if (pin.length < pinMin) return keypad.set({ error: t('pin_too_short', pinMin) });
    nui('keypad:submit', { pin });
    keypad.set({ pin: '', error: '' });
  } else if (pin.length < pinMax) {
    keypad.set({ pin: pin + key, error: '' });
  }
}

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];

export function Keypad() {
  const { open, name, pin, error, shakeTick } = keypad.use();
  if (!open) return null;

  const press = (key: string) => (event: React.MouseEvent<HTMLButtonElement>) => {
    keypadPress(key);
    event.currentTarget.blur();
  };

  return (
    <div id="keypad" className="overlay">
      <div key={shakeTick} className={'keypad card' + (shakeTick ? ' shake' : '')} role="dialog" aria-modal="true" aria-labelledby="kp-title" aria-describedby="kp-sub">
        <BrandMini />
        <h2 id="kp-title">{name}</h2>
        <p id="kp-sub" className="muted">{t('keypad_title')}</p>
        <div className="kp-display">{'•'.repeat(pin.length)}</div>
        <div className="kp-error" role="alert">{error}</div>
        <div className="kp-grid">
          {KEYS.map((key) => (
            <button key={key} onClick={press(key)}>{key}</button>
          ))}
          <button className="ghost" aria-label={t('keypad_clear')} onClick={press('del')}>{'⌫'}</button>
          <button onClick={press('0')}>0</button>
          <button className="primary" onClick={press('ok')}>{t('keypad_ok')}</button>
        </div>
        <button
          className="link"
          onClick={() => {
            closeKeypad();
            nui('close');
          }}
        >
          {t('keypad_cancel')}
        </button>
      </div>
    </div>
  );
}
