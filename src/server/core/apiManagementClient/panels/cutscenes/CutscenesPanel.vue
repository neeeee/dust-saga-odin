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

interface CutsceneDef {
  id: string;
  [k: string]: unknown;
}

const col = useCollection<CutsceneDef>({
  basePath: '/admin/cutscenes',
  idField: 'id',
  hasSchema: false,
  canReload: true,
});

const editorOpen = ref(false);
const editing = ref<Partial<CutsceneDef> | null>(null);
const isNew = ref(false);
const draft = ref<unknown>(null);

const columns: Column<CutsceneDef>[] = [
  { key: 'id', label: 'ID', sortable: true },
  { key: 'trigger', label: 'Trigger', width: '140px' },
  {
    key: 'pages',
    label: 'Pages',
    align: 'right',
    width: '70px',
    format: (row) => String((row as { pages?: unknown[] }).pages?.length ?? 0),
  },
];

function openNew(): void {
  isNew.value = true;
  editing.value = { id: '' };
  draft.value = { id: '', trigger: 'manual', pages: [] };
  editorOpen.value = true;
}

function openEdit(row: CutsceneDef): void {
  isNew.value = false;
  editing.value = row;
  draft.value = JSON.parse(JSON.stringify(row));
  editorOpen.value = true;
}

async function save(): Promise<void> {
  const body = draft.value as Partial<CutsceneDef> | null;
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

async function remove(row: CutsceneDef): Promise<void> {
  if (await col.remove(row.id)) await col.load();
}

onMounted(() => col.load());
</script>

<template>
  <div>
    <PanelToolbar>
      <template #left>
        <SearchBar
          v-model="col.searchTerm.value"
          :count="col.filtered.value.length"
          :total="col.totalCount.value"
          placeholder="Search id…"
        />
      </template>
      <template #right>
        <ConfirmButton label="Reload" confirm-label="Reload?" @confirm="col.reload()" />
        <button class="primary" @click="openNew">+ New cutscene</button>
      </template>
    </PanelToolbar>

    <DataTable
      :rows="col.filtered.value"
      :columns="columns"
      row-key="id"
      :loading="col.loading.value"
      :empty-text="col.error.value || 'No cutscenes'"
      @row-click="openEdit"
    />

    <Modal
      :open="editorOpen"
      :title="isNew ? 'Create cutscene' : `Edit ${editing?.id ?? ''}`"
      width="720px"
      @close="editorOpen = false"
    >
      <JsonEditor v-model="draft" label="Cutscene definition (JSON)" min-height="340px" />

      <template #actions>
        <CancelButton @cancel="editorOpen = false" />
        <button v-if="!isNew" class="danger" @click="editing && remove(editing as CutsceneDef)">
          Delete
        </button>
        <button class="primary" @click="save">Save</button>
      </template>
    </Modal>
  </div>
</template>
