import { defineAsyncComponent } from 'vue';
import type { AdminPanel } from '../../core/types';

export default {
  id: 'dashboard',
  title: 'Dashboard',
  category: '',
  order: 1,
  icon: '◎',
  description: 'Server health, database/redis status, and quick actions.',
  component: defineAsyncComponent(() => import('./DashboardPanel.vue')),
} satisfies AdminPanel;
