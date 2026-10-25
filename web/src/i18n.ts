type Value = string | number | null | undefined;

let strings: Record<string, string> = {};

// Sent by the client on init, no rebuild for text changes
export function setLocale(translations: unknown) {
  strings = translations && typeof translations === 'object' ? (translations as Record<string, string>) : {};
  document.documentElement.lang = strings._lang || 'en';
}

// Same placeholders as Lua string.format (%s %d)
export function t(key: string | undefined, ...values: Value[]): string {
  const text = key && typeof strings[key] === 'string' ? strings[key] : key || '';
  return text.replace(/%%|%[sd]/g, (match) => (match === '%%' ? '%' : String(values.shift() ?? '')));
}
