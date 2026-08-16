import type { RedisClientType } from 'redis';

/**
 * Zone-ownership registry mapping zoneId → shardId.
 *
 * Purpose (Phase B6): determine whether a zone transition stays on the local
 * shard or requires a cross-shard handoff. When `ZONE_OWNERSHIP` env is unset
 * (single-process mode) the shard claims every zone and `ownsZone()` always
 * returns true — no handoff is ever triggered. When `ZONE_OWNERSHIP` is a
 * comma-separated list of zone IDs, the shard claims only those zones and
 * `getOwner()` returns the owning shard for any zone in Redis.
 */
export class ZoneOwnership {
  private readonly shardId: string;
  private readonly redis: RedisClientType | null;
  private readonly isConnected: () => boolean;
  /** null = owns all zones (single-process); Set<string> = explicit ownership. */
  private readonly ownedZones: Set<string> | null;

  constructor(shardId: string, redis: RedisClientType | null, isConnected: () => boolean) {
    this.shardId = shardId;
    this.redis = redis;
    this.isConnected = isConnected;
    const env = process.env.ZONE_OWNERSHIP;
    this.ownedZones = env ? new Set(env.split(',').map(z => z.trim()).filter(Boolean)) : null;
  }

  /** Does THIS shard own the given zone? (sync, for hot-path checks) */
  ownsZone(zoneId: string): boolean {
    return this.ownedZones === null || this.ownedZones.has(zoneId);
  }

  /**
   * Which shard owns the given zone? Returns the local shardId when Redis is
   * absent (single-process fallback). Returns null if the zone has no owner
   * in Redis (should not happen after claimZones).
   */
  async getOwner(zoneId: string): Promise<string | null> {
    if (!this.canOperate()) return this.shardId;
    try {
      const owner = await this.redis!.hGet('zone:ownership', zoneId);
      return owner || this.shardId;
    } catch {
      return this.shardId;
    }
  }

  /** Claim this shard's zones in Redis on startup. */
  async claimZones(allZoneIds: string[]): Promise<void> {
    if (!this.canOperate()) return;
    const zones = this.ownedZones ?? new Set(allZoneIds);
    try {
      for (const zoneId of zones) {
        await this.redis!.hSet('zone:ownership', zoneId, this.shardId);
      }
      console.log(`[zone-ownership] claimed ${zones.size} zone(s)`);
    } catch (err) {
      console.warn('[zone-ownership] claim failed:', err);
    }
  }

  /** Release this shard's zones on shutdown. */
  async releaseZones(): Promise<void> {
    if (!this.canOperate()) return;
    try {
      const all = await this.redis!.hGetAll('zone:ownership');
      for (const [zoneId, owner] of Object.entries(all)) {
        if (owner === this.shardId) {
          await this.redis!.hDel('zone:ownership', zoneId);
        }
      }
    } catch {
      // best-effort
    }
  }

  /** WebSocket URL clients should connect to for this shard. */
  getShardUrl(): string {
    return process.env.SHARD_URL || `http://localhost:${process.env.PORT || 3001}`;
  }

  getShardId(): string {
    return this.shardId;
  }

  private canOperate(): boolean {
    return this.isConnected() && this.redis !== null;
  }
}
