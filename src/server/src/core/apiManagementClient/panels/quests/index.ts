import { defineAsyncComponent } from 'vue';
import type { AdminPanel } from '../../core/types';

export default {
  id: 'quests',
  title: 'Quests',
  category: 'Content',
  order: 11,
  icon: '✦',
  description: 'Create, edit and hot-reload quest definitions.',
  component: defineAsyncComponent(() => import('./QuestsPanel.vue')),
} satisfies AdminPanel;
