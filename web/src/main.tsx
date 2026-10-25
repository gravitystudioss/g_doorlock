import { Component, type ReactNode } from 'react';
import { createRoot } from 'react-dom/client';
import { messageSchema, type Message } from './contracts';
import { Editor } from './editor/Editor';
import { closeEditor, closeModal, editor, hideEditor, openEditor, showEditor } from './editor/store';
import { flashDenied, Hud, setIndicator, setSelection, toast } from './Hud';
import { closeKeypad, isKeypadOpen, Keypad, keypadError, keypadPress, openKeypad } from './Keypad';
import { nui } from './nui';
import { applyInit, settings } from './settings';
import { playSound } from './sound';

function handle(message: Message) {
  switch (message.action) {
    case 'init':
      return applyInit(message.data);
    case 'indicator':
      return setIndicator(message.data);
    case 'indicatorDenied':
      return flashDenied();
    case 'toast':
      return toast(message.data.type || '', message.data.text || '', { title: message.data.title, duration: message.data.duration });
    case 'sound':
      return playSound(message.data);
    case 'keypad:open':
      return openKeypad(message.data.name);
    case 'keypad:close':
      return closeKeypad();
    case 'keypad:error':
      return keypadError(message.data.text);
    case 'editor:open':
      return openEditor(message.data);
    case 'editor:close':
      return closeEditor();
    case 'editor:hide':
      return hideEditor();
    case 'editor:show':
      return showEditor(message.data);
    case 'selection':
      return setSelection(message.data);
  }
}

window.addEventListener('message', ({ data }) => {
  const message = messageSchema.safeParse(data);
  if (message.success) handle(message.data);
});

window.addEventListener('keydown', (event) => {
  const keypadOpen = isKeypadOpen();
  if (event.key === 'Escape') {
    if (editor.get().modal) return closeModal();
    if (keypadOpen) closeKeypad();
    if (keypadOpen || editor.get().visible) nui('close');
    return;
  }
  if (!keypadOpen) return;
  // preventDefault so enter/space don't also "click" the last focused button
  if (/^[0-9]$/.test(event.key)) {
    event.preventDefault();
    keypadPress(event.key);
  } else if (event.key === 'Backspace') {
    event.preventDefault();
    keypadPress('del');
  } else if (event.key === 'Enter') {
    event.preventDefault();
    keypadPress('ok');
  } else if (event.key === ' ') {
    event.preventDefault();
  }
});

// A render error hides only the failing surface
class ViewBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  componentDidCatch(error: unknown) {
    console.error('[g_doorlock]', error);
  }
  render() {
    return this.state.failed ? null : this.props.children;
  }
}

function App() {
  // Re-render every surface when the locale or branding changes
  settings.use();
  return (
    <>
      <ViewBoundary>
        <Hud />
      </ViewBoundary>
      <ViewBoundary>
        <Keypad />
      </ViewBoundary>
      <ViewBoundary>
        <Editor />
      </ViewBoundary>
    </>
  );
}

createRoot(document.getElementById('root')!).render(<App />);
nui('ready');
