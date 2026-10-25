import type { MessageOf } from './contracts';
import { setLocale } from './i18n';
import { createStore } from './store';
import type { Defaults, SoundChoice } from './types';

interface Branding {
  watermark?: boolean;
  serverName?: string;
  logo?: string;
  theme?: unknown;
}

export const settings = createStore({
  version: 0,
  pinMin: 4,
  pinMax: 8,
  indicator: true,
  sounds: [] as SoundChoice[],
  defaults: {} as Defaults,
  toastPosition: 'top-right',
  textUIPosition: 'bottom',
  serverName: 'Gravity Studios',
  logo: 'img/logo.png',
});

// Config.NUI.theme keys to CSS variables
const themeColors: Record<string, string> = {
  background: 'bg', backgroundSecondary: 'bg-2', surface: 'surface',
  surfaceSecondary: 'surface-2', input: 'input', border: 'border', borderStrong: 'border-strong',
  text: 'text', muted: 'muted', faint: 'faint', primary: 'primary', accent: 'violet',
  highlight: 'lilac', gradientStart: 'gradient-start', gradientEnd: 'gradient-end',
  primaryText: 'on-primary', info: 'cyan', success: 'ok', warning: 'warn',
  danger: 'bad', dangerStrong: 'bad-strong',
};
const derived = ['ok-border', 'primary-border', 'tab-border', 'hover', 'danger-bg', 'danger-border', 'danger-text', 'danger-soft', 'warn-soft',
  'nav-start', 'nav-end', 'selected-border', 'count-bg', 'active-bg', 'permission-bg',
  'market-active', 'seal-bg', 'total-bg', 'violet-rgb', 'primary-rgb', 'ok-rgb',
  'warn-rgb', 'bad-rgb', 'cyan-rgb', 'bg-rgb', 'bg-2-rgb', 'surface-rgb', 'muted-rgb', 'card-rgb', 'side-rgb', 'market-accent-rgb'];

const isHex = (value: unknown): value is string => typeof value === 'string' && /^#[\da-f]{6}$/i.test(value.trim());
const toRgb = (value: string) => [1, 3, 5].map((at) => parseInt(value.slice(at, at + 2), 16));
const mix = (from: string, to: string, ratio: number) => {
  const target = toRgb(to);
  return '#' + toRgb(from).map((part, index) => Math.round(part * (1 - ratio) + target[index] * ratio).toString(16).padStart(2, '0')).join('');
};

// Only recognized config keys are applied; secondary shades follow the chosen colors
function applyTheme(input: unknown) {
  const theme = (input && typeof input === 'object' ? input : {}) as { colors?: Record<string, unknown>; fonts?: Record<string, unknown> };
  const colors = theme.colors || {};
  const root = document.documentElement;
  const set = (key: string, value: string) => root.style.setProperty('--' + key, value);
  [...Object.values(themeColors), ...derived, 'ui-font', 'display-font'].forEach((key) => root.style.removeProperty('--' + key));
  const baseline = getComputedStyle(root);
  let changed = false;
  let primaryChanged = false;
  for (const [key, variable] of Object.entries(themeColors)) {
    const value = colors[key];
    if (!isHex(value)) continue;
    const color = value.trim().toLowerCase();
    if (color !== baseline.getPropertyValue('--' + variable).trim().toLowerCase()) {
      changed = true;
      if (key === 'primary') primaryChanged = true;
    }
    set(variable, color);
  }
  if (changed) {
    const style = getComputedStyle(root);
    const get = (key: string) => style.getPropertyValue('--' + key).trim();
    const bg = get('bg'), surface = get('surface'), accent = get('violet'), bad = get('bad');
    const shades: Record<string, string> = {
      'ok-border': mix(bg, get('ok'), 0.35),
      'primary-border': mix(get('primary'), get('lilac'), 0.25),
      'tab-border': mix(get('primary'), bg, 0.1),
      hover: mix(surface, accent, 0.1), 'danger-bg': mix(bg, bad, 0.08),
      'danger-border': mix(bg, bad, 0.35), 'danger-text': bad,
      'danger-soft': mix(bad, '#ffffff', 0.65), 'warn-soft': mix(get('warn'), '#ffffff', 0.3),
      'nav-start': mix(bg, accent, 0.3), 'nav-end': mix(bg, accent, 0.15),
      'selected-border': mix(bg, accent, 0.4), 'count-bg': mix(bg, get('cyan'), 0.08),
      'active-bg': mix(bg, accent, 0.13), 'permission-bg': mix(bg, accent, 0.2),
      'market-active': mix(bg, accent, 0.08), 'seal-bg': mix(bg, accent, 0.17),
      'total-bg': mix(bg, accent, 0.12),
    };
    Object.entries(shades).forEach(([key, value]) => set(key, value));
    if (primaryChanged) {
      if (!isHex(colors.gradientStart)) set('gradient-start', mix(get('primary'), get('lilac'), 0.2));
      if (!isHex(colors.gradientEnd)) set('gradient-end', mix(get('primary'), bg, 0.25));
    }
    for (const key of ['violet', 'primary', 'ok', 'warn', 'cyan', 'bg', 'bg-2', 'surface', 'muted']) {
      set(key + '-rgb', toRgb(get(key)).join(', '));
    }
    set('bad-rgb', toRgb(get('bad-strong')).join(', '));
    set('card-rgb', toRgb(surface).join(', '));
    set('side-rgb', toRgb(get('bg-2')).join(', '));
    set('market-accent-rgb', toRgb(accent).join(', '));
  }
  const fonts = theme.fonts || {};
  for (const [key, variable, fallback] of [['body', 'ui-font', "'Arial Narrow', sans-serif"], ['headings', 'display-font', 'Impact, sans-serif']]) {
    const font = fonts[key];
    if (typeof font === 'string' && font.trim()) set(variable, `${JSON.stringify(font.trim())}, ${fallback}`);
  }
}

export function applyInit(data: MessageOf<'init'>) {
  setLocale(data.locale);
  const branding = (data.branding && typeof data.branding === 'object' ? data.branding : {}) as Branding;
  applyTheme(data.theme || branding.theme);
  const logo = typeof branding.logo === 'string' ? branding.logo.trim() : 'img/logo.png';
  const current = settings.get();
  settings.set({
    version: current.version + 1,
    pinMin: data.pinMin || current.pinMin,
    pinMax: data.pinMax || current.pinMax,
    indicator: data.indicator !== false,
    sounds: data.sounds || [],
    defaults: (data.defaults && typeof data.defaults === 'object' ? data.defaults : {}) as Defaults,
    toastPosition: ['top', 'top-right', 'bottom-right'].includes(data.toastPosition || '') ? data.toastPosition! : 'top-right',
    textUIPosition: ['bottom', 'left', 'right'].includes(data.textUIPosition || '') ? data.textUIPosition! : 'bottom',
    serverName: typeof branding.serverName === 'string' ? branding.serverName : 'Gravity Studios',
    logo: branding.watermark !== false ? logo : '',
  });
}
