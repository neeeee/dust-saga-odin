import type { RedisClientType } from 'redis';

/**
 * Maintains a Redis-backed presence map: characterId -> shardId.
 *
 * Purpose (Phase B3 — thin seam): build the presence infrastructure now so that
 * Phase B5/B6 cross-shard routing has accurate, live data to consult. The 40+
 * cross-zone `state.players.get(targetId)` call sites are NOT migrated yet —
 * they remain local lookups. This service only owns the presence map itself.
 *
 * Lifecycle:
 *   connect    -> markOnline(charId)   writes presence:<charId> = <shardId> (TTL)
 *   every ~20s -> heartbeat()          refreshes TTL for all locally-online chars
 *   disconnect -> markOffline(charId)  deletes the entry
 *
 * When Redis is unavailable (dev mode, or transient outage) every operation is
 * a best-effort no-op; `getShard` returns null and callers fall back to their
 * existing local `state.players` lookup.
 */
export class PresenceService {
  private readonly shardId: string;
  private readonly redis: RedisClientType | null;
  private readonly isConnected: () => boolean;
  private readonly keyPrefix = 'presence:';
  private readonly ttlSeconds = 60;

  /** Characters currently believed online on this shard (for heartbeat iteration). */
  private readonly localOnline: Set<string> = new Set();

  constructor(shardId: string, redis: RedisClientType | null, isConnected: () => boolean) {
    this.shardId = shardId;
    this.redis = redis;
    this.isConnected = isConnected;
  }

  getShardId(): string {
    return this.shardId;
  }

  /** Record that a character is hosted by this shard. Best-effort, non-throwing. */
  async markOnline(characterId: string): Promise<void> {
    this.localOnline.add(characterId);
    if (!this.canWrite()) return;
    try {
      await this.redis!.set(this.keyPrefix + characterId, this.shardId, { EX: this.ttlSeconds });
    } catch (err) {
      console.warn(`[presence] markOnline failed for ${characterId}:`, err);
    }
  }

  /** Record that a character is no longer hosted by this shard. Best-effort, non-throwing. */
  async markOffline(characterId: string): Promise<void> {
    this.localOnline.delete(characterId);
    if (!this.canWrite()) return;
    try {
      await this.redis!.del(this.keyPrefix + characterId);
    } catch (err) {
      console.warn(`[presence] markOffline failed for ${characterId}:`, err);
    }
  }

  /**
   * Resolve which shard currently hosts a character, or null if offline / unknown.
   * Returns null when Redis is unavailable — callers should then rely on their
   * local `state.players` map (the pre-sharding behavior).
   */
  async getShard(characterId: string): Promise<string | null> {
    if (!this.canWrite()) return null;
    try {
      return await this.redis!.get(this.keyPrefix + characterId);
    } catch (err) {
      console.warn(`[presence] getShard failed for ${characterId}:`, err);
      return null;
    }
  }

  /**
   * Refresh the TTL for every character hosted by this shard. Call on a slow
   * interval (e.g. 20s) so live players' entries survive between heartbeats while
   * a crashed shard's entries expire within `ttlSeconds` of the last heartbeat.
   */
  async heartbeat(): Promise<void> {
    if (!this.canWrite() || this.localOnline.size === 0) return;
    try {
      for (const characterId of this.localOnline) {
        await this.redis!.set(this.keyPrefix + characterId, this.shardId, { EX: this.ttlSeconds });
      }
    } catch (err) {
      console.warn('[presence] heartbeat failed:', err);
    }
  }

  private canWrite(): boolean {
    return this.isConnected() && this.redis !== null;
  }
}
