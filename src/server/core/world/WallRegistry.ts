import * as fs from 'fs';
import * as path from 'path';

/**
 * Server-side wall collision, generated from the client's heightfield build
 * (tools/wall_export.odin): the same segments the Odin client collides
 * against — original _hit.dxg proxies, JSON colliders, blocking instance
 * footprints, and structure faces extracted from the visual bake (steep
 * non-terrain triangles). See src/client/systems/terrain_collision.odin.
 *
 * Zone wall sets live in data/zone_walls.json as
 *   { lists: [[[x1,z1,x2,z2,yMin,yMax,move?], ...], ...],
 *     zones: { "<zoneId>": <listIndex> } }
 * (zones sharing a terrain bake share a list). A zone's walls are parsed and
 * hashed lazily on first use; zones without walls (procedural maps) report
 * no walls and everything stays visible/passable.
 */

interface WallSeg {
  x1: number; z1: number;
  x2: number; z2: number;
  yMin: number;
  yMax: number;
  move: boolean; // blocks movement/knockback (vs LOS-only band)
}

const GRID_CELL = 8;

class ZoneWalls {
  readonly segs: WallSeg[];
  private readonly originX: number;
  private readonly originZ: number;
  private readonly cols: number;
  private readonly rows: number;
  private readonly buckets: number[][];
  constructor(segs: WallSeg[]) {
    this.segs = segs;
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    for (const s of segs) {
      minX = Math.min(minX, s.x1, s.x2);
      maxX = Math.max(maxX, s.x1, s.x2);
      minZ = Math.min(minZ, s.z1, s.z2);
      maxZ = Math.max(maxZ, s.z1, s.z2);
    }
    this.originX = minX;
    this.originZ = minZ;
    this.cols = Math.max(1, Math.ceil((maxX - minX) / GRID_CELL) + 1);
    this.rows = Math.max(1, Math.ceil((maxZ - minZ) / GRID_CELL) + 1);
    this.buckets = Array.from({ length: this.cols * this.rows }, () => []);
    for (let i = 0; i < segs.length; i++) {
      const s = segs[i];
      const c0 = this.colOf(Math.min(s.x1, s.x2));
      const c1 = this.colOf(Math.max(s.x1, s.x2));
      const r0 = this.rowOf(Math.min(s.z1, s.z2));
      const r1 = this.rowOf(Math.max(s.z1, s.z2));
      for (let r = r0; r <= r1; r++) {
        for (let c = c0; c <= c1; c++) {
          this.buckets[r * this.cols + c].push(i);
        }
      }
    }
  }

  private colOf(x: number): number {
    return Math.max(0, Math.min(this.cols - 1, Math.floor((x - this.originX) / GRID_CELL)));
  }
  private rowOf(z: number): number {
    return Math.max(0, Math.min(this.rows - 1, Math.floor((z - this.originZ) / GRID_CELL)));
  }

  /** Is (x,z) inside the wall cloud's footprint (with margin)? Positions
   * outside it are off the terrain entirely — the void around the bake. */
  contains(x: number, z: number, margin = 50): boolean {
    return x >= this.originX - margin && x <= this.originX + this.cols * GRID_CELL + margin
      && z >= this.originZ - margin && z <= this.originZ + this.rows * GRID_CELL + margin;
  }

  /** Candidate segment indices in every grid cell the line's AABB covers. */
  private candidates(fx: number, fz: number, tx: number, tz: number): number[] | null {
    const c0 = this.colOf(Math.min(fx, tx));
    const c1 = this.colOf(Math.max(fx, tx));
    const r0 = this.rowOf(Math.min(fz, tz));
    const r1 = this.rowOf(Math.max(fz, tz));
    if (c0 === c1 && r0 === r1) return this.buckets[r0 * this.cols + c0];
    let out: number[] | null = null;
    for (let r = r0; r <= r1; r++) {
      for (let c = c0; c <= c1; c++) {
        const b = this.buckets[r * this.cols + c];
        if (b.length === 0) continue;
        if (!out) out = [];
        out.push(...b);
      }
    }
    return out;
  }

  /**
   * Does a wall cross the segment (fx,fz)→(tx,tz)? When `moveOnly`, only
   * movement-blocking walls count (knockback); otherwise every band blocks
   * at its own height. `yAt` samples the traveling height at a crossing
   * (line of sight flies chest height; a knockback slides at body height).
   */
  crossing(
    fx: number, fz: number, fy: number,
    tx: number, tz: number, ty: number,
    moveOnly: boolean,
    yMargin = 0.1
  ): boolean {
    const dx = tx - fx;
    const dz = tz - fz;
    const len = Math.hypot(dx, dz);
    if (len < 1e-6) return false;
    const ux = dx / len;
    const uz = dz / len;
    const cand = this.candidates(fx, fz, tx, tz);
    if (!cand) return false;
    for (const si of cand) {
      const s = this.segs[si];
      if (moveOnly && !s.move) continue;
      const ex = s.x2 - s.x1;
      const ez = s.z2 - s.z1;
      const denom = ux * ez - uz * ex;
      if (Math.abs(denom) < 1e-9) continue;
      const ox = s.x1 - fx;
      const oz = s.z1 - fz;
      const t = (ox * ez - oz * ex) / denom;
      if (t <= 0.01 || t >= len - 0.01) continue;
      const u = (ox * uz - oz * ux) / denom;
      if (u < 0 || u > 1) continue;
      const h = fy + (ty - fy) * (t / len);
      if (h < s.yMin + yMargin || h > s.yMax - yMargin) continue;
      return true;
    }
    return false;
  }

