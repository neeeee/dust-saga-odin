import { EntityManager, System } from '../EntityManager';
import {
  LootRule, LootTable, ItemRarity,
  LOOT_DESPAWN_MS, LOOT_ASSIGNMENT_DURATION_MS,
  PartyData, PartyLootItem, PartyMember, LootRollKind,
} from '@dust-saga/shared';
import { normalizeLootRule } from '@dust-saga/shared';
import type { ItemSystem } from '../../../systems/ItemSystem';

export interface LootItemEntry {
  id: string;
  itemId: string;
  quantity: number;
  rarity?: ItemRarity;
}

export interface LootInstance {
  id: string;
  items: LootItemEntry[];
  position: { x: number; y: number; z: number };
  zoneId: string;
  sourceName: string;
  spawnTime: number;
  /** characterId of the player who can loot this bag now (null = anyone in range). */
  assignedTo: string | null;
  /** When assignment expires and the bag becomes FFA. 0 = no expiry. */
  assignmentExpiresAt: number;
  /** Party that owns this bag (for rule-aware pickup checks). */
  partyId: string | null;
  rule: LootRule;
}

let lootSeq = 0;
function nextLootId(): string {
  lootSeq = (lootSeq + 1) % 1_000_000;
  return `loot_${Date.now().toString(36)}_${lootSeq.toString(36)}`;
}

function nextItemId(): string {
  lootSeq = (lootSeq + 1) % 1_000_000;
  return `li_${Date.now().toString(36)}_${lootSeq.toString(36)}`;
}

/**
 * Per-kill loot bag generator + party-rule-aware distribution state.
 *
 * The lifecycle of a bag:
 *   1. handleEnemyLoot() on the NetworkServer decides who gets the kill's drops
 *      and calls one of spawnFFA / spawnAssigned / startNeedGreedRoll / addToPool.
 *   2. The bag lives in `activeLoot` until either fully looted, picked up via
 *      assignment, won via roll, or expired (LOOT_DESPAWN_MS).
 *   3. update() is ticked from gameLoop every server tick; expired bags are
 *      reported back via the returned list so the server can broadcast
 *      LOOT_DESPAWN to the zone.
 */
export class LootSystem extends System {
  itemSys!: ItemSystem;
  private activeLoot: Map<string, LootInstance> = new Map();
  /** Per-party need/greed pools, separate from ground bags. */
  private partyPools: Map<string, PartyLootItem[]> = new Map();
  /** Pending need/greed rolls: lootId → { partyId, members who haven't rolled } */
  private pendingRolls: Map<string, { partyId: string; itemId: string; itemName: string; quantity: number; unrolled: Set<string>; createdAt: number }> = new Map();

