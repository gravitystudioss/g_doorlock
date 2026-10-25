import { z } from 'zod';
import type { DoorEntry, Group, Leaf, Pack, ReportError, SoundChoice, Template } from './types';

// Lua sends an empty list as {}
const list = <T extends z.ZodTypeAny>(item: T) =>
  z.preprocess(
    (value) => (value && typeof value === 'object' && !Array.isArray(value) && !Object.keys(value).length ? [] : value),
    z.array(item),
  );
const object = <T>() => z.custom<T>((value) => !!value && typeof value === 'object' && !Array.isArray(value));
const text = z.string().optional();

const door = object<DoorEntry>().refine((value) => typeof value.id === 'string');

const editorData = z
  .object({
    doors: list(door).optional(),
    groups: list(object<Group>()).optional(),
    templates: list(object<Template>()).optional(),
    packs: list(object<Pack>()).optional(),
    items: list(z.object({ name: z.string(), label: z.string().optional() })).optional(),
    supportsGangs: z.boolean().optional(),
    supportsMetadata: z.boolean().optional(),
  })
  .passthrough();

const initData = z
  .object({
    locale: z.unknown(),
    branding: z.unknown(),
    theme: z.unknown(),
    toastPosition: text,
    textUIPosition: text,
    pinMin: z.coerce.number().optional(),
    pinMax: z.coerce.number().optional(),
    indicator: z.boolean().optional(),
    sounds: list(object<SoundChoice>()).optional(),
    defaults: z.unknown(),
  })
  .passthrough();

const empty = z.unknown();

export const messageSchema = z.discriminatedUnion('action', [
  z.object({ action: z.literal('init'), data: initData }),
  z.object({
    action: z.literal('indicator'),
    data: z.object({
      show: z.boolean().optional(),
      locked: z.boolean().optional(),
      broken: z.boolean().optional(),
      name: text,
      key: text,
      action: text,
      actionKey: text,
    }),
  }),
  z.object({ action: z.literal('indicatorDenied'), data: empty }),
  z.object({
    action: z.literal('toast'),
    data: z.object({ type: text, text: text, title: text, duration: z.number().optional() }),
  }),
  z.object({
    action: z.literal('sound'),
    data: z.object({ type: text, preset: text, file: text, volume: z.coerce.number().optional() }),
  }),
  z.object({ action: z.literal('keypad:open'), data: z.object({ name: text }).passthrough() }),
  z.object({ action: z.literal('keypad:close'), data: empty }),
  z.object({ action: z.literal('keypad:error'), data: z.object({ text: text }) }),
  z.object({ action: z.literal('editor:open'), data: editorData }),
  z.object({ action: z.literal('editor:close'), data: empty }),
  z.object({ action: z.literal('editor:hide'), data: empty }),
  z.object({
    action: z.literal('editor:show'),
    data: z.object({ leaves: list(object<Leaf>()).optional(), selectId: text }),
  }),
  z.object({ action: z.literal('selection'), data: z.object({ show: z.boolean().optional(), text: text, hint: text }) }),
]);
export type Message = z.infer<typeof messageSchema>;
export type MessageOf<A extends Message['action']> = Extract<Message, { action: A }>['data'];

// Base shape of the server answers forwarded by the client
export const resultSchema = z
  .object({ ok: z.boolean().optional(), err: z.string().optional(), detail: z.unknown().optional() })
  .passthrough();
export type Result = z.infer<typeof resultSchema>;

export interface DoorsResult extends Result {
  doors?: DoorEntry[];
  groups?: Group[];
}

export interface ReportResult extends DoorsResult {
  created: string[];
  updated: string[];
  skipped: { id: string; err: string }[];
  errors: ReportError[];
}
