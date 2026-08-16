"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ZoneRegistry = exports.ZoneInstance = void 0;
/**
 * Per-zone state container — the unit of zone sharding.
 *
 * Owns the set of players currently present in this zone. Enemy/summon/AOE
 * state is already zone-scoped (keyed by zoneId) in SpawnManager /
 * SummonManager / AOEZoneManager; player presence lives here so every piece of
 * per-zone state has an explicit home that can migrate with a shard.
 */
class ZoneInstance {
    constructor(zoneId) {
        this.zoneId = zoneId;
        this.players = new Set();
    }
    addPlayer(characterId) {
        this.players.add(characterId);
    }
    removePlayer(characterId) {
        return this.players.delete(characterId);
    }
    hasPlayer(characterId) {
        return this.players.has(characterId);
    }
    get playerCount() {
        return this.players.size;
    }
}
exports.ZoneInstance = ZoneInstance;
/** Registry of all live zones, keyed by zoneId. */
class ZoneRegistry {
    constructor() {
        this.zones = new Map();
    }
    getOrCreate(zoneId) {
        let zone = this.zones.get(zoneId);
        if (!zone) {
            zone = new ZoneInstance(zoneId);
            this.zones.set(zoneId, zone);
        }
        return zone;
    }
    get(zoneId) {
        return this.zones.get(zoneId);
    }
    /** Remove a player from whatever zone they're in; returns that zoneId (or undefined). */
    removePlayerFromAll(characterId) {
        for (const zone of this.zones.values()) {
            if (zone.players.delete(characterId))
                return zone.zoneId;
        }
        return undefined;
    }
    /** Find which zone a player is currently in (or undefined). */
    zoneOf(characterId) {
        for (const zone of this.zones.values()) {
            if (zone.players.has(characterId))
                return zone.zoneId;
        }
        return undefined;
    }
    *iterateZones() {
        yield* this.zones.values();
    }
}
exports.ZoneRegistry = ZoneRegistry;
