"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.LootSystem = void 0;
const EntityManager_1 = require("../EntityManager");
const shared_1 = require("@dust-saga/shared");
const shared_2 = require("@dust-saga/shared");
let lootSeq = 0;
function nextLootId() {
    lootSeq = (lootSeq + 1) % 1000000;
    return `loot_${Date.now().toString(36)}_${lootSeq.toString(36)}`;
}
function nextItemId() {
    lootSeq = (lootSeq + 1) % 1000000;
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
class LootSystem extends EntityManager_1.System {
    constructor(entityManager) {
        super(entityManager);
        this.activeLoot = new Map();
        /** Per-party need/greed pools, separate from ground bags. */
        this.partyPools = new Map();
        /** Pending need/greed rolls: lootId → { partyId, members who haven't rolled } */
        this.pendingRolls = new Map();
    }
    // ─────────────────────────────────────────────────────────────────────────
    // Generation (deterministic given a loot table + position)
    // ─────────────────────────────────────────────────────────────────────────
    /**
     * Roll a loot table into a flat list of { itemId, quantity } drops.
     * Pure: no state mutation. The caller decides what to do with the result.
     */
    rollLootTable(table) {
        if (!table || !table.drops || table.rolls <= 0)
            return [];
        const out = [];
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
    spawnFFA(drops, position, zoneId, sourceName, partyId = null, rule = shared_1.LootRule.FFA) {
        if (drops.length === 0)
            return null;
        const bag = this.buildBag(drops, position, zoneId, sourceName);
        bag.assignedTo = null;
        bag.assignmentExpiresAt = 0;
        bag.partyId = partyId;
        bag.rule = rule;
        this.activeLoot.set(bag.id, bag);
        return bag;
    }
    /** Round-robin bag: locked to one character until expiry, then FFA. */
    spawnAssigned(drops, position, zoneId, sourceName, assignedTo, partyId, rule) {
        if (drops.length === 0)
            return null;
        const bag = this.buildBag(drops, position, zoneId, sourceName);
        bag.assignedTo = assignedTo;
        bag.assignmentExpiresAt = Date.now() + shared_1.LOOT_ASSIGNMENT_DURATION_MS;
        bag.partyId = partyId;
        bag.rule = rule;
        this.activeLoot.set(bag.id, bag);
        return bag;
    }
    buildBag(drops, position, zoneId, sourceName) {
        const items = drops.map(d => ({
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
            rule: shared_1.LootRule.FFA,
        };
    }
    // ─────────────────────────────────────────────────────────────────────────
    // Need/greed roll support
    // ─────────────────────────────────────────────────────────────────────────
    /**
     * Start a need/greed roll for a single item. The item is held out-of-band
     * (not in activeLoot as a ground bag) until the roll resolves or times out.
     */
    startNeedGreedRoll(partyId, members, drop) {
        if (members.length === 0)
            return null;
        const lootId = nextLootId();
        const itemName = this.itemSys.getItemDefinition(drop.itemId)?.name || drop.itemId;
        const entry = {
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
    submitRoll(partyId, lootId, characterId, kind) {
        const pool = this.partyPools.get(partyId);
        if (!pool)
            return null;
        const entry = pool.find(i => i.lootId === lootId);
        if (!entry)
            return null;
        const pending = this.pendingRolls.get(lootId);
        if (!pending)
            return null;
        entry.rolls[characterId] = kind;
        pending.unrolled.delete(characterId);
        return entry;
    }
    /** All members rolled (or pass) — compute the winner. Returns the entry + winner, or null on timeout/no rolls. */
    resolveRoll(partyId, lootId) {
        const pool = this.partyPools.get(partyId);
        if (!pool)
            return null;
        const idx = pool.findIndex(i => i.lootId === lootId);
        if (idx === -1)
            return null;
        const entry = pool[idx];
        this.pendingRolls.delete(lootId);
        const needRollers = Object.entries(entry.rolls).filter(([, k]) => k === 'need');
        const greedRollers = Object.entries(entry.rolls).filter(([, k]) => k === 'greed');
        let candidates;
        if (needRollers.length > 0)
            candidates = needRollers;
        else if (greedRollers.length > 0)
            candidates = greedRollers;
        else
            candidates = [];
        const winnerId = candidates.length === 0
            ? null
            : candidates[Math.floor(Math.random() * candidates.length)][0];
        pool.splice(idx, 1);
        return { winnerId, entry };
    }
    /** Has everyone in the roll submitted (or timed out)? */
    isRollComplete(lootId) {
        const pending = this.pendingRolls.get(lootId);
        if (!pending)
            return true;
        return pending.unrolled.size === 0;
    }
    /** List lootIds that have expired their roll window. */
    expiredRolls(now = Date.now()) {
        const out = [];
        for (const [lootId, p] of this.pendingRolls) {
            if (now - p.createdAt > shared_1.LOOT_ASSIGNMENT_DURATION_MS) {
                out.push({ partyId: p.partyId, lootId });
            }
        }
        return out;
    }
    // ─────────────────────────────────────────────────────────────────────────
    // POOL rule (add to party pool, members manually pull from it)
    // ─────────────────────────────────────────────────────────────────────────
    addToPartyPool(partyId, drop, lootId = nextLootId()) {
        const pool = this.partyPools.get(partyId) || [];
        if (pool.length >= 32)
            return null;
        const entry = {
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
    claimFromPartyPool(partyId, lootId) {
        const pool = this.partyPools.get(partyId);
        if (!pool)
            return null;
        const idx = pool.findIndex(i => i.lootId === lootId);
        if (idx === -1)
            return null;
        const entry = pool[idx];
        pool.splice(idx, 1);
        return { itemId: entry.itemId, quantity: entry.quantity };
    }
    listPartyPool(partyId) {
        return this.partyPools.get(partyId) || [];
    }
    clearParty(partyId) {
        this.partyPools.delete(partyId);
        for (const [lootId, p] of this.pendingRolls) {
            if (p.partyId === partyId)
                this.pendingRolls.delete(lootId);
        }
    }
    // ─────────────────────────────────────────────────────────────────────────
    // Ground-bag pickup (FFA / ROUND_ROBIN)
    // ─────────────────────────────────────────────────────────────────────────
    /**
     * Validate that `characterId` is allowed to take `itemId` (or all) from `lootId`.
     * Does NOT mutate. Use commitItemPickup or commitBagPickup to actually remove.
     */
    canPickup(lootId, characterId) {
        const bag = this.activeLoot.get(lootId);
        if (!bag)
            return { ok: false, reason: 'gone', bag: null };
        if (Date.now() - bag.spawnTime > shared_1.LOOT_DESPAWN_MS) {
            return { ok: false, reason: 'expired', bag };
        }
        if (bag.assignedTo && bag.assignedTo !== characterId) {
            if (bag.assignmentExpiresAt > 0 && Date.now() >= bag.assignmentExpiresAt) {
                // assignment window expired — fall through to FFA
            }
            else {
                return { ok: false, reason: 'assigned', bag };
            }
        }
        return { ok: true, bag };
    }
    /** Take one item from a bag. Returns the item or null. Removes the bag when empty. */
    pickupItem(lootId, itemId) {
        const bag = this.activeLoot.get(lootId);
        if (!bag)
            return null;
        const idx = bag.items.findIndex(i => i.id === itemId);
        if (idx === -1)
            return null;
        const entry = bag.items[idx];
        bag.items.splice(idx, 1);
        if (bag.items.length === 0) {
            this.activeLoot.delete(lootId);
        }
        return { itemId: entry.itemId, quantity: entry.quantity };
    }
    /** Take everything left in the bag. Returns all items and removes the bag. */
    pickupAll(lootId) {
        const bag = this.activeLoot.get(lootId);
        if (!bag)
            return null;
        const out = bag.items.map(i => ({ itemId: i.itemId, quantity: i.quantity }));
        bag.items = [];
        this.activeLoot.delete(lootId);
        return out;
    }
    /** Return a bag for read access (e.g. building LOOT_OPEN payloads). */
    getBag(lootId) {
        return this.activeLoot.get(lootId) || null;
    }
    /** Force-remove a bag (used on expiry tick). */
    removeBag(lootId) {
        const bag = this.activeLoot.get(lootId);
        if (!bag)
            return null;
        this.activeLoot.delete(lootId);
        return bag;
    }
    /** Re-insert an item into an existing bag (e.g. inventory-full rollback). */
    addItemToBag(lootId, itemId, quantity) {
        const bag = this.activeLoot.get(lootId);
        if (!bag)
            return false;
        bag.items.push({ id: nextItemId(), itemId, quantity, rarity: this.itemSys.getItemDefinition(itemId)?.rarity });
        return true;
    }
    /** All bags in a zone (for cleanup on shard shutdown / zone reset). */
    bagsInZone(zoneId) {
        const out = [];
        for (const bag of this.activeLoot.values()) {
            if (bag.zoneId === zoneId)
                out.push(bag);
        }
        return out;
    }
    // ─────────────────────────────────────────────────────────────────────────
    // Per-tick expiry. Returns the list of expired bags so the server can
    // broadcast LOOT_DESPAWN packets to each zone.
    // ─────────────────────────────────────────────────────────────────────────
    tickExpiry(now = Date.now()) {
        const expired = [];
        for (const [id, bag] of this.activeLoot) {
            if (now - bag.spawnTime > shared_1.LOOT_DESPAWN_MS) {
                expired.push(bag);
                this.activeLoot.delete(id);
            }
        }
        return expired;
    }
    /** ECS System.update — delegates to tickExpiry (kept for interface compat). */
    update(_deltaTime) {
        this.tickExpiry();
    }
    // ─────────────────────────────────────────────────────────────────────────
    // Helpers for the NetworkServer distribution decision
    // ─────────────────────────────────────────────────────────────────────────
    /** Round-robin: pick the next member and advance the party's index. */
    pickRoundRobin(party) {
        const idx = (party.roundRobinIndex ?? 0) % party.members.length;
        party.roundRobinIndex = (idx + 1) % party.members.length;
        return party.members[idx];
    }
    ruleOf(rule) {
        return (0, shared_2.normalizeLootRule)(rule);
    }
}
exports.LootSystem = LootSystem;
