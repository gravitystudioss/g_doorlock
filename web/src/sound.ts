import type { MessageOf } from './contracts';

let audioContext: AudioContext | null = null;

function tone(context: AudioContext, frequency: number, start: number, duration: number, type: OscillatorType, volume: number, slideTo?: number) {
  const oscillator = context.createOscillator();
  const gain = context.createGain();
  const at = context.currentTime + start;
  oscillator.type = type;
  oscillator.frequency.setValueAtTime(frequency, at);
  if (slideTo) oscillator.frequency.linearRampToValueAtTime(slideTo, at + duration);
  gain.gain.setValueAtTime(0.0001, at);
  gain.gain.exponentialRampToValueAtTime(volume, at + 0.01);
  gain.gain.exponentialRampToValueAtTime(0.0001, at + duration);
  oscillator.connect(gain).connect(context.destination);
  oscillator.start(at);
  oscillator.stop(at + duration + 0.02);
}

function click(context: AudioContext, start: number, volume: number) {
  const length = Math.floor(context.sampleRate * 0.04);
  const buffer = context.createBuffer(1, length, context.sampleRate);
  const samples = buffer.getChannelData(0);
  for (let i = 0; i < length; i++) samples[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / length, 4);
  const source = context.createBufferSource();
  const gain = context.createGain();
  const filter = context.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.value = 2200;
  gain.gain.value = volume;
  source.buffer = buffer;
  source.connect(filter).connect(gain).connect(context.destination);
  source.start(context.currentTime + start);
}

const presets: Record<string, (context: AudioContext, volume: number) => void> = {
  bolt: (ctx, v) => { click(ctx, 0, v * 1.4); tone(ctx, 140, 0, 0.09, 'square', v * 0.25, 90); click(ctx, 0.09, v * 1.6); },
  unlock: (ctx, v) => { click(ctx, 0, v * 1.2); tone(ctx, 520, 0.02, 0.08, 'sine', v * 0.5); tone(ctx, 780, 0.1, 0.1, 'sine', v * 0.5); },
  beep: (ctx, v) => { tone(ctx, 880, 0, 0.12, 'sine', v * 0.6); },
  denied: (ctx, v) => { tone(ctx, 220, 0, 0.14, 'square', v * 0.25); tone(ctx, 160, 0.16, 0.2, 'square', v * 0.25); },
  chime: (ctx, v) => { tone(ctx, 660, 0, 0.15, 'sine', v * 0.5); tone(ctx, 880, 0.12, 0.15, 'sine', v * 0.5); tone(ctx, 1320, 0.24, 0.25, 'sine', v * 0.4); },
  keycard: (ctx, v) => { tone(ctx, 1200, 0, 0.06, 'square', v * 0.2); tone(ctx, 1600, 0.08, 0.09, 'square', v * 0.2); click(ctx, 0.2, v * 1.2); },
  heavy: (ctx, v) => { tone(ctx, 70, 0, 0.35, 'sawtooth', v * 0.25, 45); click(ctx, 0.05, v * 2); click(ctx, 0.3, v * 2.2); },
  knock: (ctx, v) => { click(ctx, 0, v * 2.5); click(ctx, 0.18, v * 2.5); click(ctx, 0.36, v * 2.5); },
  alarm: (ctx, v) => { tone(ctx, 880, 0, 0.5, 'square', v * 0.22, 1320); tone(ctx, 1320, 0.55, 0.5, 'square', v * 0.22, 880); },
  gate: (ctx, v) => { tone(ctx, 90, 0, 0.9, 'sawtooth', v * 0.15, 110); tone(ctx, 180, 0, 0.9, 'triangle', v * 0.12, 200); click(ctx, 0.92, v * 1.5); },
};

export function playSound(data: MessageOf<'sound'>) {
  const volume = Math.max(0, Math.min(1, data.volume || 0.3));
  if (data.type === 'file' && data.file) {
    const audio = new Audio('sounds/' + data.file);
    audio.volume = volume;
    audio.play().catch(() => {});
    return;
  }
  if (!audioContext) audioContext = new AudioContext();
  if (audioContext.state === 'suspended') audioContext.resume();
  (presets[data.preset || ''] || presets.beep)(audioContext, volume);
}
