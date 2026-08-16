import { ref, computed } from 'vue';
import { api } from '../core/api';
import { notify } from './useNotify';
import type { CrudDescriptor } from '../core/types';

/**
 * Generic list + CRUD helper for resource panels that map onto a standard
 * admin REST shape:
 *
 *   GET    /admin/<resource>            -> { count, items|<resource> }
 *   GET    /admin/<resource>/:id        -> single resource
 *   POST   /admin/<resource>            -> create
 *   PUT    /admin/<resource>/:id        -> upsert
 *   DELETE /admin/<resource>/:id        -> delete
 *   POST   /admin/<schema>              -> reload
 *   GET    /admin/<resource>/schema     -> field docs (optional)
 *
 * Using this is opt-in — a panel only takes what it needs. The Items, Quests
 * and Cutscenes panels all wrap it so they stay ~30 lines of glue each.
 */
export function useCollection<T extends Record<string, unknown>>(
  descriptor: CrudDescriptor,
) {
  const idField = descriptor.idField ?? 'id';
  const items = ref<T[]>([]) as { value: T[] };
  const loading = ref(false);
  const error = ref<string | null>(null);
  const searchTerm = ref('');
  const totalCount = ref(0);
  const schema = ref<Record<string, string> | null>(null);

  const filtered = computed<T[]>(() => {
    const q = searchTerm.value.trim().toLowerCase();
    if (!q) return items.value;
    return items.value.filter(item => {
      const id = String(item[idField] ?? '').toLowerCase();
      const name = String((item as { name?: unknown }).name ?? '').toLowerCase();
      return id.includes(q) || name.includes(q);
    });
  });

  function extractArray(payload: unknown): T[] {
    if (Array.isArray(payload)) return payload as T[];
    if (payload && typeof payload === 'object') {
      const obj = payload as Record<string, unknown>;
      for (const key of ['items', 'quests', 'cutscenes', 'data', 'results']) {
        if (Array.isArray(obj[key])) return obj[key] as T[];
      }
    }
    return [];
  }

  async function load(query: Record<string, string> = {}): Promise<void> {
    loading.value = true;
    error.value = null;
    try {
      const qs = new URLSearchParams(query).toString();
      const path = qs ? `${descriptor.basePath}?${qs}` : descriptor.basePath;
      const res = await api.get<{ count?: number }>(path);
      items.value = extractArray(res.data);
      totalCount.value =
        (res.data as { count?: number })?.count ?? items.value.length;
    } catch (err) {
      error.value = err instanceof Error ? err.message : 'Failed to load';
      notify.error(error.value!);
    } finally {
      loading.value = false;
    }
  }

  async function fetchSchema(): Promise<void> {
    if (!descriptor.hasSchema) return;
    try {
      const res = await api.get<Record<string, string>>(
        `${descriptor.basePath}/schema`,
      );
      schema.value = res.data;
    } catch {
      schema.value = null;
    }
  }

  async function create(body: Partial<T>): Promise<T | null> {
    try {
      await api.post(`${descriptor.basePath}`, body);
      notify.success('Created');
      return body as T;
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Create failed';
      notify.error(msg);
      throw err;
    }
  }

  async function update(id: string, body: Partial<T>): Promise<void> {
    try {
      await api.put(`${descriptor.basePath}/${encodeURIComponent(id)}`, body);
      notify.success('Saved');
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Save failed';
      notify.error(msg);
      throw err;
    }
  }

  async function remove(id: string): Promise<boolean> {
    try {
      await api.del(`${descriptor.basePath}/${encodeURIComponent(id)}`);
      notify.success('Deleted');
      items.value = items.value.filter(i => String(i[idField]) !== id);
      return true;
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Delete failed';
      notify.error(msg);
      return false;
    }
  }

  async function reload(): Promise<void> {
    if (!descriptor.canReload) return;
    try {
      const res = await api.post<{ count?: number }>(`${descriptor.basePath}/reload`);
      notify.success('Reloaded');
      await load();
      void res;
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Reload failed';
      notify.error(msg);
    }
  }

  async function getOne(id: string): Promise<T | null> {
    try {
      const res = await api.get<T>(`${descriptor.basePath}/${encodeURIComponent(id)}`);
      return res.data;
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Fetch failed';
      notify.error(msg);
      return null;
    }
  }

  return {
    items,
    filtered,
    loading,
    error,
    searchTerm,
    totalCount,
    schema,
    idField,
    load,
    fetchSchema,
    getOne,
    create,
    update,
    remove,
    reload,
  };
}
