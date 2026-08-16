/**
 * Per-zone state container — the unit of zone sharding.
 *
 * Owns the set of players currently present in this zone. Enemy/summon/AOE
 * state is already zone-scoped (keyed by zoneId) in SpawnManager /
 * SummonManager / AOEZoneManager; player presence lives here so every piece of
 * per-zone state has an explicit home that can migrate with a shard.
 */
export class ZoneInstance {
  readonly players = new Set<string>();

  constructor(readonly zoneId: string) {}

  addPlayer(characterId: string): void {
    this.players.add(characterId);
  }

  removePlayer(characterId: string): boolean {
    return this.players.delete(characterId);
  }

  hasPlayer(characterId: string): boolean {
    return this.players.has(characterId);
  }

  get playerCount(): number {
    return this.players.size;
  }
}

/** Registry of all live zones, keyed by zoneId. */
export class ZoneRegistry {
  private zones = new Map<string, ZoneInstance>();

  getOrCreate(zoneId: string): ZoneInstance {
    let zone = this.zones.get(zoneId);
    if (!zone) {
      zone = new ZoneInstance(zoneId);
      this.zones.set(zoneId, zone);
    }
    return zone;
  }

  get(zoneId: string): ZoneInstance | undefined {
    return this.zones.get(zoneId);
  }

  /** Remove a player from whatever zone they're in; returns that zoneId (or undefined). */
  removePlayerFromAll(characterId: string): string | undefined {
    for (const zone of this.zones.values()) {
      if (zone.players.delete(characterId)) return zone.zoneId;
    }
    return undefined;
  }

  /** Find which zone a player is currently in (or undefined). */
  zoneOf(characterId: string): string | undefined {
    for (const zone of this.zones.values()) {
      if (zone.players.has(characterId)) return zone.zoneId;
    }
    return undefined;
  }

  *iterateZones(): IterableIterator<ZoneInstance> {
    yield* this.zones.values();
  }
}
