import type { RedisClientType } from 'redis';
import type { PlayerSession } from '@dust-saga/shared';
import { serializeSession, deserializeSession } from './SessionSerializer';

/**
 * Cross-shard zone handoff via Redis.
 *
 * Purpose (Phase B6): when a player transitions to a zone owned by another
 * shard, the old shard serializes the live session to Redis key
 * `handoff:<characterId>` (30s TTL). The new shard checks this key during
 * character-select; if found, the session is deserialized directly instead of
 * loading from the database, preserving in-memory state (buffs, cooldowns,
 * inventory changes since last DB save).
 *
 * The old shard still saves to DB before handoff as a fallback — if the new
 * shard fails to pick up the handoff within the TTL window, a normal DB-based
 * login still works (with slightly stale state).
 *
 * Best-effort no-op when Redis is absent.
 */
export class ZoneHandoff {
  private readonly redis: RedisClientType | null;
  private readonly isConnected: () => boolean;
  private readonly keyPrefix = 'handoff:';
  private readonly ttlSeconds = 30;

  constructor(redis: RedisClientType | null, isConnected: () => boolean) {
    this.redis = redis;
    this.isConnected = isConnected;
  }

  /** Serialize the session to Redis for the new shard to pick up. */
  async initiate(characterId: string, session: PlayerSession): Promise<boolean> {
    if (!this.canOperate()) return false;
    try {
      const json = serializeSession(session);
      await this.redis!.set(this.keyPrefix + characterId, json, { EX: this.ttlSeconds });
      return true;
    } catch (err) {
      console.warn(`[handoff] initiate failed for ${characterId}:`, err);
      return false;
    }
  }

  /**
   * Check for a pending handoff. If found, deserialize and delete the key.
   * Returns null when no handoff is pending or Redis is unavailable.
   */
  async resolve(characterId: string): Promise<PlayerSession | null> {
    if (!this.canOperate()) return null;
    try {
      const json = await this.redis!.get(this.keyPrefix + characterId);
      if (!json) return null;
      await this.redis!.del(this.keyPrefix + characterId);
      return deserializeSession(json);
    } catch (err) {
      console.warn(`[handoff] resolve failed for ${characterId}:`, err);
      return null;
    }
  }

  private canOperate(): boolean {
    return this.isConnected() && this.redis !== null;
  }
}
