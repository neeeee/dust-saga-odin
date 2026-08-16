import { defineAsyncComponent } from 'vue';
import type { AdminPanel } from '../../core/types';

export default {
  id: 'items',
  title: 'Items',
  category: 'Content',
  order: 10,
  icon: '⚔',
  description: 'Create, edit and hot-reload item definitions.',
  component: defineAsyncComponent(() => import('./ItemsPanel.vue')),
} satisfies AdminPanel;
