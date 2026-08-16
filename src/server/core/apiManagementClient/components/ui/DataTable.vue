<script setup lang="ts" generic="T extends Record<string, unknown>">
import { ref, computed } from 'vue';

/**
 * Generic data table with column definitions, optional sortable headers, and
 * a row-click handler. Columns describe how to render each cell so panels
 * don't reinvent table markup. Generic over the row type `T` so consumers get
 * typed row-click handlers and format functions.
 */
export interface Column<R> {
  key: string;
  label: string;
  width?: string;
  sortable?: boolean;
  align?: 'left' | 'right' | 'center';
  format?: (row: R) => string;
  /** Slot name for custom cell rendering: <template #cell-<key>="{ row }"> */
  slot?: string;
}

const props = defineProps<{
  rows: readonly T[];
  columns: Column<T>[];
  rowKey: string;
  loading?: boolean;
  emptyText?: string;
}>();

const emit = defineEmits<{ 'row-click': [row: T] }>();

const sortKey = ref<string | null>(null);
const sortDir = ref<'asc' | 'desc'>('asc');

function toggleSort(col: Column<T>): void {
  if (!col.sortable) return;
  if (sortKey.value === col.key) {
    sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc';
  } else {
    sortKey.value = col.key;
    sortDir.value = 'asc';
  }
}

const sortedRows = computed(() => {
  if (!sortKey.value) return props.rows;
  const key = sortKey.value;
  const dir = sortDir.value === 'asc' ? 1 : -1;
  return [...props.rows].sort((a, b) => {
    const av = a[key];
    const bv = b[key];
    if (av == null && bv == null) return 0;
    if (av == null) return 1;
    if (bv == null) return -1;
    if (typeof av === 'number' && typeof bv === 'number') {
      return (av - bv) * dir;
    }
    return String(av).localeCompare(String(bv)) * dir;
  });
});

function valueFor(row: T, col: Column<T>): string {
  if (col.format) return col.format(row);
  const v = row[col.key];
  if (v == null) return '';
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
}
</script>

<template>
  <div class="data-table">
    <div v-if="loading" class="dt-loading">Loading…</div>
    <table v-else>
      <thead>
        <tr>
          <th
            v-for="col in columns"
            :key="col.key"
            :style="{ width: col.width, textAlign: col.align || 'left' }"
            :class="{ sortable: col.sortable, active: sortKey === col.key }"
            @click="toggleSort(col)"
          >
            {{ col.label }}
            <span v-if="col.sortable && sortKey === col.key" class="sort-arrow">
              {{ sortDir === 'asc' ? '▲' : '▼' }}
            </span>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-if="!sortedRows.length">
          <td :colspan="columns.length" class="dt-empty">
            {{ emptyText || 'No data' }}
          </td>
        </tr>
        <tr
          v-for="row in sortedRows"
          :key="String(row[rowKey])"
          @click="emit('row-click', row)"
        >
          <td
            v-for="col in columns"
            :key="col.key"
            :style="{ textAlign: col.align || 'left' }"
          >
            <slot v-if="col.slot" :name="col.slot" :row="row" />
            <span v-else>{{ valueFor(row, col) }}</span>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.data-table {
  background: var(--bg-elev);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  overflow: hidden;
}
.dt-loading,
.dt-empty {
  padding: 28px;
  text-align: center;
  color: var(--text-faint);
}
table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}
thead th {
  background: var(--bg-elev-2);
  text-align: left;
  padding: 9px 12px;
  font-size: 11.5px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-dim);
  font-weight: 600;
  border-bottom: 1px solid var(--border);
  user-select: none;
  white-space: nowrap;
}
thead th.sortable {
  cursor: pointer;
}
thead th.sortable:hover {
  color: var(--text);
}
.sort-arrow {
  font-size: 9px;
  margin-left: 2px;
}
tbody td {
  padding: 9px 12px;
  border-bottom: 1px solid var(--border);
  vertical-align: top;
  max-width: 420px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
tbody tr:last-child td {
  border-bottom: none;
}
tbody tr {
  cursor: pointer;
  transition: background 0.08s;
}
tbody tr:hover {
  background: var(--bg-hover);
}
</style>
