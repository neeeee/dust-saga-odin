import { reactive, readonly } from 'vue';

/**
 * Tiny global toast bus. Panels and the API layer can push notifications
 * without prop-drilling. Used by the `<Notification>` component for rendering.
 */
export interface Toast {
  id: number;
  type: 'success' | 'error' | 'info';
  message: string;
  timeout: number;
}

interface NotifyState {
  toasts: Toast[];
}

const state = reactive<NotifyState>({ toasts: [] });
let nextId = 1;

function dismiss(id: number): void {
  const idx = state.toasts.findIndex(t => t.id === id);
  if (idx >= 0) state.toasts.splice(idx, 1);
}

function push(
  type: Toast['type'],
  message: string,
  timeout = 4000,
): number {
  const id = nextId++;
  state.toasts.push({ id, type, message, timeout });
  if (timeout > 0) {
    window.setTimeout(() => dismiss(id), timeout);
  }
  return id;
}

export const notify = {
  state: readonly(state),
  dismiss,
  success: (m: string, t?: number) => push('success', m, t),
  error: (m: string, t?: number) => push('error', m, t ?? 6000),
  info: (m: string, t?: number) => push('info', m, t),
};
