import { useSyncExternalStore } from 'react';

// Module stores: async handlers always read the current value
export function createStore<T extends object>(initial: T) {
  let value = initial;
  const listeners = new Set<() => void>();
  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  };
  const get = () => value;
  return {
    get,
    set(patch: Partial<T> | ((current: T) => Partial<T>)) {
      value = { ...value, ...(typeof patch === 'function' ? patch(value) : patch) };
      listeners.forEach((listener) => listener());
    },
    use: () => useSyncExternalStore(subscribe, get),
  };
}
