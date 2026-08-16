<script setup lang="ts">
import type { AdminPanel } from '../../core/types';

defineProps<{
  groups: ReadonlyArray<{ category: string; panels: AdminPanel[] }>;
  currentId: string;
}>();

const emit = defineEmits<{
  navigate: [id: string];
  logout: [];
}>();

function categoryLabel(category: string): string {
  return category || 'General';
}
</script>

<template>
  <aside class="nav">
    <div class="brand">
      <span class="brand-mark">◆</span>
      <div class="col">
        <strong>Dust Saga</strong>
        <small>API Management</small>
      </div>
    </div>

    <nav class="nav-list">
      <div v-for="group in groups" :key="group.category || '_'" class="nav-group">
        <div v-if="group.category" class="nav-cat">{{ categoryLabel(group.category) }}</div>
        <button
          v-for="panel in group.panels"
          :key="panel.id"
          class="nav-item"
          :class="{ active: panel.id === currentId }"
          :title="panel.description || panel.title"
          @click="emit('navigate', panel.id)"
        >
          <span class="nav-icon" v-if="panel.icon">{{ panel.icon }}</span>
          <span class="nav-label">{{ panel.title }}</span>
        </button>
      </div>
    </nav>

    <div class="nav-footer">
      <button class="ghost logout" @click="emit('logout')">Sign out</button>
    </div>
  </aside>
</template>

<style scoped>
.nav {
  width: 232px;
  flex-shrink: 0;
  background: var(--bg-elev);
  border-right: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  height: 100%;
}
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 18px 16px;
  border-bottom: 1px solid var(--border);
}
.brand-mark {
  color: var(--accent);
  font-size: 18px;
}
.brand strong {
  font-size: 14px;
}
.brand small {
  color: var(--text-faint);
  font-size: 11px;
}
.nav-list {
  flex: 1;
  overflow-y: auto;
  padding: 10px 8px;
}
.nav-group + .nav-group {
  margin-top: 10px;
}
.nav-cat {
  font-size: 10.5px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--text-faint);
  padding: 8px 10px 4px;
}
.nav-item {
  width: 100%;
  text-align: left;
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 8px 10px;
  border: 1px solid transparent;
  background: transparent;
  color: var(--text-dim);
  font-weight: 500;
}
.nav-item:hover {
  background: var(--bg-hover);
  color: var(--text);
}
.nav-item.active {
  background: var(--accent-dim);
  color: var(--accent);
  border-color: var(--accent-dim);
}
.nav-icon {
  width: 16px;
  text-align: center;
}
.nav-footer {
  padding: 10px 12px;
  border-top: 1px solid var(--border);
}
.logout {
  width: 100%;
  color: var(--text-dim);
}
</style>
