import type { PlayerSession } from '@dust-saga/shared';

/**
 * Serialize / deserialize a PlayerSession for cross-shard zone handoff.
 *
 * The session is almost entirely plain data, but three fields must be stripped:
 * - `resistCache` — a `Map<string, number>` which JSON.stringify renders as `{}`
 * - `effectiveStats` — Phase A1 stat cache, recomputed by `recalcStats`
 * - `statBreakdown` — Phase A1 breakdown, recomputed by `recalcStats`
 *
 * `socketId` is zeroed because the new shard assigns its own. `activeCast` is
 * cleared so a pending cast does not fire on the wrong shard.
 */

export function serializeSession(session: PlayerSession): string {
  const clone: any = { ...session };
  delete clone.resistCache;
  clone.effectiveStats = null;
  clone.statBreakdown = null;
  clone.socketId = '';
  clone.activeCast = null;
  return JSON.stringify(clone);
}

export function deserializeSession(json: string): PlayerSession {
  const session: PlayerSession = JSON.parse(json);
  session.effectiveStats = null;
  session.statBreakdown = null;
  session.resistCache = undefined;
  return session;
}
