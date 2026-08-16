"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.serializeSession = serializeSession;
exports.deserializeSession = deserializeSession;
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
function serializeSession(session) {
    const clone = { ...session };
    delete clone.resistCache;
    clone.effectiveStats = null;
    clone.statBreakdown = null;
    clone.socketId = '';
    clone.activeCast = null;
    return JSON.stringify(clone);
}
function deserializeSession(json) {
    const session = JSON.parse(json);
    session.effectiveStats = null;
    session.statBreakdown = null;
    session.resistCache = undefined;
    return session;
}
