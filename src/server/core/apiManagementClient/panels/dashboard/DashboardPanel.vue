<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
import { api, rootApi } from '../../core/api';
import { notify } from '../../composables/useNotify';
import Loader from '../../components/ui/Loader.vue';
import ConfirmButton from '../../components/utils/ConfirmButton.vue';

interface Health {
  status: string;
  timestamp: string;
  database: string;
  redis: string;
}

const health = ref<Health | null>(null);
const loading = ref(false);
const error = ref<string | null>(null);
const lastUpdated = ref<Date | null>(null);
let timer: number | undefined;

async function refresh(): Promise<void> {
  loading.value = true;
  error.value = null;
  try {
    const res = await rootApi.get<Health>('/health');
    health.value = res.data;
    lastUpdated.value = new Date();
  } catch (err) {
    error.value = err instanceof Error ? err.message : 'Health check failed';
    notify.error(error.value!);
  } finally {
    loading.value = false;
  }
}

function statusColor(v: string | undefined): string {
  return v === 'ok' || v === 'connected' ? 'up' : 'down';
}

async function reloadItems(): Promise<void> {
  try {
    await api.post('/admin/items/reload');
    notify.success('Items reloaded');
  } catch (err) {
    notify.error(err instanceof Error ? err.message : 'Reload failed');
  }
}

onMounted(() => {
  void refresh();
  timer = window.setInterval(refresh, 15000);
});
onUnmounted(() => {
  if (timer) window.clearInterval(timer);
});
</script>

<template>
  <div class="dashboard">
    <div class="row" style="margin-bottom: 16px">
      <button @click="refresh" :disabled="loading">
        {{ loading ? 'Refreshing…' : 'Refresh' }}
      </button>
      <span v-if="lastUpdated" class="muted">Updated {{ lastUpdated.toLocaleTimeString() }}</span>
      <span class="spacer" />
    </div>

    <Loader v-if="loading && !health" label="Checking server…" />
    <p v-else-if="error && !health" class="error">{{ error }}</p>

    <div v-if="health" class="stat-grid">
      <div class="stat-card">
        <span class="stat-label">Server</span>
        <span class="stat-value" :class="statusColor(health.status)">
          {{ health.status === 'ok' ? '● Online' : '○ Offline' }}
        </span>
      </div>
      <div class="stat-card">
        <span class="stat-label">Postgres</span>
        <span class="stat-value" :class="statusColor(health.database)">
          ● {{ health.database }}
        </span>
      </div>
      <div class="stat-card">
        <span class="stat-label">Redis</span>
        <span class="stat-value" :class="statusColor(health.redis)">
          ● {{ health.redis }}
        </span>
      </div>
      <div class="stat-card">
        <span class="stat-label">Timestamp</span>
        <span class="stat-value mono small">{{ health.timestamp }}</span>
      </div>
    </div>

    <div class="quick-actions">
      <h3>Quick actions</h3>
      <div class="row">
        <ConfirmButton
          label="Reload items"
          confirm-label="Reload?"
          @confirm="reloadItems"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
.stat-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: 12px;
  margin-bottom: 24px;
}
.stat-card {
  background: var(--bg-elev);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.stat-label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-faint);
}
.stat-value {
  font-size: 16px;
  font-weight: 600;
}
.stat-value.up {
  color: var(--success);
}
.stat-value.down {
  color: var(--error);
}
.stat-value.small {
  font-size: 12.5px;
  font-weight: 400;
}
.mono {
  font-family: var(--mono);
}
.muted {
  color: var(--text-faint);
  font-size: 12px;
}
.quick-actions {
  border-top: 1px solid var(--border);
  padding-top: 16px;
}
.quick-actions h3 {
  margin: 0 0 12px;
  font-size: 13px;
  color: var(--text-dim);
}
.error {
  color: var(--error);
}
</style>
