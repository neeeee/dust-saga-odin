<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { useCollection } from '../../composables/useCollection';
import type { Column } from '../../components/ui/DataTable.vue';
import DataTable from '../../components/ui/DataTable.vue';
import Modal from '../../components/ui/Modal.vue';
import JsonEditor from '../../components/ui/JsonEditor.vue';
import SearchBar from '../../components/ui/SearchBar.vue';
import PanelToolbar from '../../components/ui/PanelToolbar.vue';
import ConfirmButton from '../../components/utils/ConfirmButton.vue';
import CancelButton from '../../components/utils/CancelButton.vue';

interface ItemDef {
  id: string;
  name: string;
  type: string;
  rarity: string;
  requiredLevel: number;
  [k: string]: unknown;
}

const col = useCollection<ItemDef>({
  basePath: '/admin/items',
  idField: 'id',
  hasSchema: true,
  canReload: true,
});

const typeFilter = ref('');
const editorOpen = ref(false);
const editing = ref<Partial<ItemDef> | null>(null);
const isNew = ref(false);
const draft = ref<unknown>(null);

const columns: Column<ItemDef>[] = [
  { key: 'id', label: 'ID', sortable: true, width: '200px' },
  { key: 'name', label: 'Name', sortable: true },
  { key: 'type', label: 'Type', sortable: true, width: '110px' },
  {
    key: 'rarity',
    label: 'Rarity',
    sortable: true,
    width: '110px',
    slot: 'cell-rarity',
  },
  { key: 'requiredLevel', label: 'Lvl', sortable: true, align: 'right', width: '60px' },
];

function openNew(): void {
  isNew.value = true;
  editing.value = { id: '', name: '', type: 'consumable', rarity: 'common', requiredLevel: 1 };
  draft.value = { ...editing.value };
  editorOpen.value = true;
}

function openEdit(row: ItemDef): void {
  isNew.value = false;
  editing.value = row;
  draft.value = JSON.parse(JSON.stringify(row));
  editorOpen.value = true;
}

async function save(): Promise<void> {
  const body = draft.value as Partial<ItemDef> | null;
  if (!body) return;
  try {
    if (isNew.value) {
      await col.create(body);
    } else {
      await col.update(body.id!, body);
    }
    editorOpen.value = false;
    await col.load();
  } catch {
    /* notify handled in useCollection */
  }
}

async function remove(row: ItemDef): Promise<void> {
  const ok = await col.remove(row.id);
  if (ok) await col.load();
}

onMounted(async () => {
  await col.fetchSchema();
  await col.load();
});

function applyTypeFilter(): void {
  const q: Record<string, string> = {};
  if (typeFilter.value) q.type = typeFilter.value;
  void col.load(q);
}
</script>

<template>
  <div>
    <PanelToolbar>
      <template #left>
        <SearchBar
          v-model="col.searchTerm.value"
          :count="col.filtered.value.length"
          :total="col.totalCount.value"
          placeholder="Search id or name…"
        />
        <select v-model="typeFilter" @change="applyTypeFilter" style="max-width: 150px">
          <option value="">All types</option>
          <option v-for="t in ['weapon','armor','helmet','boots','gloves','legs','shield','earring','necklace','belt','ring','accessory','consumable','material','recipe','quest']" :key="t" :value="t">{{ t }}</option>
        </select>
      </template>
      <template #right>
        <ConfirmButton label="Reload" confirm-label="Reload?" @confirm="col.reload()" />
        <button class="primary" @click="openNew">+ New item</button>
      </template>
    </PanelToolbar>

    <DataTable
      :rows="col.filtered.value"
      :columns="columns"
      row-key="id"
      :loading="col.loading.value"
      :empty-text="col.error.value || 'No items'"
      @row-click="openEdit"
    >
      <template #cell-rarity="{ row }">
        <span class="badge" :class="(row as ItemDef).rarity">{{ (row as ItemDef).rarity }}</span>
      </template>
    </DataTable>

    <Modal
      :open="editorOpen"
      :title="isNew ? 'Create item' : `Edit ${editing?.id ?? ''}`"
      width="720px"
      @close="editorOpen = false"
    >
      <div v-if="col.schema.value" class="schema-hint">
        <details>
          <summary>Field schema ({{ Object.keys(col.schema.value).length }} fields)</summary>
          <pre>{{ JSON.stringify(col.schema.value, null, 2) }}</pre>
        </details>
      </div>
      <JsonEditor v-model="draft" label="Item definition (JSON)" min-height="320px" />

      <template #actions>
        <CancelButton @cancel="editorOpen = false" />
        <button
          v-if="!isNew"
          class="danger"
          @click="editing && remove(editing as ItemDef)"
        >
          Delete
        </button>
        <button class="primary" @click="save">Save</button>
      </template>
    </Modal>
  </div>
</template>

<style scoped>
.schema-hint {
  margin-bottom: 12px;
}
.schema-hint summary {
  cursor: pointer;
  color: var(--text-dim);
  font-size: 12px;
}
.schema-hint pre {
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 10px;
  max-height: 180px;
  overflow: auto;
}
</style>
