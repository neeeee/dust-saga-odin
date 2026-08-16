"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.EnmitySystem = void 0;
const VE_DECAY_RATE = 60;
const CE_DECAY_RATE_COMBAT = 2;
const CE_DECAY_RATE_IDLE = 20;
const PROVOKE_MINIMUM = 1000;
class EnmitySystem {
    addCE(enemy, characterId, amount) {
        this.ensureTable(enemy);
        const entry = enemy.enmityTable[characterId];
        if (entry) {
            entry.ce += amount;
        }
        else {
            enemy.enmityTable[characterId] = { ce: amount, ve: 0, timestamp: Date.now() };
        }
    }
    addVE(enemy, characterId, amount) {
        this.ensureTable(enemy);
        const entry = enemy.enmityTable[characterId];
        if (entry) {
            entry.ve += amount;
        }
        else {
            enemy.enmityTable[characterId] = { ce: 0, ve: amount, timestamp: Date.now() };
        }
    }
    addEnmity(enemy, characterId, ce, ve) {
        this.addCE(enemy, characterId, ce);
        this.addVE(enemy, characterId, ve);
        this.engageIfIdle(enemy, characterId);
    }
    addDamageEnmity(enemy, characterId, damage) {
        if (damage <= 0)
            return;
        this.addEnmity(enemy, characterId, damage, damage);
    }
    addDebuffEnmity(enemy, characterId, potency, applied) {
        const base = applied ? 300 + Math.floor(potency * 2) : 200;
        this.addEnmity(enemy, characterId, base, base);
    }
    addHealEnmity(enemy, characterId, healing) {
        if (healing <= 0)
            return;
        const amount = Math.floor(healing * 0.5);
        if (amount <= 0)
            return;
        this.addEnmity(enemy, characterId, amount, amount);
    }
    provokeEnmity(enemy, characterId) {
        this.ensureTable(enemy);
        let maxCE = 0;
        for (const key of Object.keys(enemy.enmityTable)) {
            if (enemy.enmityTable[key].ce > maxCE)
                maxCE = enemy.enmityTable[key].ce;
        }
        const provokeCE = Math.max(maxCE + 1, PROVOKE_MINIMUM);
        const entry = enemy.enmityTable[characterId];
        if (entry) {
            entry.ce = provokeCE;
            entry.ve = 0;
        }
        else {
            enemy.enmityTable[characterId] = { ce: provokeCE, ve: 0, timestamp: Date.now() };
        }
        if (enemy.state === 'idle' || enemy.state === 'return') {
            enemy.state = 'chase';
            enemy.targetId = characterId;
        }
    }
    engageIfIdle(enemy, characterId) {
        if (enemy.state === 'idle' || enemy.state === 'return') {
            enemy.state = 'chase';
            enemy.targetId = characterId;
        }
    }
    getTopTarget(enemy) {
        if (!enemy.enmityTable)
            return null;
        const keys = Object.keys(enemy.enmityTable);
        if (keys.length === 0)
            return null;
        let best = null;
        for (const characterId of keys) {
            const entry = enemy.enmityTable[characterId];
            const total = entry.ce + entry.ve;
            if (total <= 0)
                continue;
            if (!best || total > best.total || (total === best.total && entry.timestamp > best.timestamp)) {
                best = { characterId, ce: entry.ce, ve: entry.ve, total, timestamp: entry.timestamp };
            }
        }
        return best ? { characterId: best.characterId, ce: best.ce, ve: best.ve, total: best.total } : null;
    }
    removePlayer(enemy, characterId) {
        if (enemy.enmityTable) {
            delete enemy.enmityTable[characterId];
        }
    }
    decay(enemy, deltaTime, combat) {
        if (!enemy.enmityTable)
            return;
        const keys = Object.keys(enemy.enmityTable);
        if (keys.length === 0)
            return;
        const veRate = VE_DECAY_RATE * deltaTime;
        const ceRate = (combat ? CE_DECAY_RATE_COMBAT : CE_DECAY_RATE_IDLE) * deltaTime;
        if (veRate <= 0 && ceRate <= 0)
            return;
        const toRemove = [];
        for (const characterId of keys) {
            const entry = enemy.enmityTable[characterId];
            entry.veDecayAccum = (entry.veDecayAccum || 0) + veRate;
            entry.ceDecayAccum = (entry.ceDecayAccum || 0) + ceRate;
            const veDecay = Math.floor(entry.veDecayAccum);
            const ceDecay = Math.floor(entry.ceDecayAccum);
            if (veDecay > 0) {
                entry.ve = Math.max(0, entry.ve - veDecay);
                entry.veDecayAccum -= veDecay;
            }
            if (ceDecay > 0) {
                entry.ce = Math.max(0, entry.ce - ceDecay);
                entry.ceDecayAccum -= ceDecay;
            }
            if (entry.ce <= 0 && entry.ve <= 0) {
                toRemove.push(characterId);
            }
        }
        for (const id of toRemove) {
            delete enemy.enmityTable[id];
        }
    }
    clearEnmity(enemy) {
        if (enemy.enmityTable) {
            enemy.enmityTable = {};
        }
    }
    hasEnmityWithParty(enemy, partyMemberIds) {
        if (!enemy.enmityTable)
            return false;
        for (const id of partyMemberIds) {
            if (enemy.enmityTable[id])
                return true;
        }
        return false;
    }
    ensureTable(enemy) {
        if (!enemy.enmityTable) {
            enemy.enmityTable = {};
        }
    }
}
exports.EnmitySystem = EnmitySystem;
