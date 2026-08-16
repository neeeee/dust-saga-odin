<script setup lang="ts">
import { ref, computed } from 'vue';
import { rootApi } from '../../core/api';

/**
 * Generic request builder. Lets an operator hit any server endpoint with any
 * method/body — useful for endpoints that don't yet have a dedicated panel, or
 * for ad-hoc debugging. Demonstrates that the dashboard degrades gracefully:
 * new APIs are usable the moment they ship, before a UI is built for them.
 *
 * Paths are absolute (from server root), e.g. `/health`, `/api/admin/items`.
 * Uses the root client so both `/health` and `/api/...` work as typed.
 */

type Method = 'GET' | 'POST' | 'PUT' | 'DELETE';

const method = ref<Method>('GET');
const path = ref('/api/admin/items');
const bodyText = ref('');
const response = ref<unknown>(null);
const status = ref<number | null>(null);
const elapsed = ref<number | null>(null);
const error = ref<string | null>(null);
const sending = ref(false);

const presets: { label: string; method: Method; path: string }[] = [
  { label: 'Health', method: 'GET', path: '/health' },
  { label: 'Classes', method: 'GET', path: '/api/classes' },
  { label: 'List items', method: 'GET', path: '/api/admin/items' },
  { label: 'Item schema', method: 'GET', path: '/api/admin/items/schema' },
  { label: 'List quests', method: 'GET', path: '/api/admin/quests' },
  { label: 'List cutscenes', method: 'GET', path: '/api/admin/cutscenes' },
];

const hasBody = computed(() => method.value === 'POST' || method.value === 'PUT');

function applyPreset(p: { method: Method; path: string }): void {
  method.value = p.method;
  path.value = p.path;
}

function formattedResponse(): string {
  if (response.value == null) return '';
  try {
    return JSON.stringify(response.value, null, 2);
  } catch {
    return String(response.value);
  }
}

async function send(): Promise<void> {
  response.value = null;
  status.value = null;
  elapsed.value = null;
  error.value = null;
  sending.value = true;
  const started = performance.now();
  try {
    let body: unknown = undefined;
    if (hasBody.value && bodyText.value.trim()) {
      body = JSON.parse(bodyText.value);
    }
    let res;
    switch (method.value) {
      case 'GET':
        res = await rootApi.get(path.value);
        break;
      case 'DELETE':
        res = await rootApi.del(path.value);
        break;
      case 'POST':
        res = await rootApi.post(path.value, body);
        break;
      case 'PUT':
        res = await rootApi.put(path.value, body);
        break;
    }
    response.value = res.data;
    status.value = res.status;
  } catch (err) {
    error.value = err instanceof Error ? err.message : 'Request failed';
    status.value = (err as { status?: number }).status ?? null;
    response.value = (err as { body?: unknown }).body ?? null;
  } finally {
    elapsed.value = Math.round(performance.now() - started);
    sending.value = false;
  }
}
</script>

<template>
  <div class="explorer">
    <div class="presets">
      <span class="muted">Quick fill:</span>
      <button v-for="p in presets" :key="p.label" class="ghost small" @click="applyPreset(p)">
        {{ p.label }}
      </button>
    </div>

    <div class="request-bar">
      <select v-model="method" class="method-select">
        <option>GET</option>
        <option>POST</option>
        <option>PUT</option>
        <option>DELETE</option>
      </select>
      <input
        v-model="path"
        class="path-input"
        spellcheck="false"
        placeholder="/api/admin/items"
      />
      <button class="primary" :disabled="sending" @click="send">
        {{ sending ? 'Sending…' : 'Send' }}
      </button>
    </div>
    <p class="muted hint">Path is absolute from the server root, e.g. <code>/health</code> or <code>/api/admin/items</code>. The token header is attached automatically.</p>

    <textarea
      v-if="hasBody"
      v-model="bodyText"
      class="body-input"
      placeholder='JSON body, e.g. {"id": "test"}'
      spellcheck="false"
    />

    <div v-if="status !== null || error" class="response-head">
      <span class="badge" :class="status && status < 400 ? 'rare' : 'common'">
        {{ status ?? '—' }}
      </span>
      <span v-if="error" class="err">{{ error }}</span>
      <span v-if="elapsed !== null" class="muted">{{ elapsed }} ms</span>
    </div>

    <pre v-if="response !== null" class="response-body">{{ formattedResponse() }}</pre>
  </div>
</template>

<style scoped>
.explorer {
  display: flex;
  flex-direction: column;
  gap: 12px;
  max-width: 900px;
}
.presets {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
}
.small {
  padding: 3px 9px;
  font-size: 12px;
}
.request-bar {
  display: flex;
  gap: 8px;
}
.method-select {
  width: 100px;
  flex-shrink: 0;
  font-weight: 600;
}
.path-input {
  font-family: var(--mono);
  flex: 1;
}
.hint {
  font-size: 11.5px;
  margin: -4px 0 0;
}
.body-input {
  min-height: 120px;
  font-family: var(--mono);
  font-size: 12.5px;
}
.response-head {
  display: flex;
  align-items: center;
  gap: 10px;
}
.err {
  color: var(--error);
  font-size: 13px;
}
.response-body {
  background: var(--bg-elev);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 14px;
  max-height: 520px;
  overflow: auto;
  margin: 0;
  white-space: pre-wrap;
  word-break: break-word;
}
.muted {
  color: var(--text-faint);
  font-size: 12px;
}
</style>