  /**
   * Furthest point along (fx,fz)→(tx,tz) before the first
   * movement-blocking wall that spans the traveler's body [y, y+height].
   * Returns the original destination when unobstructed.
   */
  clampStep(
    fx: number, fz: number,
    tx: number, tz: number,
    y: number, height: number
  ): { x: number; z: number; blocked: boolean } {
    const dx = tx - fx;
    const dz = tz - fz;
    const len = Math.hypot(dx, dz);
    if (len < 1e-6) return { x: tx, z: tz, blocked: false };
    const ux = dx / len;
    const uz = dz / len;
    const cand = this.candidates(fx, fz, tx, tz);
    if (!cand) return { x: tx, z: tz, blocked: false };
    let bestT = len;
    for (const si of cand) {
      const s = this.segs[si];
      if (!s.move) continue;
      // band must span the traveler's body
      if (s.yMax <= y + 0.1 || s.yMin >= y + height - 0.1) continue;
      const ex = s.x2 - s.x1;
      const ez = s.z2 - s.z1;
      const denom = ux * ez - uz * ex;
      if (Math.abs(denom) < 1e-9) continue;
      const ox = s.x1 - fx;
      const oz = s.z1 - fz;
      const t = (ox * ez - oz * ex) / denom;
      if (t <= 0.0 || t >= bestT) continue;
      const u = (ox * uz - oz * ux) / denom;
      if (u < 0 || u > 1) continue;
      bestT = t;
    }
    if (bestT >= len) return { x: tx, z: tz, blocked: false };
    // stop just short of the wall
    const t = Math.max(0, bestT - 0.05);
    return { x: fx + ux * t, z: fz + uz * t, blocked: true };
  }
}

let rawLists: number[][][] | null = null;
let rawZones: Record<string, number> | null = null;
let loadAttempted = false;
const builtLists = new Map<number, ZoneWalls>();

function loadRaw(): void {
  if (loadAttempted) return;
  loadAttempted = true;
  const candidates = [
    path.join(__dirname, '..', '..', 'data', 'zone_walls.json'), // tsx (src) and dist-with-data
    path.join(__dirname, '..', '..', '..', 'data', 'zone_walls.json'), // dist without copied data
    path.join(process.cwd(), 'data', 'zone_walls.json'),
  ];
  for (const p of candidates) {
    try {
      if (!fs.existsSync(p)) continue;
      const parsed = JSON.parse(fs.readFileSync(p, 'utf8'));
      if (Array.isArray(parsed.lists) && parsed.zones) {
        rawLists = parsed.lists;
        rawZones = parsed.zones;
        return;
      }
    } catch {
      // try the next candidate
    }
  }
}

/** Wall set for a zone (null when the zone has no wall data). */
export function getZoneWalls(zoneId: string | undefined): ZoneWalls | null {
  if (!zoneId) return null;
  loadRaw();
  if (!rawLists || !rawZones) return null;
  const idx = rawZones[zoneId];
  if (idx === undefined) return null;
  let walls = builtLists.get(idx);
  if (!walls) {
    const segs: WallSeg[] = rawLists[idx].map((a: number[]) => ({
      x1: a[0], z1: a[1], x2: a[2], z2: a[3],
      yMin: a[4], yMax: a[5],
      move: (a[6] ?? 1) !== 0,
    }));
    walls = new ZoneWalls(segs);
    builtLists.set(idx, walls);
  }
  return walls;
}

/**
 * Is (x,z) plausibly inside the zone's playable footprint? Zones with wall
 * data use the wall-cloud bounds (+margin); zones without fall back to a
 * size/2 box around the origin (procedural planes are centered there).
 * Used to heal characters saved out in the void by stale warp targets.
 */
export function zonePositionInBounds(
  zoneId: string | undefined,
  x: number, z: number,
  zoneSize = 2000
): boolean {
  const walls = getZoneWalls(zoneId);
  if (walls) return walls.contains(x, z);
  const half = Math.max(zoneSize, 2000) / 2 + 100;
  return Math.abs(x) <= half && Math.abs(z) <= half;
}

/**
 * Clear chest-height (1.2) line of sight between two actor positions.
 * Zones without wall data are fully visible.
 */
export function wallsBlockSight(
  zoneId: string | undefined,
  from: { x: number; y?: number; z: number },
  to: { x: number; y?: number; z: number }
): boolean {
  const walls = getZoneWalls(zoneId);
  if (!walls) return false;
  return walls.crossing(
    from.x, from.z, (from.y ?? 0) + 1.2,
    to.x, to.z, (to.y ?? 0) + 1.2,
    false
  );
}

/**
 * Clamp a horizontal step (knockback tick, AI shove) against
 * movement-blocking walls spanning the traveler's body. Returns the
 * furthest unobstructed point.
 */
export function clampMovement(
  zoneId: string | undefined,
  from: { x: number; y?: number; z: number },
  to: { x: number; z: number }
): { x: number; z: number; blocked: boolean } {
  const walls = getZoneWalls(zoneId);
  if (!walls) return { x: to.x, z: to.z, blocked: false };
  return walls.clampStep(from.x, from.z, to.x, to.z, from.y ?? 0, 1.7);
}
