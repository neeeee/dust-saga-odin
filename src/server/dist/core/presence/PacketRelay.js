"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PacketRelay = void 0;
/**
 * Cross-shard packet delivery via Redis pub/sub.
 *
 * Purpose (Phase B5): when `NetworkServer.sendToPlayer(characterId, packet)`
 * cannot find the character locally, it delegates to `relay()` which resolves
 * the target shard via the presence map and publishes the packet to
 * `relay:<targetShard>`. The owning shard's subscription delivers it to the
 * player's socket.
 *
 * This makes every existing `sendToPlayer` call site cross-shard-aware without
 * touching any handler — party updates, loot results, chat notifications, etc.
 * all reach players regardless of which shard hosts them.
 *
 * `broadcastInZone` and global `io.emit` are already cross-shard via the
 * Socket.IO Redis adapter (B2); this fills the only remaining gap: targeted
 * unicast by characterId.
 *
 * When Redis is unavailable every operation is a no-op; `relay()` returns
 * immediately and the caller (sendToPlayer) silently drops the packet —
 * identical to the pre-sharding behavior for offline targets.
 */
class PacketRelay {
    /**
     * @param deliverLocal Callback that performs direct socket delivery on THIS
     *   shard. Must NOT call `sendToPlayer` (would recurse into `relay`).
     *   Typically: `state.playerToSocket.get(id) → sendToSocket`.
     */
    constructor(shardId, redis, isConnected, presence, deliverLocal) {
        this.subClient = null;
        this.started = false;
        this.shardId = shardId;
        this.redis = redis;
        this.isConnected = isConnected;
        this.presence = presence;
        this.deliverLocal = deliverLocal;
    }
    /**
     * Subscribe to this shard's relay channel. Called once during bootstrap with
     * a dedicated Redis client (subscribe mode is exclusive — cannot reuse the
     * shared game client or the adapter clients).
     */
    async start(subClient) {
        if (this.started || !this.canOperate())
            return;
        this.subClient = subClient;
        try {
            await this.subClient.subscribe(`relay:${this.shardId}`, (raw) => {
                try {
                    const msg = JSON.parse(raw);
                    this.deliverLocal(msg.characterId, msg.packet);
                }
                catch (err) {
                    console.warn('[relay] malformed message, dropping:', err);
                }
            });
            this.started = true;
            console.log(`Packet relay listening on relay:${this.shardId}`);
        }
        catch (err) {
            console.warn('[relay] failed to start subscription:', err);
            this.subClient = null;
        }
    }
    /**
     * Route a packet to whatever shard currently hosts the character. Fire-and-
     * forget: the promise is not awaited by the caller (`sendToPlayer` is sync).
     * No-op when Redis is unavailable, target is offline, or target is local
     * (local delivery was already attempted by `sendToPlayer`).
     */
    relay(characterId, packet) {
        if (!this.canOperate())
            return;
        void this.relayAsync(characterId, packet);
    }
    async relayAsync(characterId, packet) {
        try {
            const targetShard = await this.presence.getShard(characterId);
            if (!targetShard || targetShard === this.shardId)
                return;
            const msg = { characterId, packet };
            await this.redis.publish(`relay:${targetShard}`, JSON.stringify(msg));
        }
        catch (err) {
            console.warn(`[relay] failed to route packet for ${characterId}:`, err);
        }
    }
    async stop() {
        if (this.subClient) {
            await this.subClient.quit().catch(() => { });
            this.subClient = null;
            this.started = false;
        }
    }
    canOperate() {
        return this.isConnected() && this.redis !== null;
    }
}
exports.PacketRelay = PacketRelay;
