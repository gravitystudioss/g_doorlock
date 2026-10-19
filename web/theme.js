/* Shared Gravity theme adapter. Only recognized config keys are applied. */
window.GravityNUITheme = (() => {
    const colors = {
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
    const hex = value => typeof value === 'string' && /^#[\da-f]{6}$/i.test(value.trim());
    const rgb = value => [1, 3, 5].map(at => parseInt(value.slice(at, at + 2), 16));
    const mix = (a, b, ratio) => '#' + rgb(a).map((part, i) =>
        Math.round(part * (1 - ratio) + rgb(b)[i] * ratio).toString(16).padStart(2, '0')).join('');

    function apply(root, theme, prefix = '--g-') {
        theme = theme && typeof theme === 'object' ? theme : {};
        const set = (key, value) => root.style.setProperty(prefix + key, value);
        [...Object.values(colors), ...derived, 'ui-font', 'display-font'].forEach(key => root.style.removeProperty(prefix + key));
        const baseline = getComputedStyle(root);
        let changed = false;
        let primaryChanged = false;
        Object.entries(colors).forEach(([key, variable]) => {
            const value = theme.colors && theme.colors[key];
            if (!hex(value)) return;
            const color = value.trim().toLowerCase();
            if (color !== baseline.getPropertyValue(prefix + variable).trim().toLowerCase()) {
                changed = true;
                if (key === 'primary') primaryChanged = true;
            }
            set(variable, color);
        });
        if (changed) {
            const style = getComputedStyle(root);
            const get = key => style.getPropertyValue(prefix + key).trim();
            const bg = get('bg'), surface = get('surface'), accent = get('violet'), bad = get('bad');
            const shades = {
                'ok-border': mix(bg, get('ok'), .35),
                'primary-border': mix(get('primary'), get('lilac'), .25),
                'tab-border': mix(get('primary'), bg, .1),
                hover: mix(surface, accent, .1), 'danger-bg': mix(bg, bad, .08),
                'danger-border': mix(bg, bad, .35), 'danger-text': bad,
                'danger-soft': mix(bad, '#ffffff', .65), 'warn-soft': mix(get('warn'), '#ffffff', .3),
                'nav-start': mix(bg, accent, .3), 'nav-end': mix(bg, accent, .15),
                'selected-border': mix(bg, accent, .4), 'count-bg': mix(bg, get('cyan'), .08),
                'active-bg': mix(bg, accent, .13), 'permission-bg': mix(bg, accent, .2),
                'market-active': mix(bg, accent, .08), 'seal-bg': mix(bg, accent, .17),
                'total-bg': mix(bg, accent, .12),
            };
            Object.entries(shades).forEach(([key, value]) => set(key, value));
            if (primaryChanged) {
                if (!hex(theme.colors.gradientStart)) set('gradient-start', mix(get('primary'), get('lilac'), .2));
                if (!hex(theme.colors.gradientEnd)) set('gradient-end', mix(get('primary'), bg, .25));
            }
            for (const key of ['violet', 'primary', 'ok', 'warn', 'cyan', 'bg', 'bg-2', 'surface', 'muted']) {
                set(key + '-rgb', rgb(get(key)).join(', '));
            }
            set('bad-rgb', rgb(get('bad-strong')).join(', '));
            set('card-rgb', rgb(surface).join(', '));
            set('side-rgb', rgb(get('bg-2')).join(', '));
            set('market-accent-rgb', rgb(accent).join(', '));
        }
        for (const [key, variable, fallback] of [['body', 'ui-font', "'Arial Narrow', sans-serif"], ['headings', 'display-font', 'Impact, sans-serif']]) {
            const font = theme.fonts && theme.fonts[key];
            if (typeof font === 'string' && font.trim()) set(variable, `${JSON.stringify(font.trim())}, ${fallback}`);
        }
    }
    return { apply };
})();
