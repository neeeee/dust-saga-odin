<script setup lang="ts">
import { ref, watch } from 'vue';

/**
 * JSON editor: a validated textarea. v-model carries the parsed object. The
 * raw text is edited separately and parsed on change; invalid JSON shows an
 * inline error and keeps the previous valid value intact. Useful for the
 * arbitrary-shape create/edit forms on Items / Quests where building a full
 * field-by-field UI would be brittle.
 */
const props = defineProps<{
  modelValue: unknown;
  label?: string;
  minHeight?: string;
}>();

const emit = defineEmits<{ 'update:modelValue': [value: unknown] }>();

const text = ref('');
const error = ref<string | null>(null);

function serialize(v: unknown): string {
  try {
    return JSON.stringify(v ?? null, null, 2);
  } catch {
    return '';
  }
}

watch(
  () => props.modelValue,
  v => {
    const next = serialize(v);
    if (next !== text.value && !error.value) {
      text.value = next;
    }
  },
  { immediate: true },
);

function onInput(e: Event): void {
  const raw = (e.target as HTMLTextAreaElement).value;
  text.value = raw;
  if (!raw.trim()) {
    error.value = null;
    emit('update:modelValue', null);
    return;
  }
  try {
    const parsed = JSON.parse(raw);
    error.value = null;
    emit('update:modelValue', parsed);
  } catch (err) {
    error.value = err instanceof Error ? err.message : 'Invalid JSON';
  }
}
</script>

<template>
  <div class="json-editor">
    <label v-if="label" class="je-label">{{ label }}</label>
    <textarea
      :value="text"
      :style="{ minHeight: minHeight || '260px' }"
      spellcheck="false"
      @input="onInput"
    />
    <p v-if="error" class="je-error">⚠ {{ error }}</p>
  </div>
</template>

<style scoped>
.json-editor {
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.je-label {
  font-size: 11.5px;
  color: var(--text-dim);
  font-weight: 500;
}
textarea {
  font-family: var(--mono);
  font-size: 12.5px;
  line-height: 1.5;
  white-space: pre;
  tab-size: 2;
}
.je-error {
  margin: 0;
  color: var(--error);
  font-size: 12px;
  font-family: var(--mono);
}
</style>
