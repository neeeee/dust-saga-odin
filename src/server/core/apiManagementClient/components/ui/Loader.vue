<script setup lang="ts">
withDefaults(defineProps<{ label?: string; inline?: boolean }>(), {
  label: '',
  inline: false,
});
</script>

<template>
  <div :class="['loader', { inline }]">
    <span class="spinner" />
    <span v-if="label" class="loader-label">{{ label }}</span>
  </div>
</template>

<style scoped>
.loader {
  display: flex;
  align-items: center;
  gap: 9px;
  color: var(--text-dim);
  padding: 18px;
  justify-content: center;
}
.loader.inline {
  padding: 0;
}
.spinner {
  width: 14px;
  height: 14px;
  border: 2px solid var(--border);
  border-top-color: var(--accent);
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
}
.loader-label {
  font-size: 12.5px;
}
@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
