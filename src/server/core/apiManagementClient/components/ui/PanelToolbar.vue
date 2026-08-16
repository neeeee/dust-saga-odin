<script setup lang="ts">
/**
 * Toolbar wrapper used at the top of every list view: a left-aligned slot for
 * search/filters and a right-aligned slot for actions (new, reload). Keeps
 * panel layouts consistent.
 */
</script>

<template>
  <div class="panel-toolbar">
    <div class="toolbar-left"><slot name="left" /></div>
    <div class="toolbar-right"><slot name="right" /></div>
  </div>
</template>

<style scoped>
.panel-toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 14px;
  flex-wrap: wrap;
}
.toolbar-left {
  display: flex;
  align-items: center;
  gap: 10px;
  flex: 1;
  min-width: 200px;
}
.toolbar-right {
  display: flex;
  align-items: center;
  gap: 8px;
}
</style>