  constructor(entityManager: EntityManager) {
    super(entityManager);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Generation (deterministic given a loot table + position)
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Roll a loot table into a flat list of { itemId, quantity } drops.
   * Pure: no state mutation. The caller decides what to do with the result.
   */
  rollLootTable(table: LootTable): Array<{ itemId: string; quantity: number }> {
    if (!table || !table.drops || table.rolls <= 0) return [];
    const out: Array<{ itemId: string; quantity: number }> = [];
    for (let i = 0; i < table.rolls; i++) {
      for (const drop of table.drops) {
        if (drop.chance > 0 && Math.random() < drop.chance) {
          out.push({ itemId: drop.itemId, quantity: Math.max(1, drop.quantity) });
        }
      }
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bag spawn variants — caller picks the one matching the active loot rule
  // ─────────────────────────────────────────────────────────────────────────

  /** Free-for-all bag: anyone (in-range) can pick up. Returns the new bag. */
  spawnFFA(
    drops: Array<{ itemId: string; quantity: number }>,
    position: { x: number; y: number; z: number },
    zoneId: string,
    sourceName: string,
    partyId: string | null = null,
    rule: LootRule = LootRule.FFA
  ): LootInstance | null {
    if (drops.length === 0) return null;
    const bag = this.buildBag(drops, position, zoneId, sourceName);
    bag.assignedTo = null;
    bag.assignmentExpiresAt = 0;
    bag.partyId = partyId;
    bag.rule = rule;
    this.activeLoot.set(bag.id, bag);
    return bag;
  }

  /** Round-robin bag: locked to one character until expiry, then FFA. */
  spawnAssigned(
    drops: Array<{ itemId: string; quantity: number }>,
    position: { x: number; y: number; z: number },
    zoneId: string,
    sourceName: string,
    assignedTo: string,
    partyId: string,
    rule: LootRule
  ): LootInstance | null {
    if (drops.length === 0) return null;
    const bag = this.buildBag(drops, position, zoneId, sourceName);
    bag.assignedTo = assignedTo;
    bag.assignmentExpiresAt = Date.now() + LOOT_ASSIGNMENT_DURATION_MS;
    bag.partyId = partyId;
    bag.rule = rule;
    this.activeLoot.set(bag.id, bag);
    return bag;
  }

  private buildBag(
    drops: Array<{ itemId: string; quantity: number }>,
    position: { x: number; y: number; z: number },
    zoneId: string,
    sourceName: string
  ): LootInstance {
    const items: LootItemEntry[] = drops.map(d => ({
      id: nextItemId(),
      itemId: d.itemId,
      quantity: d.quantity,
      rarity: this.itemSys.getItemDefinition(d.itemId)?.rarity,
    }));
    return {
      id: nextLootId(),
      items,
      position: {
        x: position.x + (Math.random() - 0.5) * 1.5,
        y: position.y + 0.5,
        z: position.z + (Math.random() - 0.5) * 1.5,
      },
      zoneId,
      sourceName,
      spawnTime: Date.now(),
      assignedTo: null,
      assignmentExpiresAt: 0,
      partyId: null,
      rule: LootRule.FFA,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Need/greed roll support
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Start a need/greed roll for a single item. The item is held out-of-band
   * (not in activeLoot as a ground bag) until the roll resolves or times out.
   */
  startNeedGreedRoll(
    partyId: string,
    members: PartyMember[],
    drop: { itemId: string; quantity: number }
  ): PartyLootItem | null {
    if (members.length === 0) return null;
    const lootId = nextLootId();
    const itemName = this.itemSys.getItemDefinition(drop.itemId)?.name || drop.itemId;
    const entry: PartyLootItem = {
      lootId,
      itemId: drop.itemId,
      itemName,
      quantity: drop.quantity,
      rolls: {},
    };
    const pool = this.partyPools.get(partyId) || [];
    pool.push(entry);
    this.partyPools.set(partyId, pool);
    this.pendingRolls.set(lootId, {
      partyId,
      itemId: drop.itemId,
      itemName,
      quantity: drop.quantity,
      unrolled: new Set(members.map(m => m.characterId)),
      createdAt: Date.now(),
    });
    return entry;
  }

  /** Record a member's need/greed/pass choice. Returns the entry, or null if closed. */
  submitRoll(partyId: string, lootId: string, characterId: string, kind: 'need' | 'greed' | 'pass'): PartyLootItem | null {
    const pool = this.partyPools.get(partyId);
    if (!pool) return null;
    const entry = pool.find(i => i.lootId === lootId);
    if (!entry) return null;
    const pending = this.pendingRolls.get(lootId);
    if (!pending) return null;

    entry.rolls[characterId] = kind;
    pending.unrolled.delete(characterId);
    return entry;
  }

  /** All members rolled (or pass) — compute the winner. Returns the entry + winner, or null on timeout/no rolls. */
  resolveRoll(partyId: string, lootId: string): { winnerId: string | null; entry: PartyLootItem } | null {
    const pool = this.partyPools.get(partyId);
    if (!pool) return null;
    const idx = pool.findIndex(i => i.lootId === lootId);
    if (idx === -1) return null;
    const entry = pool[idx];
    this.pendingRolls.delete(lootId);

    const needRollers: Array<[string, LootRollKind]> = Object.entries(entry.rolls).filter(([, k]) => k === 'need') as Array<[string, LootRollKind]>;
    const greedRollers: Array<[string, LootRollKind]> = Object.entries(entry.rolls).filter(([, k]) => k === 'greed') as Array<[string, LootRollKind]>;

    let candidates: Array<[string, LootRollKind]>;
    if (needRollers.length > 0) candidates = needRollers;
    else if (greedRollers.length > 0) candidates = greedRollers;
    else candidates = [];

    const winnerId = candidates.length === 0
      ? null
      : candidates[Math.floor(Math.random() * candidates.length)][0];

    pool.splice(idx, 1);
    return { winnerId, entry };
  }

  /** Has everyone in the roll submitted (or timed out)? */
  isRollComplete(lootId: string): boolean {
    const pending = this.pendingRolls.get(lootId);
    if (!pending) return true;
    return pending.unrolled.size === 0;
  }

  /** List lootIds that have expired their roll window. */
  expiredRolls(now: number = Date.now()): Array<{ partyId: string; lootId: string }> {
    const out: Array<{ partyId: string; lootId: string }> = [];
    for (const [lootId, p] of this.pendingRolls) {
      if (now - p.createdAt > LOOT_ASSIGNMENT_DURATION_MS) {
        out.push({ partyId: p.partyId, lootId });
      }
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // POOL rule (add to party pool, members manually pull from it)
  // ─────────────────────────────────────────────────────────────────────────

  addToPartyPool(
    partyId: string,
    drop: { itemId: string; quantity: number },
    lootId: string = nextLootId()
  ): PartyLootItem | null {
    const pool = this.partyPools.get(partyId) || [];
    if (pool.length >= 32) return null;
    const entry: PartyLootItem = {
      lootId,
      itemId: drop.itemId,
      itemName: this.itemSys.getItemDefinition(drop.itemId)?.name || drop.itemId,
      quantity: drop.quantity,
      rolls: {},
    };
    pool.push(entry);
    this.partyPools.set(partyId, pool);
    return entry;
  }

  /** Pull an item out of the party pool (FFA-style: first clicker wins). */
  claimFromPartyPool(partyId: string, lootId: string): { itemId: string; quantity: number } | null {
    const pool = this.partyPools.get(partyId);
    if (!pool) return null;
    const idx = pool.findIndex(i => i.lootId === lootId);
    if (idx === -1) return null;
    const entry = pool[idx];
    pool.splice(idx, 1);
    return { itemId: entry.itemId, quantity: entry.quantity };
  }

  listPartyPool(partyId: string): PartyLootItem[] {
    return this.partyPools.get(partyId) || [];
  }

  clearParty(partyId: string): void {
    this.partyPools.delete(partyId);
    for (const [lootId, p] of this.pendingRolls) {
      if (p.partyId === partyId) this.pendingRolls.delete(lootId);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Ground-bag pickup (FFA / ROUND_ROBIN)
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Validate that `characterId` is allowed to take `itemId` (or all) from `lootId`.
   * Does NOT mutate. Use commitItemPickup or commitBagPickup to actually remove.
   */
  canPickup(lootId: string, characterId: string): { ok: boolean; reason?: string; bag: LootInstance | null } {
    const bag = this.activeLoot.get(lootId);
    if (!bag) return { ok: false, reason: 'gone', bag: null };
    if (Date.now() - bag.spawnTime > LOOT_DESPAWN_MS) {
      return { ok: false, reason: 'expired', bag };
    }
    if (bag.assignedTo && bag.assignedTo !== characterId) {
      if (bag.assignmentExpiresAt > 0 && Date.now() >= bag.assignmentExpiresAt) {
        // assignment window expired — fall through to FFA
      } else {
        return { ok: false, reason: 'assigned', bag };
      }
    }
    return { ok: true, bag };
  }

  /** Take one item from a bag. Returns the item or null. Removes the bag when empty. */
  pickupItem(lootId: string, itemId: string): { itemId: string; quantity: number } | null {
    const bag = this.activeLoot.get(lootId);
    if (!bag) return null;
    const idx = bag.items.findIndex(i => i.id === itemId);
    if (idx === -1) return null;
    const entry = bag.items[idx];
    bag.items.splice(idx, 1);
    if (bag.items.length === 0) {
      this.activeLoot.delete(lootId);
    }
    return { itemId: entry.itemId, quantity: entry.quantity };
  }

  /** Take everything left in the bag. Returns all items and removes the bag. */
  pickupAll(lootId: string): Array<{ itemId: string; quantity: number }> | null {
    const bag = this.activeLoot.get(lootId);
    if (!bag) return null;
    const out = bag.items.map(i => ({ itemId: i.itemId, quantity: i.quantity }));
    bag.items = [];
    this.activeLoot.delete(lootId);
    return out;
  }

  /** Return a bag for read access (e.g. building LOOT_OPEN payloads). */
  getBag(lootId: string): LootInstance | null {
    return this.activeLoot.get(lootId) || null;
  }

  /** Force-remove a bag (used on expiry tick). */
  removeBag(lootId: string): LootInstance | null {
    const bag = this.activeLoot.get(lootId);
    if (!bag) return null;
    this.activeLoot.delete(lootId);
    return bag;
  }

  /** Re-insert an item into an existing bag (e.g. inventory-full rollback). */
  addItemToBag(lootId: string, itemId: string, quantity: number): boolean {
    const bag = this.activeLoot.get(lootId);
    if (!bag) return false;
    bag.items.push({ id: nextItemId(), itemId, quantity, rarity: this.itemSys.getItemDefinition(itemId)?.rarity });
    return true;
  }

  /** All bags in a zone (for cleanup on shard shutdown / zone reset). */
  bagsInZone(zoneId: string): LootInstance[] {
    const out: LootInstance[] = [];
    for (const bag of this.activeLoot.values()) {
      if (bag.zoneId === zoneId) out.push(bag);
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Per-tick expiry. Returns the list of expired bags so the server can
  // broadcast LOOT_DESPAWN packets to each zone.
  // ─────────────────────────────────────────────────────────────────────────

  tickExpiry(now: number = Date.now()): LootInstance[] {
    const expired: LootInstance[] = [];
    for (const [id, bag] of this.activeLoot) {
      if (now - bag.spawnTime > LOOT_DESPAWN_MS) {
        expired.push(bag);
        this.activeLoot.delete(id);
      }
    }
    return expired;
  }

  /** ECS System.update — delegates to tickExpiry (kept for interface compat). */
  update(_deltaTime: number): void {
    this.tickExpiry();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers for the NetworkServer distribution decision
  // ─────────────────────────────────────────────────────────────────────────

  /** Round-robin: pick the next member and advance the party's index. */
  pickRoundRobin(party: PartyData): PartyMember {
    const idx = (party.roundRobinIndex ?? 0) % party.members.length;
    party.roundRobinIndex = (idx + 1) % party.members.length;
    return party.members[idx];
  }

  ruleOf(rule: LootRule | string | undefined): LootRule {
    return normalizeLootRule(rule);
  }
}
