"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.collectProcs = collectProcs;
exports.buildProcStatusEffect = buildProcStatusEffect;
exports.getProcResistCategory = getProcResistCategory;
exports.isDrainLifeProc = isDrainLifeProc;
exports.getDarkRecoilPercent = getDarkRecoilPercent;
const shared_1 = require("@dust-saga/shared");
const PROC_EFFECT_MAP = {
    weaken: { statusType: shared_1.StatusEffectType.BUFF_GENERIC, debuffCategory: 'weaken' },
    burn: { statusType: shared_1.StatusEffectType.BURN, debuffCategory: 'burn', tickInterval: 1000 },
    sleep: { statusType: shared_1.StatusEffectType.SLEEP, debuffCategory: 'sleep' },
    freeze: { statusType: shared_1.StatusEffectType.FREEZE, debuffCategory: 'freeze' },
    drainLife: { statusType: shared_1.StatusEffectType.BUFF_GENERIC },
    trip: { statusType: shared_1.StatusEffectType.BUFF_GENERIC, debuffCategory: 'trip' },
    stun: { statusType: shared_1.StatusEffectType.STUN, debuffCategory: 'stun' },
    poison: { statusType: shared_1.StatusEffectType.POISON, debuffCategory: 'ailment', tickInterval: 3000 },
    bleed: { statusType: shared_1.StatusEffectType.BLEED, debuffCategory: 'bleed', tickInterval: 2000 },
    silence: { statusType: shared_1.StatusEffectType.SILENCE, debuffCategory: 'ailment' },
    castSpeedDown: { statusType: shared_1.StatusEffectType.DEBUFF_CAST_SPEED_DOWN, debuffCategory: 'disorder' },
    slow: { statusType: shared_1.StatusEffectType.SLOW, debuffCategory: 'ailment' },
};
function collectProcs(session, itemSys) {
    const procs = [];
    const souls = session.socketedSouls;
    if (souls) {
        for (const soul of souls) {
            if (!soul)
                continue;
            const def = itemSys.getItemDefinition(soul.itemId);
            if (def?.onHitProcs) {
                procs.push(...def.onHitProcs);
            }
        }
    }
    const weapon = session.equipment?.weapon;
    let enhancementLevel = 0;
    let enhancementElement;
    if (weapon) {
        enhancementLevel = weapon.enhancementLevel || 0;
        enhancementElement = weapon.enhancementElement;
        const weaponDef = itemSys.getItemDefinition(weapon.itemId);
        if (weaponDef?.innateProcs) {
            for (const proc of weaponDef.innateProcs) {
                if (proc.element && proc.element !== enhancementElement)
                    continue;
                procs.push(proc);
            }
        }
    }
    return { procs, enhancementLevel, enhancementElement };
}
function buildProcStatusEffect(proc, sourceId, targetId) {
    const mapping = PROC_EFFECT_MAP[proc.effect];
    if (!mapping)
        return null;
    const def = shared_1.STATUS_EFFECT_DEFS[mapping.statusType];
    if (!def)
        return null;
    const now = Date.now();
    const durationMs = (proc.duration || 0) * 1000 || def.duration;
    return {
        id: `proc_${proc.effect}_${targetId}_${now}`,
        type: mapping.statusType,
        sourceId,
        targetId,
        potency: proc.potency || 0,
        appliedAt: now,
        duration: durationMs,
        tickInterval: mapping.tickInterval ?? def.tickInterval,
        lastTickAt: now,
        stacks: 1,
        skillName: `proc_${proc.effect}`,
        debuffCategory: mapping.debuffCategory,
    };
}
function getProcResistCategory(proc) {
    const mapping = PROC_EFFECT_MAP[proc.effect];
    return mapping?.debuffCategory;
}
function isDrainLifeProc(proc) {
    return proc.effect === 'drainLife';
}
const DARK_RECOIL_TABLE = {
    0: 0.50, 1: 0.50, 2: 0.50, 3: 0.50, 4: 0.50,
    5: 0.40, 6: 0.36, 7: 0.30, 8: 0.25, 9: 0.15, 10: 0.12,
};
function getDarkRecoilPercent(enhancementLevel) {
    return DARK_RECOIL_TABLE[enhancementLevel] ?? 0;
}
