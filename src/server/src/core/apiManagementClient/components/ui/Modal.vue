<script setup lang="ts">
import { watch } from 'vue';

/**
 * Centered modal dialog with backdrop. Body scroll lock is handled by watching
 * the open state. Content is provided via the default slot; actions via the
 * `actions` slot.
 */
const props = withDefaults(
  defineProps<{
    open: boolean;
    title?: string;
    width?: string;
  }>(),
  { width: '640px' },
);

const emit = defineEmits<{ close: [] }>();

function onKey(e: KeyboardEvent): void {
  if (e.key === 'Escape' && props.open) emit('close');
}

watch(
  () => props.open,
  open => {
    document.body.style.overflow = open ? 'hidden' : '';
    if (open) window.addEventListener('keydown', onKey);
    else window.removeEventListener('keydown', onKey);
  },
);
</script>

<template>
  <transition name="modal">
    <div v-if="open" class="modal-backdrop" @click.self="emit('close')">
      <div class="modal" :style="{ maxWidth: width }">
        <header v-if="title || $slots.header" class="modal-header">
          <slot name="header"><h3>{{ title }}</h3></slot>
          <button class="modal-x ghost" @click="emit('close')">✕</button>
        </header>
        <div class="modal-body">
          <slot />
        </div>
        <footer v-if="$slots.actions" class="modal-actions">
          <slot name="actions" />
        </footer>
      </div>
    </div>
  </transition>
</template>

<style scoped>
.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding: 5vh 20px;
  z-index: 900;
  overflow-y: auto;
}
.modal {
  width: 100%;
  background: var(--bg-elev);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
  display: flex;
  flex-direction: column;
  max-height: 90vh;
}
.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 18px;
  border-bottom: 1px solid var(--border);
}
.modal-header h3 {
  margin: 0;
  font-size: 15px;
}
.modal-x {
  padding: 2px 8px;
  color: var(--text-dim);
}
.modal-body {
  padding: 18px;
  overflow: auto;
}
.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  padding: 14px 18px;
  border-top: 1px solid var(--border);
}
.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}
.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.15s ease;
}
.modal-enter-from .modal,
.modal-leave-to .modal {
  transform: translateY(-12px);
}
.modal-enter-active .modal,
.modal-leave-active .modal {
  transition: transform 0.15s ease;
}
</style>
