<script setup lang="ts">
import { notify } from '../../composables/useNotify';
/**
 * Toast renderer. Reads from the global notify bus and stacks notifications
 * in the top-right corner. Mounted once by the app shell.
 */
</script>

<template>
  <div class="toast-stack">
    <transition-group name="toast">
      <div
        v-for="toast in notify.state.toasts"
        :key="toast.id"
        class="toast"
        :class="toast.type"
        @click="notify.dismiss(toast.id)"
      >
        <span class="toast-icon">{{
          toast.type === 'success' ? '✓' : toast.type === 'error' ? '✕' : 'ℹ'
        }}</span>
        <span class="toast-msg">{{ toast.message }}</span>
      </div>
    </transition-group>
  </div>
</template>

<style scoped>
.toast-stack {
  position: fixed;
  top: 16px;
  right: 16px;
  z-index: 1000;
  display: flex;
  flex-direction: column;
  gap: 8px;
  pointer-events: none;
}
.toast {
  pointer-events: auto;
  min-width: 240px;
  max-width: 380px;
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 10px 14px;
  border-radius: var(--radius-sm);
  background: var(--bg-elev-2);
  border: 1px solid var(--border);
  border-left-width: 3px;
  box-shadow: var(--shadow);
  cursor: pointer;
  font-size: 13px;
}
.toast.success {
  border-left-color: var(--success);
}
.toast.error {
  border-left-color: var(--error);
}
.toast.info {
  border-left-color: var(--accent);
}
.toast-icon {
  font-weight: 700;
}
.toast.success .toast-icon {
  color: var(--success);
}
.toast.error .toast-icon {
  color: var(--error);
}
.toast.info .toast-icon {
  color: var(--accent);
}
.toast-enter-from,
.toast-leave-to {
  opacity: 0;
  transform: translateX(20px);
}
.toast-enter-active,
.toast-leave-active {
  transition: all 0.2s ease;
}
</style>
