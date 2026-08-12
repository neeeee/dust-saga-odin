import type { Component } from 'vue';

/**
 * Contract every dashboard panel implements.
 *
 * A panel is a self-contained view (e.g. "Items", "Quests", "Live Ops").
 * Panels are auto-discovered by the registry — see `core/registry.ts` — so
 * adding a new panel does NOT require editing any central file. Drop a folder
 * under `panels/<id>/index.ts` that default-exports an `AdminPanel` and it
 * shows up in the nav automatically.
 *
 * Example `panels/widgets/index.ts`:
 *
 *   import { defineAsyncComponent } from 'vue';
 *   import type { AdminPanel } from '../../core/types';
 *   export default {
 *     id: 'widgets',
 *     title: 'Widgets',
 *     category: 'Content',
 *     order: 30,
 *     icon: '◆',
 *     component: defineAsyncComponent(() => import('./WidgetsPanel.vue')),
 *   } satisfies AdminPanel;
 */
export interface AdminPanel {
  /** Unique id; used as the URL hash (#widgets). Lowercase, kebab-case. */
  id: string;
  /** Label shown in the sidebar nav. */
  title: string;
  /** Optional nav grouping header (panels with the same category cluster). */
  category?: string;
  /** Sort weight within the whole nav (ascending). Defaults to a large number. */
  order?: number;
  /** Single glyph / emoji rendered before the title. Optional. */
  icon?: string;
  /** Vue component (or async loader) rendered when the panel is active. */
  component: Component | (() => Promise<Component>);
  /** Short tooltip / subtitle. Optional. */
  description?: string;
}

/** Standard CRUD capability description a panel can advertise to the registry. */
export interface CrudDescriptor {
  /** Base admin API path, e.g. '/admin/items'. */
  basePath: string;
  /** Field used as the primary key (usually 'id'). */
  idField?: string;
  /** Whether this resource exposes GET /schema for form rendering. */
  hasSchema?: boolean;
  /** Whether hot-reload (POST /reload) is supported. */
  canReload?: boolean;
}

/** Result of an authenticated API call. */
export interface ApiResult<T = unknown> {
  ok: boolean;
  status: number;
  data: T;
}

/** Error thrown by the API client for non-2xx responses. */
export class ApiError extends Error {
  status: number;
  body: unknown;
  constructor(message: string, status: number, body: unknown) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.body = body;
  }
}
