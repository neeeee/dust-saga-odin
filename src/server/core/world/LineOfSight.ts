import { getZoneDefinition } from '@dust-saga/shared';
import { wallsBlockSight } from './WallRegistry';

const OBSTACLE_RADIUS: Record<string, number> = {
  house: 3.0,
  rock: 1.5,
  tree: 0.6,
  bush: 0.3,
};

/**
 * Clear line of sight between two actor positions.
 *
 * Two obstacle sources, both honored:
 *  - the zone's wall segments (WallRegistry: hit proxies + JSON colliders +
 *    blocking instances + bake structure faces — what the client collides
 *    against, exported by tools/wall_export.odin); zones with wall data are
 *    checked chest-height (y + 1.2) through the segment bands.
 *  - the legacy procedural obstacle circles (environmentObjects) for the
 *    older hand-authored zones.
 */
export function hasLineOfSight(
  zoneId: string,
  from: { x: number; y?: number; z: number },
  to: { x: number; y?: number; z: number }
): boolean {
  if (wallsBlockSight(zoneId, from, to)) return false;

  const zone = getZoneDefinition(zoneId);
  if (!zone) return true;

  const dx = to.x - from.x;
  const dz = to.z - from.z;
  const distSq = dx * dx + dz * dz;
  if (distSq < 1) return true;

  const dist = Math.sqrt(distSq);
  const dirX = dx / dist;
  const dirZ = dz / dist;

  for (const group of zone.environmentObjects) {
    const radius = OBSTACLE_RADIUS[group.type] ?? 1.0;
    const rSq = radius * radius;

    for (const obj of group.positions) {
      const fx = obj.x - from.x;
      const fz = obj.z - from.z;

      const projection = fx * dirX + fz * dirZ;
      if (projection < 0 || projection > dist) continue;

      const perpX = fx - projection * dirX;
      const perpZ = fz - projection * dirZ;
      const perpDistSq = perpX * perpX + perpZ * perpZ;

      if (perpDistSq < rSq) return false;
    }
  }

  return true;
}
