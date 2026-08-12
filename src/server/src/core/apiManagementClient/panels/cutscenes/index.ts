import { defineAsyncComponent } from 'vue';
import type { AdminPanel } from '../../core/types';

export default {
  id: 'cutscenes',
  title: 'Cutscenes',
  category: 'Content',
  order: 12,
  icon: '🎬',
  description: 'Create, edit and hot-reload cutscene definitions.',
  component: defineAsyncComponent(() => import('./CutscenesPanel.vue')),
} satisfies AdminPanel;
