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

interface QuestDef {
  id: string;
  title: string;
  type: string;
  npcId: string;
  requiredLevel: number;
  [k: string]: unknown;
}

const col = useCollection<QuestDef>({
  basePath: '/admin/quests',
  idField: 'id',
  hasSchema: true,
  canReload: true,
});

const editorOpen = ref(false);
const editing = ref<Partial<QuestDef> | null>(null);
const isNew = ref(false);
const draft = ref<unknown>(null);

const columns: Column<QuestDef>[] = [
  { key: 'id', label: 'ID', sortable: true, width: '200px' },
  { key: 'title', label: 'Title', sortable: true },
  { key: 'type', label: 'Type', sortable: true, width: '100px' },
  { key: 'npcId', label: 'NPC', sortable: true, width: '140px' },
  { key: 'requiredLevel', label: 'Lvl', sortable: true, align: 'right', width: '60px' },
];

function openNew(): void {
  isNew.value = true;
  editing.value = { id: '', title: '', type: 'kill', npcId: '', requiredLevel: 1 };
  draft.value = { ...editing.value };
  editorOpen.value = true;
}

function openEdit(row: QuestDef): void {
  isNew.value = false;
  editing.value = row;
  draft.value = JSON.parse(JSON.stringify(row));
  editorOpen.value = true;
}

async function save(): Promise<void> {
  const body = draft.value as Partial<QuestDef> | null;
  if (!body) return;
  try {
    if (isNew.value) await col.create(body);
    else await col.update(body.id!, body);
    editorOpen.value = false;
    await col.load();
  } catch {
    /* handled */
  }
}

async function remove(row: QuestDef): Promise<void> {
  if (await col.remove(row.id)) await col.load();
}

onMounted(async () => {
  await col.fetchSchema();
  await col.load();
});
</script>

<template>
  <div>
    <PanelToolbar>
      <template #left>
        <SearchBar
          v-model="col.searchTerm.value"
          :count="col.filtered.value.length"
          :total="col.totalCount.value"
          placeholder="Search id or title…"
        />
      </template>
      <template #right>
        <ConfirmButton label="Reload" confirm-label="Reload?" @confirm="col.reload()" />
        <button class="primary" @click="openNew">+ New quest</button>
      </template>
    </PanelToolbar>

    <DataTable
      :rows="col.filtered.value"
      :columns="columns"
      row-key="id"
      :loading="col.loading.value"
      :empty-text="col.error.value || 'No quests'"
      @row-click="openEdit"
    />

    <Modal
      :open="editorOpen"
      :title="isNew ? 'Create quest' : `Edit ${editing?.id ?? ''}`"
      width="720px"
      @close="editorOpen = false"
    >
      <div v-if="col.schema.value" class="schema-hint">
        <details>
          <summary>Field schema</summary>
          <pre>{{ JSON.stringify(col.schema.value, null, 2) }}</pre>
        </details>
      </div>
      <JsonEditor v-model="draft" label="Quest definition (JSON)" min-height="340px" />

      <template #actions>
        <CancelButton @cancel="editorOpen = false" />
        <button v-if="!isNew" class="danger" @click="editing && remove(editing as QuestDef)">
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
