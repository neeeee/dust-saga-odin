import type { AdminPanel } from './types';

/**
 * Auto-discovering panel registry.
 *
 * Every folder under `panels/<id>/index.ts` that default-exports an
 * `AdminPanel` is picked up here at build time via Vite's glob-import
 * mechanism (the call below). This is what makes the dashboard extendable:
 * to ship a new panel you only create `panels/<id>/index.ts` + its component
 * — no central registration, no nav edits, no router edits.
 *
 * `eager: true` is intentional: panel metadata (title/icon/order) is cheap
 * and needed up-front to render the sidebar. Heavy components stay lazy by
 * using `defineAsyncComponent` inside each panel index, so the actual view
 * bundle only loads when the user opens that panel.
 */
const moduleMap = import.meta.glob('../panels/*/index.ts', {
  eager: true,
}) as Record<string, { default?: AdminPanel }>;

function loadPanels(): AdminPanel[] {
  const found: AdminPanel[] = [];
  for (const path of Object.keys(moduleMap)) {
    const panel = moduleMap[path].default;
    if (!panel || typeof panel !== 'object' || !panel.id) {
      console.warn(`[registry] skipping ${path}: missing a default AdminPanel export`);
      continue;
    }
    found.push(panel);
  }

  const seen = new Set<string>();
  const deduped = found.filter(p => {
    if (seen.has(p.id)) {
      console.warn(`[registry] duplicate panel id "${p.id}" — ignoring later registration`);
      return false;
    }
    seen.add(p.id);
    return true;
  });

  deduped.sort((a, b) => (a.order ?? 1e6) - (b.order ?? 1e6));
  return deduped;
}

export const panels: readonly AdminPanel[] = loadPanels();

/** Panels grouped by `category` (preserving overall order), for nav rendering. */
export const panelGroups: ReadonlyArray<{ category: string; panels: AdminPanel[] }> = (() => {
  const groups = new Map<string, AdminPanel[]>();
  for (const p of panels) {
    const key = p.category ?? '';
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(p);
  }
  return [...groups.entries()].map(([category, items]) => ({ category, panels: items }));
})();

/** Look up a panel by id (falls back to the first panel). */
export function findPanel(id: string | null | undefined): AdminPanel | undefined {
  if (!id) return undefined;
  return panels.find(p => p.id === id);
}
