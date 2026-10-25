import { resultSchema, type Result } from './contracts';

declare global {
  interface Window {
    GetParentResourceName?: () => string;
  }
}

export const inGame = typeof window.GetParentResourceName === 'function';

// Resolves to null when the client does not answer: callers show err_generic
export async function nui(event: string, payload: unknown = {}): Promise<unknown> {
  if (!inGame) return null;
  try {
    const response = await fetch(`https://${window.GetParentResourceName!()}/${event}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(20000),
    });
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
}

// Server answers that must carry the { ok, err } shape
export async function nuiResult<T extends Result = Result>(event: string, payload: unknown = {}): Promise<T | null> {
  const parsed = resultSchema.safeParse(await nui(event, payload));
  return parsed.success ? (parsed.data as T) : null;
}
