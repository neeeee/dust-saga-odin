<script setup lang="ts">
/**
 * Standard cancel / secondary button for dialogs and inline editors.
 * Purely presentational — emits `cancel` and lets the parent decide dismissal.
 */
withDefaults(defineProps<{ label?: string; disabled?: boolean }>(), {
  label: 'Cancel',
  disabled: false,
});
const emit = defineEmits<{ cancel: [] }>();
</script>

<template>
  <button class="ghost" :disabled="disabled" @click="emit('cancel')">
    {{ label }}
  </button>
</template>
