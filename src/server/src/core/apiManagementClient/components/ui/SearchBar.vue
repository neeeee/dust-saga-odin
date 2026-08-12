<script setup lang="ts">
/**
 * A search/filter input wired to v-model, with a leading glyph and an optional
 * results count badge. Backs the list view in every CRUD panel.
 */
const props = withDefaults(
  defineProps<{
    modelValue: string;
    placeholder?: string;
    count?: number;
    total?: number;
  }>(),
  { placeholder: 'Search…', count: undefined, total: undefined },
);

const emit = defineEmits<{ 'update:modelValue': [value: string] }>();
</script>

<template>
  <div class="search-bar">
    <span class="sb-icon">⌕</span>
    <input
      :value="modelValue"
      :placeholder="placeholder"
      @input="emit('update:modelValue', ($event.target as HTMLInputElement).value)"
    />
    <span v-if="count !== undefined" class="sb-count">
      {{ count }}{{ total !== undefined ? ` / ${total}` : '' }}
    </span>
  </div>
</template>

<style scoped>
.search-bar {
  position: relative;
  display: flex;
  align-items: center;
  width: 100%;
  max-width: 420px;
}
.sb-icon {
  position: absolute;
  left: 10px;
  color: var(--text-faint);
  font-size: 14px;
  pointer-events: none;
}
.search-bar input {
  padding-left: 30px;
  padding-right: 64px;
}
.sb-count {
  position: absolute;
  right: 8px;
  font-size: 11px;
  color: var(--text-faint);
  background: var(--bg-elev-2);
  padding: 1px 7px;
  border-radius: 99px;
  pointer-events: none;
}
</style>
