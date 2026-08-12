<script setup lang="ts">
/**
 * Lightweight labelled text input. Two-way binds with v-model. Kept as a
 * presentational wrapper so panels get consistent field styling.
 */
withDefaults(
  defineProps<{
    modelValue?: string;
    label?: string;
    placeholder?: string;
    type?: string;
    disabled?: boolean;
    mono?: boolean;
  }>(),
  {
    modelValue: '',
    type: 'text',
    disabled: false,
    mono: false,
  },
);

const emit = defineEmits<{
  'update:modelValue': [value: string];
  enter: [];
}>();
</script>

<template>
  <label class="textbox">
    <span v-if="label" class="tb-label">{{ label }}</span>
    <input
      :type="type"
      :value="modelValue"
      :placeholder="placeholder"
      :disabled="disabled"
      :class="{ mono }"
      @input="emit('update:modelValue', ($event.target as HTMLInputElement).value)"
      @keyup.enter="emit('enter')"
    />
  </label>
</template>

<style scoped>
.textbox {
  display: flex;
  flex-direction: column;
  gap: 5px;
  width: 100%;
}
.tb-label {
  font-size: 11.5px;
  color: var(--text-dim);
  font-weight: 500;
}
input.mono {
  font-family: var(--mono);
}
</style>
