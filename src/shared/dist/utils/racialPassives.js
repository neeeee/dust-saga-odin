"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.applyRacialCritChance = applyRacialCritChance;
exports.applyRacialDodgeChance = applyRacialDodgeChance;
exports.applyRacialIncomingDamage = applyRacialIncomingDamage;
exports.applyRacialOutgoingDamage = applyRacialOutgoingDamage;
exports.applyRacialPotionHealing = applyRacialPotionHealing;
exports.applyRacialMpCost = applyRacialMpCost;
exports.applyRacialAilmentDuration = applyRacialAilmentDuration;
exports.checkSurviveFatal = checkSurviveFatal;
exports.checkDamageToMpConversion = checkDamageToMpConversion;
exports.checkFatalDamageForParty = checkFatalDamageForParty;
exports.processRacialOnDamage = processRacialOnDamage;
exports.getRangedRangeBonus = getRangedRangeBonus;
exports.getCharmResist = getCharmResist;
exports.getMpRegenBonus = getMpRegenBonus;
exports.getMeleeSkillBonus = getMeleeSkillBonus;
exports.hasLapinSupport = hasLapinSupport;
exports.hasEnkiduSupport = hasEnkiduSupport;
const races_1 = require("../types/races");
function applyRacialCritChance(passiveId, baseCritChance) {
    if (passiveId === races_1.RacialPassiveId.MYRINE_ACUTE_SENSES)
        return baseCritChance + 0.05;
    return baseCritChance;
}
function applyRacialDodgeChance(passiveId) {
    if (passiveId === races_1.RacialPassiveId.MYRINE_SHARPNESS)
        return 0.05;
    return 0;
}
function applyRacialIncomingDamage(passiveId, damage, damageType) {
    if (damageType === 'physical' && passiveId === races_1.RacialPassiveId.ENKIDU_STONE_SKIN) {
        return Math.max(1, Math.floor(damage * 0.9));
    }
    if (damageType === 'magical' && passiveId === races_1.RacialPassiveId.LAPIN_MAGIC_RESISTANCE) {
        return Math.max(1, Math.floor(damage * 0.9));
    }
    return Math.max(1, damage);
}
function applyRacialOutgoingDamage(passiveId, damage, weaponType) {
    if (!passiveId)
        return damage;
    if ((weaponType === 'axe' || weaponType === 'blunt') && passiveId === races_1.RacialPassiveId.DWARF_SPIRIT) {
        return Math.floor(damage * 1.1);
    }
    if (weaponType === 'twohand' && passiveId === races_1.RacialPassiveId.ENKIDU_STRONG_ARM) {
        return Math.floor(damage * 1.1);
    }
    return damage;
}
function applyRacialPotionHealing(passiveId, baseHeal) {
    if (passiveId === races_1.RacialPassiveId.HUMAN_BREWER) {
        return Math.floor(baseHeal * 1.15);
    }
    return baseHeal;
}
function applyRacialMpCost(passiveId, baseMpCost) {
    if (passiveId === races_1.RacialPassiveId.ELF_NATURES_HARMONY) {
        return Math.max(1, Math.floor(baseMpCost * 0.85));
    }
    return baseMpCost;
}
function applyRacialAilmentDuration(passiveId, baseDurationMs) {
    if (passiveId === races_1.RacialPassiveId.HUMAN_ADAPTABILITY) {
        return Math.max(0, Math.floor(baseDurationMs * 0.5));
    }
    return baseDurationMs;
}
function checkSurviveFatal(passiveId) {
    if (passiveId === races_1.RacialPassiveId.DWARF_FILIAL_PIETY) {
        return Math.random() < 0.03;
    }
    return false;
}
function checkDamageToMpConversion(passiveId) {
    if (passiveId === races_1.RacialPassiveId.MYRINE_CALMNESS) {
        return Math.random() < 0.05;
    }
    return false;
}
function checkFatalDamageForParty(passiveId) {
    if (passiveId === races_1.RacialPassiveId.DWARF_STRONGHEARTED) {
        return Math.random() < 0.01;
    }
    return false;
}
function processRacialOnDamage(target, incomingDamage, damageType) {
    const passiveId = target.racialPassive;
    let finalDamage = applyRacialIncomingDamage(passiveId, incomingDamage, damageType);
    let survivedFatal = false;
    let mpConverted = 0;
    if (checkDamageToMpConversion(passiveId)) {
        mpConverted = Math.floor(finalDamage * 0.3);
        target.stats.mana = Math.min(target.stats.maxMana, target.stats.mana + mpConverted);
    }
    if (finalDamage >= target.stats.health && checkSurviveFatal(passiveId)) {
        finalDamage = target.stats.health - 1;
        survivedFatal = true;
    }
    return { finalDamage, survivedFatal, mpConverted };
}
function getRangedRangeBonus(passiveId) {
    if (passiveId === races_1.RacialPassiveId.ELF_HAWKEYE)
        return 3;
    return 0;
}
function getCharmResist(passiveId) {
    if (passiveId === races_1.RacialPassiveId.ELF_STEADFASTNESS)
        return 20;
    return 0;
}
function getMpRegenBonus(passiveId) {
    if (passiveId === races_1.RacialPassiveId.LAPIN_INNER_LIGHT)
        return 0.15;
    return 0;
}
function getMeleeSkillBonus(passiveId) {
    if (passiveId === races_1.RacialPassiveId.HUMAN_FIGHTING_SPIRIT)
        return 10;
    return 0;
}
function hasLapinSupport(passiveId) {
    return passiveId === races_1.RacialPassiveId.ENKIDU_LAPIN_SUPPORT;
}
function hasEnkiduSupport(passiveId) {
    return passiveId === races_1.RacialPassiveId.LAPIN_ENKIDU_SUPPORT;
}
