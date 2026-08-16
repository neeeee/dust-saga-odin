import { defineAsyncComponent } from 'vue';
import type { AdminPanel } from '../../core/types';

export default {
  id: 'api-explorer',
  title: 'API Explorer',
  category: 'Tools',
  order: 90,
  icon: '⌘',
  description: 'Send arbitrary requests to any admin endpoint — the escape hatch for APIs without a dedicated panel yet.',
  component: defineAsyncComponent(() => import('./ApiExplorerPanel.vue')),
} satisfies AdminPanel;
