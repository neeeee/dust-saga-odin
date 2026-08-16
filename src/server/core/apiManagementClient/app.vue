<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { auth } from './core/auth';
import { panels, findPanel, panelGroups } from './core/registry';
import Nav from './components/ui/Nav.vue';
import Notification from './components/utils/Notification.vue';

const currentId = ref<string>('');

function readHash(): string {
  const h = window.location.hash.replace(/^#/, '');
  return h && findPanel(h) ? h : (panels[0]?.id ?? '');
}

function onHashChange(): void {
  currentId.value = readHash();
}

function navigate(id: string): void {
  window.location.hash = id;
}

const currentPanel = computed(() => findPanel(currentId.value));

let initialized = false;
onMounted(() => {
  window.addEventListener('hashchange', onHashChange);
  currentId.value = readHash();
  if (!initialized) {
    initialized = true;
    if (auth.state.token && auth.state.status !== 'authenticated') {
      void auth.verify();
    }
  }
});
onUnmounted(() => window.removeEventListener('hashchange', onHashChange));

const checking = computed(() => auth.state.status === 'checking');
const needsLogin = computed(
  () => auth.state.status === 'unauthenticated' || auth.state.status === 'unknown',
);
</script>

<template>
  <Notification />

  <div v-if="needsLogin && !checking" class="login-screen">
    <form
      class="login-card"
      @submit.prevent="auth.login(($event.target as HTMLFormElement).token.value)"
    >
      <h1>Dust Saga</h1>
      <p class="login-sub">API Management Dashboard</p>
      <label>Admin Token</label>
      <input
        name="token"
        type="password"
        autocomplete="current-password"
        placeholder="ADMIN_TOKEN"
        :value="auth.state.token"
        autofocus
      />
      <p v-if="auth.state.error" class="login-error">{{ auth.state.error }}</p>
      <button type="submit" class="primary">Sign in</button>
      <p class="login-hint">
        The token is the server's <code>ADMIN_TOKEN</code> env var. It is stored
        only in this browser's localStorage.
      </p>
    </form>
  </div>

  <div v-else-if="checking" class="login-screen">
    <p class="login-sub">Verifying token…</p>
  </div>

  <div v-else class="shell">
    <Nav
      :groups="panelGroups"
      :current-id="currentId"
      @navigate="navigate"
      @logout="auth.logout()"
    />
    <main class="content">
      <header class="content-header" v-if="currentPanel">
        <div class="col">
          <h2>
            <span class="panel-icon" v-if="currentPanel.icon">{{ currentPanel.icon }}</span>
            {{ currentPanel.title }}
          </h2>
          <p v-if="currentPanel.description" class="panel-desc">
            {{ currentPanel.description }}
          </p>
        </div>
      </header>
      <section class="content-body">
        <component :is="currentPanel.component" v-if="currentPanel" />
        <p v-else class="empty">No panels registered.</p>
      </section>
    </main>
  </div>
</template>

<style scoped>
.login-screen {
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--bg);
}
.login-card {
  width: 380px;
  max-width: 92vw;
  background: var(--bg-elev);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 28px;
  box-shadow: var(--shadow);
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.login-card h1 {
  margin: 0;
  font-size: 22px;
}
.login-sub {
  margin: 0 0 8px;
  color: var(--text-dim);
}
.login-error {
  margin: 0;
  color: var(--error);
  font-size: 12.5px;
}
.login-hint {
  margin: 8px 0 0;
  color: var(--text-faint);
  font-size: 11.5px;
  line-height: 1.45;
}
.login-card label {
  font-size: 12px;
  color: var(--text-dim);
  margin-top: 6px;
}
.shell {
  height: 100%;
  display: flex;
}
.content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
.content-header {
  padding: 18px 24px;
  border-bottom: 1px solid var(--border);
  background: var(--bg-elev);
}
.content-header h2 {
  margin: 0;
  font-size: 17px;
  display: flex;
  align-items: center;
  gap: 8px;
}
.panel-icon {
  font-size: 18px;
}
.panel-desc {
  margin: 4px 0 0;
  color: var(--text-dim);
  font-size: 12.5px;
}
.content-body {
  flex: 1;
  overflow: auto;
  padding: 20px 24px;
}
.empty {
  color: var(--text-faint);
}
</style>
