<script setup lang="ts">
import { ref, watch } from 'vue';

/**
 * A button that requires a two-step confirm before firing its action.
 * Click once -> "Confirm?" state; click again (within the timeout) -> emit.
 * Prevents accidental destructive actions (deletes, reloads) without a modal.
 */
const props = withDefaults(
  defineProps<{
    label?: string;
    confirmLabel?: string;
    timeout?: number;
    danger?: boolean;
    disabled?: boolean;
  }>(),
  {
    label: 'Confirm',
    confirmLabel: 'Confirm?',
    timeout: 3000,
    danger: false,
    disabled: false,
  },
);

const emit = defineEmits<{ confirm: [] }>();

const armed = ref(false);
let timer: number | undefined;

watch(armed, a => {
  if (timer) window.clearTimeout(timer);
  if (a) timer = window.setTimeout(() => (armed.value = false), props.timeout);
});

function onClick(): void {
  if (!armed.value) {
    armed.value = true;
    return;
  }
  armed.value = false;
  emit('confirm');
}
</script>

<template>
  <button
    :class="['confirm-btn', { danger, armed }]"
    :disabled="disabled"
    @click="onClick"
    @blur="armed = false"
  >
    {{ armed ? confirmLabel : label }}
  </button>
</template>

<style scoped>
.confirm-btn.armed {
  background: var(--error);
  border-color: var(--error);
  color: #fff;
  font-weight: 600;
}
</style>
