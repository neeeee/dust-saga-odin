"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SkillSystem = void 0;
const shared_1 = require("@dust-saga/shared");
const shared_2 = require("@dust-saga/shared");
const shared_3 = require("@dust-saga/shared");
const obeliskBuff_1 = require("../../combat/obeliskBuff");
const CLASS_SKILL_LOOKUP = (() => {
    const lookup = new Map();
    for (const category of Object.values(shared_2.CLASS_SKILL_DATA)) {
        for (const subSkill of category.skills) {
            for (const [name, def] of Object.entries(subSkill.skills)) {
                lookup.set(name, { ...def, name });
            }
        }
    }
    for (const skills of Object.values(shared_2.CATEGORY_LEVEL_SKILLS)) {
        for (const [name, def] of Object.entries(skills)) {
            lookup.set(name, { ...def, name });
        }
    }
    return lookup;
})();
const CATEGORY_SKILL_TO_KEY = {};
for (const [catId, skills] of Object.entries(shared_2.CATEGORY_LEVEL_SKILLS)) {
    const catKey = shared_2.CATEGORY_ID_TO_KEY[Number(catId)];
    for (const skillName of Object.keys(skills)) {
        CATEGORY_SKILL_TO_KEY[skillName] = catKey;
    }
}
const CLASS_SPECIFIC_SKILL_LOOKUP = (() => {
    const lookup = new Map();
    for (const jobSkills of Object.values(shared_3.CLASS_SPECIFIC_SKILLS)) {
        for (const [name, s] of Object.entries(jobSkills)) {
            lookup.set(name, {
                name,
                reqPoints: s.reqPoints || 0,
                mpCost: s.mpCost,
                castTime: s.castTime,
                cooldown: s.cooldown,
                duration: s.duration,
                description: s.description,
                skillType: s.skillType,
                isAOE: s.isAOE,
                aoeTargetMode: s.aoeTargetMode,
                aoeRadius: s.aoeRadius,
                buffEffectTable: s.buffEffectTable,
                debuffEffectTable: s.debuffEffectTable,
                debuffDuration: s.debuffDuration,
                damageType: s.damageType,
                damageSubType: s.damageSubType,
                basePower: s.basePower,
                pulseCount: s.pulseCount,
                pulseInterval: s.pulseInterval,
                onHitEffects: s.onHitEffects,
                healing: s.healing,
            });
        }
    }
    return lookup;
})();
const SKILL_TO_SUBCATEGORY = {};
for (const category of Object.values(shared_2.CLASS_SKILL_DATA)) {
    for (const subSkill of category.skills) {
        for (const skillName of Object.keys(subSkill.skills)) {
            SKILL_TO_SUBCATEGORY[skillName] = subSkill.name;
        }
    }
}
class SkillSystem {
    constructor() {
        this.gcd = 1000;
        this.globalCooldowns = new Map();
    }
    createStatusEffect(type, potency, sourceId, targetId, overrides) {
        const def = shared_1.STATUS_EFFECT_DEFS[type];
        if (!def)
            return null;
        const now = Date.now();
        return {
            id: `se_${now}_${Math.random().toString(36).slice(2, 6)}`,
            type,
            sourceId,
            targetId,
            potency,
            appliedAt: now,
            duration: overrides?.duration ?? def.duration,
            tickInterval: overrides?.tickInterval ?? def.tickInterval,
            lastTickAt: now,
            stacks: 1,
            ...overrides,
        };
    }
    gainProficiency(session, skillName) {
        const subCategory = SKILL_TO_SUBCATEGORY[skillName];
        if (!subCategory)
            return null;
        const skill = this.findSkillDefinition(skillName);
        if (!skill)
            return null;
        const cap = session.skillProficiencies[subCategory] || 0;
        const current = session.skillAdeptness[subCategory] || 0;
        const hasCastTime = (skill.castTime || 0) > 0.1;
        const result = (0, shared_1.calculateProficiencyGain)(current, cap, hasCastTime);
        if (!result)
            return null;
        session.skillAdeptness[subCategory] = result.newAdeptness;
        (0, shared_1.recalculateCategoryTotals)(session.skillAdeptness);
        result.subCategory = subCategory;
        this.lastProficiencyGain = result;
        return result;
    }
    getWeaponElement(session) {
        const weapon = session.equipment?.weapon;
        if (!weapon)
            return undefined;
        const enh = weapon.stats?.enhancementElement;
        if (enh) {
            return enh.startsWith('magic_') ? enh.slice(6) : enh;
        }
        return weapon.stats?.weaponElement || undefined;
    }
    inferSkillType(skill) {
        if (skill.isPassive)
            return shared_1.SkillType.PASSIVE;
        if (skill.isRevive)
            return shared_1.SkillType.REVIVE;
        if (skill.isSong)
            return shared_1.SkillType.SONG;
        if (skill.sacrificeHeal)
            return shared_1.SkillType.SACRIFICE_HEAL;
        if (skill.mpDamage)
            return shared_1.SkillType.MP_DAMAGE;
        const isMagical = skill.damageType === 'magical'
            || (skill.damageType !== 'physical' && skill.damageSubType && ['fire', 'ice', 'lightning', 'dark', 'holy', 'poison'].includes(skill.damageSubType));
        if (skill.basePower && skill.basePower > 0) {
            return isMagical ? shared_1.SkillType.DAMAGE_MAGICAL : shared_1.SkillType.DAMAGE_PHYSICAL;
        }
        if (skill.isDebuff || skill.debuffEffectTable)
            return shared_1.SkillType.DEBUFF;
        if (skill.invisible)
            return shared_1.SkillType.INVISIBILITY;
        if (skill.barrier)
            return shared_1.SkillType.BARRIER;
        if (skill.healing)
            return shared_1.SkillType.HEAL;
        if (skill.isBuff || skill.buffEffectTable)
            return shared_1.SkillType.BUFF;
        if (skill.createItems)
            return shared_1.SkillType.CRAFT;
        if (skill.summonObject)
            return shared_1.SkillType.SUMMON;
        return undefined;
    }
    getDamageType(st, skill) {
        if (st === shared_1.SkillType.DAMAGE_MAGICAL || st === shared_1.SkillType.MP_DAMAGE)
            return 'magical';
        if (st === shared_1.SkillType.DAMAGE_PHYSICAL || st === shared_1.SkillType.DRAIN_LIFE)
            return 'physical';
        return skill.damageType === 'magical' ? 'magical' : 'physical';
    }
    canUseSkill(session, skillName, targetId) {
        if (session.stats.health <= 0) {
            return { canUse: false, error: 'dead' };
        }
        if (session.activeCast) {
            return { canUse: false, error: 'casting' };
        }
        const now = Date.now();
        const gcdReady = this.globalCooldowns.get(session.characterId) || 0;
        if (now < gcdReady) {
            return { canUse: false, error: 'gcd' };
        }
        const cooldown = session.skillCooldowns?.find(c => c.skillName === skillName && now < c.readyAt);
        if (cooldown) {
            return { canUse: false, error: 'cooldown' };
        }
        const skill = this.findSkillDefinition(skillName);
        if (!skill) {
            return { canUse: false, error: 'not_found' };
        }
        if ((0, shared_1.isPassiveSkill)(skill)) {
            return { canUse: false, error: 'passive' };
        }
        const proficiencies = session.skillProficiencies || {};
        const subCategory = SKILL_TO_SUBCATEGORY[skillName];
        const designJobId = (0, shared_1.getDesignJobId)(session.jobId || 'warrior');
        const effectiveProficiencies = (0, shared_1.getEffectiveProficiencies)(proficiencies, designJobId);
        if (skill.reqLevel && skill.reqLevel > session.stats.level) {
            return { canUse: false, error: 'insufficient_level' };
        }
        if (skill.reqPoints) {
            if (typeof skill.reqPoints === 'number') {
                const catKey = CATEGORY_SKILL_TO_KEY[skillName];
                if (catKey) {
                    const catAdeptness = session.skillAdeptness?.[catKey] || 0;
                    if (catAdeptness < skill.reqPoints) {
                        return { canUse: false, error: 'insufficient_proficiency' };
                    }
                }
                else {
                    const subPoints = subCategory ? (effectiveProficiencies[subCategory] || 0) : 0;
                    if (subPoints < skill.reqPoints) {
                        return { canUse: false, error: 'insufficient_proficiency' };
                    }
                }
            }
            else if (Array.isArray(skill.reqPoints)) {
                if (!(0, shared_1.meetsRequirements)(skill.reqPoints, (name) => effectiveProficiencies[name] || 0)) {
                    return { canUse: false, error: 'insufficient_proficiency' };
                }
            }
        }
        if (session.stats.mana < skill.mpCost) {
            const devotionFx = session.statusEffects?.find(e => e.buffData?.devotionLink);
            if (!devotionFx) {
                return { canUse: false, error: 'no_mana' };
            }
        }
        if (skill.blockOnly) {
            const hasBlockingStance = session.statusEffects?.some(e => e.type === shared_1.StatusEffectType.BUFF_BLOCKING_STANCE || e.buffData?.blockingStance || e.buffData?.defensiveMarch);
            if (!hasBlockingStance) {
                return { canUse: false, error: 'not_blocking' };
            }
        }
        const isBlockStancing = session.statusEffects?.some(e => e.type === shared_1.StatusEffectType.BUFF_BLOCKING_STANCE && e.buffData?.blockingStance);
        if (isBlockStancing) {
            const allowedWhileBlocking = ['Shield Bash', 'Shield Tackle', 'Auto-guard', 'Defensive March', 'Defender', 'Blocking'];
            if (!allowedWhileBlocking.includes(skillName)) {
                return { canUse: false, error: 'blocking' };
            }
        }
        if (skill.shieldRequired) {
            const hasShield = !!session.equipment?.shield;
            if (!hasShield) {
                return { canUse: false, error: 'no_shield' };
            }
        }
        if (skill.requiredWeaponType && skill.requiredWeaponType.length > 0) {
            const weapon = session.equipment?.weapon;
            if (!weapon) {
                return { canUse: false, error: 'wrong_weapon' };
            }
            const weaponDef = this.itemSys.getItemDefinition(weapon.itemId);
            if (!weaponDef?.weaponType || !skill.requiredWeaponType.includes(weaponDef.weaponType)) {
                return { canUse: false, error: 'wrong_weapon' };
            }
        }
        if (skill.negateFieldSpells || skill.debuffEffectTable?.preventFieldSpells) {
            const hasPrevent = session.statusEffects?.some(e => e.type === shared_1.StatusEffectType.PREVENT_FIELD_SPELLS);
            if (hasPrevent) {
                return { canUse: false, error: 'field_blocked' };
            }
        }
        if (session.statusEffects?.some(e => e.type === shared_1.StatusEffectType.SILENCE && skill.mpCost > 0)) {
            return { canUse: false, error: 'silenced' };
        }
        if (session.statusEffects?.some(e => e.type === shared_1.StatusEffectType.BURN) && skill.damageType === 'physical' && skill.basePower && skill.basePower > 0) {
            return { canUse: false, error: 'burn' };
        }
        if (session.statusEffects?.some(e => e.disablePhysicalAttacks)) {
            const isPhysicalDamage = skill.damageType === 'physical' && skill.basePower && skill.basePower > 0;
            if (isPhysicalDamage) {
                return { canUse: false, error: 'disabled' };
            }
        }
        const inferredType = skill.skillType ?? this.inferSkillType(skill);
        const isSinging = session.statusEffects?.some(e => e.type === shared_1.StatusEffectType.SONG_GREEN ||
            e.type === shared_1.StatusEffectType.SONG_BLUE ||
            e.type === shared_1.StatusEffectType.SONG_YELLOW ||
            e.type === shared_1.StatusEffectType.SONG_RED);
        if (isSinging && inferredType !== shared_1.SkillType.SONG) {
            return { canUse: false, error: 'singing' };
        }
        if (session.statusEffects?.some(e => e.type === shared_1.StatusEffectType.STUN ||
            e.type === shared_1.StatusEffectType.SLEEP ||
            e.type === shared_1.StatusEffectType.FREEZE)) {
            return { canUse: false, error: 'cc' };
        }
        if (session.currentNpcId) {
            return { canUse: false, error: 'busy' };
        }
        let targetType = (0, shared_1.getSkillTargetType)(skill) || shared_1.SKILL_TARGET_RULES[skillName];
        if (!targetType) {
            const isGroundTargeted = skill.isAOE && skill.aoeTargetMode === shared_1.AOETargetMode.GROUND_TARGETED;
            if (!isGroundTargeted && inferredType) {
                const typesRequiringTarget = new Set([
                    shared_1.SkillType.DAMAGE_PHYSICAL, shared_1.SkillType.DAMAGE_MAGICAL,
                    shared_1.SkillType.DEBUFF, shared_1.SkillType.DRAIN_LIFE, shared_1.SkillType.MP_DAMAGE,
                    shared_1.SkillType.DISPEL, shared_1.SkillType.FEAR, shared_1.SkillType.PROVOKE, shared_1.SkillType.KNOCKBACK,
                ]);
                if (typesRequiringTarget.has(inferredType)) {
                    targetType = shared_1.SkillTargetType.OTHER_ONLY;
                }
            }
        }
        if (targetType) {
            if (targetType === shared_1.SkillTargetType.OTHER_ONLY) {
                if (!targetId) {
                    return { canUse: false, error: 'no_target' };
                }
                if (targetId === session.characterId) {
                    return { canUse: false, error: 'no_self_target' };
                }
            }
            else if (targetType !== shared_1.SkillTargetType.SELF && targetType !== shared_1.SkillTargetType.SELF_OR_TARGET) {
                if (targetId === session.characterId) {
                    return { canUse: false, error: 'no_self_target' };
                }
            }
        }
        return { canUse: true };
    }
    beginCast(session, skillName, targetId, aoePosition) {
        const skill = this.findSkillDefinition(skillName);
        if (!skill)
            return { started: false, castTime: 0 };
        const baseCastTime = skill.castTime * 1000;
        if (baseCastTime <= 0) {
            return { started: true, castTime: 0 };
        }
        const castSpd = session.stats.castSpeed || 100;
        const effective = session.effectiveStats ?? (0, shared_1.getEffectiveStats)(session.stats, session.statPoints, session.statusEffects || []);
        const castTimeMultiplier = Math.max(0, 100 - effective.castTimeReduction * 100);
        const effectiveCastTime = Math.max(0, Math.floor(baseCastTime * (100 / castSpd) * (castTimeMultiplier / 100)));
        if (effectiveCastTime <= 0) {
            return { started: true, castTime: 0 };
        }
        session.activeCast = {
            skillName,
            startedAt: Date.now(),
            castTime: effectiveCastTime,
            targetId,
            aoePosition
        };
        return { started: true, castTime: effectiveCastTime };
    }
    executeSkill(session, skillName, targetId, getTargetStats) {
        const skill = this.findSkillDefinition(skillName);
        if (!skill)
            return { success: false, error: 'not_found' };
        const st = skill.skillType ?? this.inferSkillType(skill);
        if (st === shared_1.SkillType.SONG) {
            const songMap = {
                green: shared_1.StatusEffectType.SONG_GREEN,
                blue: shared_1.StatusEffectType.SONG_BLUE,
                yellow: shared_1.StatusEffectType.SONG_YELLOW,
                red: shared_1.StatusEffectType.SONG_RED,
            };
            const songType = skill.buffEffectTable?.songType;
            const songEffectType = songType ? songMap[songType] : undefined;
            if (songEffectType && session.statusEffects?.some(e => e.type === songEffectType)) {
                session.statusEffects = session.statusEffects.filter(e => e.type !== songEffectType && e.skillName !== skill.name);
                session.activeCast = null;
                return { success: true, songToggledOff: true };
            }
        }
        session.stats.mana -= skill.mpCost;
        const now = Date.now();
        if (!session.skillCooldowns)
            session.skillCooldowns = [];
        const totalINT = (session.statPoints.INT || 0) + (session.baseStats?.INT || 0);
        const cooldownReduction = Math.floor(totalINT / 10) * 2;
        const magicalAidFx = session.statusEffects?.find(e => e.buffData?.magicalAid);
        const magicalAidCdReduction = magicalAidFx ? 20 : 0;
        const cooldownMultiplier = Math.max(0, 100 - cooldownReduction - magicalAidCdReduction) / 100;
        const effectiveCooldown = Math.floor(skill.cooldown * 1000 * cooldownMultiplier);
        if (cooldownReduction > 0) {
            this.lastCooldownDebug = { skillName, totalINT, cooldownReduction, baseCd: skill.cooldown, effective: effectiveCooldown / 1000 };
        }
        session.skillCooldowns.push({
            skillName,
            readyAt: now + effectiveCooldown
        });
        this.globalCooldowns.set(session.characterId, now + this.gcd);
        session.activeCast = null;
        this.gainProficiency(session, skillName);
        if (st === shared_1.SkillType.REVIVE && targetId) {
            return { success: true, revived: true };
        }
        if (st === shared_1.SkillType.PROVOKE) {
            return { success: true, provoked: true, targetId: targetId || undefined };
        }
        if (st === shared_1.SkillType.DEBUFF || st === shared_1.SkillType.FEAR || st === shared_1.SkillType.DISPEL) {
            if (skill.debuffEffectTable) {
                const debuffEffects = this.buildDebuffEffects(session, skill);
                return { success: true, statusEffects: debuffEffects.length > 0 ? debuffEffects : undefined };
            }
            if (st === shared_1.SkillType.FEAR) {
                return { success: true, fear: true };
            }
            if (st === shared_1.SkillType.DISPEL) {
                return { success: true, dispelBuff: skill.dispelBuff, dispelDebuff: skill.dispelDebuff };
            }
            if (skill.onHitEffects && skill.onHitEffects.length > 0) {
                const statusEffects = this.buildStatusEffects(session, skill, 0);
                return { success: true, statusEffects: statusEffects.length > 0 ? statusEffects : undefined };
            }
            return { success: true };
        }
        if (st === shared_1.SkillType.CRAFT && skill.createItems && skill.createItems.length > 0) {
            return { success: true, createdItems: skill.createItems };
        }
        if (st === shared_1.SkillType.SACRIFICE_HEAL && targetId) {
            return { success: true, sacrificeHeal: true, targetId };
        }
        if (st === shared_1.SkillType.MP_DAMAGE && targetId) {
            const basePower = skill.basePower ?? 1;
            const mpTotalINT = (session.statPoints.INT || 0) + (session.baseStats?.INT || 0);
            const mpTotalSPI = (session.statPoints.SPI || 0) + (session.baseStats?.SPI || 0);
            const mpDamageAmount = Math.floor(basePower * (mpTotalINT + mpTotalSPI * 0.3) * 0.5);
            return { success: true, mpDamage: mpDamageAmount, damageType: 'magical' };
        }
        const isBuffLike = st === shared_1.SkillType.BUFF || st === shared_1.SkillType.SONG
            || st === shared_1.SkillType.HP_BUFF || st === shared_1.SkillType.MP_RESTORE
            || st === shared_1.SkillType.HEAL_OVER_TIME
            || st === shared_1.SkillType.INVISIBILITY || st === shared_1.SkillType.BARRIER;
        if ((isBuffLike && skill.duration > 0) || (skill.buffEffectTable && skill.duration === 0)) {
            if (skill.buffEffectTable?.defensiveMarch) {
                const existing = session.statusEffects?.find(e => e.type === shared_1.StatusEffectType.BUFF_BLOCKING_STANCE && e.buffData?.defensiveMarch && e.skillName === skillName);
                if (existing) {
                    session.statusEffects = session.statusEffects.filter(e => e !== existing);
                    return { success: true, defensiveMarchToggledOff: true };
                }
            }
            if (skill.buffEffectTable?.damageRedirect && targetId) {
                const existing = session.statusEffects?.find(e => e.type === shared_1.StatusEffectType.BUFF_DAMAGE_REDIRECT && e.skillName === skillName);
                if (existing) {
                    const oldTarget = existing.buffData?.damageRedirectTargetId || existing.targetId;
                    session.statusEffects = session.statusEffects.filter(e => e !== existing);
                    return { success: true, guardianToggledOff: true, guardianRemovedTarget: oldTarget };
                }
                this.applyGuardianBuff(session, skill, targetId);
                return { success: true, guardianApplied: targetId };
            }
            if (skill.buffEffectTable?.devotion) {
                return { success: true };
            }
            this.applyBuff(session, skill);
        }
        if (st === shared_1.SkillType.MP_RESTORE) {
            const mpAmount = this.calculateMpRegen(session, skill);
            session.stats.mana = Math.min(session.stats.maxMana, session.stats.mana + mpAmount);
            return { success: true, mpRestored: mpAmount };
        }
        if (st === shared_1.SkillType.HEAL || st === shared_1.SkillType.HEAL_OVER_TIME || st === shared_1.SkillType.PARTY_HEAL) {
            const healAmount = this.calculateHealing(session, skill);
            return { success: true, healing: healAmount };
        }
        if (st === shared_1.SkillType.HP_BUFF && (!targetId || targetId === session.characterId)) {
            const hpIncrease = this.calculateMaxHpBuff(session, skill);
            const healthRatio = session.stats.maxHealth > 0 ? session.stats.health / session.stats.maxHealth : 1;
            session.stats.maxHealth += hpIncrease;
            session.stats.health = Math.min(session.stats.maxHealth, Math.floor(session.stats.maxHealth * healthRatio) + hpIncrease);
            return { success: true, maxHpIncrease: hpIncrease, healing: hpIncrease };
        }
        if ((st === shared_1.SkillType.DAMAGE_PHYSICAL || st === shared_1.SkillType.DAMAGE_MAGICAL) && targetId) {
            const target = getTargetStats(targetId);
            if (target) {
                const dmgType = this.getDamageType(st, skill);
                const result = this.calculateSkillDamage(session, skill, target, dmgType);
                if (skill.debuffEffectTable) {
                    const debuffEffects = this.buildDebuffEffects(session, skill);
                    if (debuffEffects.length > 0) {
                        result.statusEffects = debuffEffects;
                    }
                }
                this.applyDualPhysical(session, skill, target, result);
                return result;
            }
        }
        if (st === shared_1.SkillType.DRAIN_LIFE && targetId) {
            const target = getTargetStats(targetId);
            if (target) {
                const result = this.calculateSkillDamage(session, skill, target, 'physical');
                if (result.damage && result.damage > 0 && !result.missed) {
                    const drainHeal = Math.floor(result.damage * 0.3);
                    return { ...result, healing: drainHeal };
                }
                return result;
            }
        }
        if (st === shared_1.SkillType.SUMMON && skill.summonObject) {
            let element;
            if (skill.summonObject.objectType === 'plant') {
                element = this.getWeaponElement(session);
            }
            return {
                success: true,
                summonObject: { ...skill.summonObject },
                element,
            };
        }
        if (skill.banishObject) {
            return {
                success: true,
                banishObject: true,
                banishRadius: skill.banishRadius || 5,
            };
        }
        if (skill.manaSwap) {
            return { success: true, manaSwap: true };
        }
        if (skill.soulSwap) {
            return { success: true, soulSwap: true };
        }
        return { success: true };
    }
    applyDualPhysical(session, skill, target, result) {
        if (!skill.dualPhysical)
            return;
        const physSkill = {
            ...skill,
            basePower: skill.dualPhysical.basePower,
            damageType: 'physical',
            damageSubType: (skill.dualPhysical.damageSubType ?? 'slash'),
            scalingStat: skill.dualPhysical.scalingStat,
            debuffEffectTable: undefined,
            hasDebuff: false,
        };
        const physResult = this.calculateSkillDamageInternal(session, physSkill, target, 'physical');
        result.physicalDamage = physResult.damage;
        result.physicalElementalDamage = physResult.elementalDamage;
    }
    calculateAOEDamage(session, skillName, targetId, getTargetStats) {
        const skill = this.findSkillDefinition(skillName);
        if (!skill)
            return { success: false, error: 'not_found' };
        const st = skill.skillType ?? this.inferSkillType(skill);
        const isDamage = st === shared_1.SkillType.DAMAGE_PHYSICAL || st === shared_1.SkillType.DAMAGE_MAGICAL
            || st === shared_1.SkillType.DRAIN_LIFE || st === shared_1.SkillType.MP_DAMAGE;
        if (!isDamage)
            return { success: true };
        const target = getTargetStats(targetId);
        if (!target)
            return { success: true, missed: true };
        const dmgType = this.getDamageType(st, skill);
        const result = this.calculateSkillDamageInternal(session, skill, target, dmgType);
        if (skill.debuffEffectTable) {
            const debuffEffects = this.buildDebuffEffects(session, skill);
            if (debuffEffects.length > 0) {
                result.statusEffects = debuffEffects;
            }
        }
        if (skill.dualPhysical) {
            this.applyDualPhysical(session, skill, target, result);
        }
        return result;
    }
    calculateSkillDamage(session, skill, target, damageType) {
        return this.calculateSkillDamageInternal(session, skill, target, damageType);
    }
    calculateSkillDamageInternal(session, skill, target, damageType) {
        const isMagical = damageType === 'magical';
        const numHits = skill.baseHits || 1;
        const hitChance = this.calculateAccuracy(session, target);
        const effectiveStats = session.effectiveStats ?? (0, shared_1.getEffectiveStats)(session.stats, session.statPoints, session.statusEffects || []);
        const basePower = skill.basePower ?? 1;
        const baseStats = session.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
        let primaryStat;
        if (isMagical) {
            primaryStat = session.stats.magicAttack || ((session.statPoints.INT || 0) + (baseStats.INT || 0));
        }
        else if (skill.scalingStat) {
            const stat = skill.scalingStat;
            primaryStat = (session.statPoints[stat] || 0) + (baseStats[stat] || 0);
        }
        else {
            primaryStat = (session.statPoints.STR || 0) + (baseStats.STR || 0);
        }
        if (skill.proficiencyBonus && skill.proficiencyBonus > 0) {
            const subCategory = this.getSubCategoryForSkill(skill.name || '');
            if (subCategory) {
                const prof = session.skillAdeptness?.[subCategory] || 0;
                primaryStat += Math.floor(prof * skill.proficiencyBonus);
            }
        }
        const secondaryStat = isMagical
            ? (session.statPoints.SPI || 0) + (baseStats.SPI || 0)
            : (session.statPoints.DEX || 0) + (baseStats.DEX || 0);
        const hasBurn = !isMagical && session.statusEffects?.some(e => e.type === shared_1.StatusEffectType.BURN);
        const hasAttackHalved = !isMagical && session.statusEffects?.some(e => e.attackHalved);
        const effectivePrimaryStat = hasBurn ? Math.floor(primaryStat * 0.5) : hasAttackHalved ? Math.floor(primaryStat * 0.5) : primaryStat;
        const defenseStat = isMagical ? target.magicDefense : target.defense;
        let attackMultiplier = 1;
        const attackBuff = session.statusEffects?.find(e => e.type === shared_1.StatusEffectType.BUFF_ATTACK);
        if (attackBuff && !isMagical) {
            attackMultiplier = attackBuff.potency;
        }
        const magicalAidBuff = isMagical ? session.statusEffects?.find(e => e.buffData?.magicalAid) : null;
        if (magicalAidBuff) {
            attackMultiplier *= 1.2;
        }
        const baseDamage = skill.damageVsLowDefense
            ? Math.floor(basePower * (effectivePrimaryStat + secondaryStat * 0.3) * attackMultiplier
                + defenseStat * 0.5)
            : Math.floor(basePower * (effectivePrimaryStat + secondaryStat * 0.3) * attackMultiplier
                - defenseStat * 0.5);
        let elementalResistMultiplier = 1;
        if (isMagical && skill.damageSubType) {
            const resistMap = {
                fire: target.fireResist,
                ice: target.iceResist,
                lightning: target.lightningResist,
                dark: target.darkResist,
                holy: target.holyResist,
            };
            let resist = resistMap[skill.damageSubType] || 0;
            // Obelisk buff: attacker ignores a flat amount of the target's magic
            // resistance (penetration — floored at 0 so it never creates bonus
            // damage against targets with no resist).
            const obelisk = (0, obeliskBuff_1.getObeliskBuffForWeapon)(this.itemSys, session.equipment?.weapon);
            if (obelisk && obelisk.resistIgnore > 0 && resist > 0) {
                resist = Math.max(0, resist - obelisk.resistIgnore);
            }
            if (resist !== 0) {
                elementalResistMultiplier = resist > 0
                    ? 1 - Math.min(0.75, resist / 100)
                    : 1 + Math.min(1.0, Math.abs(resist) / 100);
            }
        }
        let physReduction = 0;
        if (!isMagical && target.physicalDamageReduction && target.physicalDamageReduction > 0) {
            physReduction = Math.min(0.9, target.physicalDamageReduction);
        }
        const totalDex = (session.statPoints.DEX || 0) + (session.baseStats?.DEX || 0);
        const critChance = shared_1.COMBAT_CONFIG.CRITICAL_CHANCE + totalDex * 0.002;
        const levelDiff = session.stats.level - target.level;
        let levelMultiplier = 1;
        if (levelDiff > 0) {
            levelMultiplier = 1 + levelDiff * 0.03;
        }
        else if (levelDiff < 0) {
            const penalty = 1 - 0.5 * (1 - Math.exp(levelDiff * 0.03));
            levelMultiplier = Math.max(0.25, penalty);
        }
        const totalSPI = (session.statPoints.SPI || 0) + (baseStats.SPI || 0);
        const totalINT = (session.statPoints.INT || 0) + (baseStats.INT || 0);
        const targetResists = {
            fireResist: target.fireResist,
            iceResist: target.iceResist,
            lightningResist: target.lightningResist,
            darkResist: target.darkResist,
            holyResist: target.holyResist,
            poisonResist: target.poisonResist,
        };
        const steps = [];
        if (isMagical) {
            steps.push(`basePower=${basePower} magicAttack=${primaryStat}(INT=${session.statPoints.INT + baseStats.INT}) SPI=${secondaryStat}`);
        }
        else {
            steps.push(`basePower=${basePower} STR=${primaryStat}(base${baseStats.STR}+alloc${session.statPoints.STR}) DEX=${secondaryStat}`);
        }
        steps.push(`raw=${basePower}×(${primaryStat}+${secondaryStat}×0.3)×${attackMultiplier}-${defenseStat}×0.5=${baseDamage}`);
        const hits = [];
        let totalDamage = 0;
        let anyCritical = false;
        let anyMissed = false;
        for (let h = 0; h < numHits; h++) {
            if (Math.random() > hitChance) {
                hits.push({ damage: 0, isCritical: false, missed: true });
                anyMissed = true;
                if (numHits > 1)
                    steps.push(`hit${h + 1}: miss`);
                continue;
            }
            let damage = baseDamage;
            const weaponEnhElement = session.equipment?.weapon?.enhancementElement;
            const weaponEnhLevel = session.equipment?.weapon?.enhancementLevel;
            const magicBoost = (0, shared_1.getMagicEnhancementBoost)(weaponEnhElement, weaponEnhLevel, skill.damageSubType);
            if (magicBoost > 1) {
                damage = Math.floor(damage * magicBoost);
            }
            if (elementalResistMultiplier !== 1) {
                damage = Math.floor(damage * elementalResistMultiplier);
            }
            if (physReduction > 0) {
                damage = Math.floor(damage * (1 - physReduction));
            }
            const isCrit = !isMagical && Math.random() < critChance;
            if (isCrit) {
                damage = Math.floor(damage * shared_1.COMBAT_CONFIG.CRITICAL_MULTIPLIER);
                anyCritical = true;
            }
            damage = Math.floor(damage * levelMultiplier);
            const varianceRoll = 0.9 + Math.random() * 0.2;
            damage = Math.floor(damage * varianceRoll);
            damage = Math.max(shared_1.COMBAT_CONFIG.MIN_DAMAGE, damage);
            if (target.damageTakenMultiplier && target.damageTakenMultiplier > 1) {
                damage = Math.floor(damage * target.damageTakenMultiplier);
            }
            const allElemental = [];
            if (damageType !== 'magical') {
                const skillElement = skill.damageSubType;
                if (skillElement && ['fire', 'ice', 'lightning', 'dark', 'holy', 'poison'].includes(skillElement)) {
                    const elemPower = skill.elementalPower ?? skill.basePower ?? 1;
                    allElemental.push((0, shared_1.computeElementalDamageLine)(elemPower, totalSPI, totalINT, session.stats.level, skillElement, targetResists));
                }
                const skillWeaponDef = this.itemSys.getItemDefinition(session.equipment?.weapon?.itemId);
                const weaponElem = (0, shared_1.calculateWeaponElementalDamage)(skillWeaponDef?.stats.weaponElement, skillWeaponDef?.stats.weaponElementPower, session.statusEffects || [], totalSPI, totalINT, session.stats.level, targetResists, session.equipment?.weapon?.enhancementElement, session.equipment?.weapon?.enhancementLevel, effectiveStats.auraDamageMultiplier);
                allElemental.push(...weaponElem);
            }
            hits.push({
                damage,
                isCritical: isCrit,
                elementalDamage: allElemental.length > 0 ? allElemental : undefined,
            });
            totalDamage += damage;
            if (numHits === 1) {
                if (isCrit)
                    steps.push(`crit=${damage}`);
            }
            else {
                steps.push(`hit${h + 1}=${damage}${isCrit ? '(crit)' : ''}`);
            }
        }
        steps.push(`total=${totalDamage}`);
        const statusEffects = this.buildStatusEffects(session, skill, totalDamage);
        const result = {
            success: true,
            damage: totalDamage,
            isCritical: anyCritical,
            missed: numHits === 1 ? anyMissed : undefined,
            damageType,
            statusEffects: statusEffects.length > 0 ? statusEffects : undefined,
            debugCalc: `[${skill.name}] ${steps.join(' → ')} → final=${totalDamage}`,
        };
        if (numHits > 1) {
            result.hits = hits;
        }
        else if (hits.length > 0 && hits[0].elementalDamage) {
            result.elementalDamage = hits[0].elementalDamage;
        }
        return result;
    }
    buildStatusEffects(session, skill, damage) {
        if (!skill.onHitEffects || skill.onHitEffects.length === 0)
            return [];
        const effects = [];
        const now = Date.now();
        for (const oh of skill.onHitEffects) {
            const chance = oh.chance ?? 1;
            if (Math.random() > chance)
                continue;
            let potency = oh.potency ?? 0;
            if (typeof potency === 'object' && potency !== null) {
                const base = potency.formula || '0';
                const statName = potency.stat || 'INT';
                const statValue = (session.statPoints[statName] || 0)
                    + (session.baseStats?.[statName] || 0);
                const vars = { ...potency, damage, [statName]: statValue };
                potency = (0, shared_1.safeFormulaEval)(base, vars);
            }
            const effect = this.createStatusEffect(oh.type, potency, session.characterId, '', {
                duration: oh.duration,
            });
            if (effect)
                effects.push(effect);
        }
        return effects;
    }
    buildDebuffEffects(casterSession, skill) {
        const dt = skill.debuffEffectTable;
        const effects = [];
        const now = Date.now();
        const duration = (skill.debuffDuration || skill.duration || 30) * 1000;
        const category = dt.debuffCategory;
        const addEffect = (type, potency, extra) => {
            const def = shared_1.STATUS_EFFECT_DEFS[type];
            if (def) {
                effects.push({
                    id: `debuff_${Date.now()}_${Math.random().toString(36).slice(2, 6)}_${type}`,
                    type,
                    sourceId: casterSession.characterId,
                    targetId: '',
                    potency,
                    appliedAt: now,
                    duration,
                    tickInterval: def.tickInterval,
                    lastTickAt: now,
                    stacks: 1,
                    skillName: skill.name,
                    debuffCategory: category,
                    ...extra,
                });
            }
        };
        if (dt.dot) {
            const tickInterval = dt.dotTickInterval || 2000;
            let statusType;
            switch (dt.dot) {
                case 'poison':
                    statusType = shared_1.StatusEffectType.POISON;
                    break;
                case 'severe_poison':
                    statusType = shared_1.StatusEffectType.SEVERE_POISON;
                    break;
                case 'bleed':
                    statusType = shared_1.StatusEffectType.BLEED;
                    break;
                case 'mp_drain':
                    statusType = shared_1.StatusEffectType.MP_DRAIN;
                    break;
                default:
                    return effects;
            }
            let dotHPPercent = dt.dotHPPercent;
            if (dt.dotSPIBase !== undefined && dt.dotSPIMax !== undefined) {
                const casterSPI = casterSession.statPoints.SPI || 0;
                const cap = dt.dotSPICap || 110;
                const progress = Math.min(1, casterSPI / cap);
                dotHPPercent = dt.dotSPIBase + progress * (dt.dotSPIMax - dt.dotSPIBase);
            }
            addEffect(statusType, dt.dotPotency || 0, {
                tickInterval,
                dotMpDrain: dt.dotMpDrain,
                dotHPPercent,
            });
            return effects;
        }
        const DEBUFF_PROPERTY_MAP = [
            { prop: 'attackDown', effectType: shared_1.StatusEffectType.DEBUFF_DAMAGE_DOWN },
            { prop: 'defenseDown', effectType: shared_1.StatusEffectType.DEBUFF_DEFENSE_DOWN },
            { prop: 'speedDown', effectType: shared_1.StatusEffectType.DEBUFF_SPEED_DOWN },
            { prop: 'accuracyDown', effectType: shared_1.StatusEffectType.DEBUFF_ACCURACY_DOWN },
            { prop: 'dodgeDown', effectType: shared_1.StatusEffectType.DEBUFF_DODGE_DOWN },
            { prop: 'castSpeedDown', effectType: shared_1.StatusEffectType.DEBUFF_CAST_SPEED_DOWN },
            { prop: 'damageTakenUp', effectType: shared_1.StatusEffectType.DEBUFF_DAMAGE_TAKEN_UP, extra: { consumable: dt.consumable || false } },
            { prop: 'moveSpeedDown', effectType: shared_1.StatusEffectType.SLOW },
            { prop: 'hasFreeze', effectType: shared_1.StatusEffectType.FREEZE, extra: { duration: dt.hasFreeze?.duration * 1000 } },
            { prop: 'hasSleep', effectType: shared_1.StatusEffectType.SLEEP, extra: { duration: dt.hasSleep?.duration * 1000 } },
            { prop: 'hasStun', effectType: shared_1.StatusEffectType.STUN, extra: { duration: dt.hasStun?.duration * 1000 } },
            { prop: 'hasSilence', effectType: shared_1.StatusEffectType.SILENCE, extra: { duration: dt.hasSilence?.duration * 1000 } },
            { prop: 'disablePhysicalAttacks', effectType: shared_1.StatusEffectType.BUFF_GENERIC, extra: { disablePhysicalAttacks: true } },
            { prop: 'attackHalved', effectType: shared_1.StatusEffectType.BUFF_GENERIC, extra: { attackHalved: true } },
            { prop: 'preventFieldSpells', effectType: shared_1.StatusEffectType.PREVENT_FIELD_SPELLS },
            { prop: 'preventResurrect', effectType: shared_1.StatusEffectType.PREVENT_RESSURECT },
            { prop: 'curse', effectType: shared_1.StatusEffectType.CURSE },
            { prop: 'revealInvisible', effectType: shared_1.StatusEffectType.BUFF_GENERIC },
        ];
        for (const mapping of DEBUFF_PROPERTY_MAP) {
            const value = dt[mapping.prop];
            if (value === undefined || value === null || value === false)
                continue;
            let potency = typeof value === 'number' ? value : 0;
            const extra = typeof value === 'object' && value !== null ? mapping.extra : undefined;
            const effect = this.createStatusEffect(mapping.effectType, potency, casterSession.characterId, '', {
                skillName: skill.name,
                debuffCategory: category,
                ...extra,
            });
            if (effect)
                effects.push(effect);
        }
        if (dt.mpDamage && dt.mpDamageDirect) {
            const effect = this.createStatusEffect(shared_1.StatusEffectType.MP_DAMAGE_DEBUFF, dt.mpDamage, casterSession.characterId, '', { mpDamageDirect: dt.mpDamage });
            if (effect)
                effects.push(effect);
        }
        if (dt.removeResistBuffs && dt.removeResistBuffs.length > 0) {
            const effect = this.createStatusEffect(shared_1.StatusEffectType.BUFF_GENERIC, 0, casterSession.characterId, '', {
                skillName: skill.name,
                debuffCategory: category,
                removeResistBuffs: dt.removeResistBuffs,
            });
            if (effect)
                effects.push(effect);
        }
        return effects;
    }
    calculateAccuracy(session, target) {
        if (target.dodge === 0)
            return 0.99;
        const baseStats = session.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
        const totalDex = (session.statPoints.DEX || 0) + (baseStats.DEX || 0);
        const attackerAccuracy = (0, shared_1.calculateAccuracy)(session.stats.level, totalDex, 0);
        const hitChance = (0, shared_1.calculateHitChance)(attackerAccuracy, target.dodge);
        return Math.min(0.99, Math.max(0.01, hitChance));
    }
    calculateHealing(session, skill) {
        const baseStats = session.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
        const totalSPI = (session.statPoints.SPI || 0) + baseStats.SPI;
        const totalINT = (session.statPoints.INT || 0) + baseStats.INT;
        const level = session.stats.level;
        if (!skill.healing) {
            const multiplier = 1.0 + (skill.mpCost / 30);
            return Math.floor((totalSPI * 2.0 + totalINT * 1.0 + level * 2) * multiplier);
        }
        const h = skill.healing;
        const proficiencies = session.skillAdeptness || {};
        const profStat = h.proficiencyStat || 'Grace';
        const prof = proficiencies[profStat] || 0;
        const baseAmount = h.baseAmount || 0;
        const spiScale = h.statMultipliers?.SPI ?? 0.3;
        const intScale = h.statMultipliers?.INT ?? 0.6;
        const levelScale = h.statMultipliers?.level ?? 1.0;
        const profScale = h.statMultipliers?.prof ?? 2.0;
        const mpMult = h.mpCostScaling
            ? 1.0 + (skill.mpCost / h.mpCostScaling)
            : 1.0 + (skill.mpCost / 30);
        const healPercent = session.statBreakdown?.healPercent || 0;
        const gearMult = 1 + (healPercent / 100);
        return Math.floor((baseAmount + totalSPI * spiScale + totalINT * intScale + level * levelScale + prof * profScale) * mpMult * gearMult);
    }
    calculateMpRegen(session, skill) {
        const spi = session.statPoints.SPI;
        const level = session.stats.level;
        const multiplier = 1.0 + (skill.mpCost / 15);
        return Math.floor((spi * 1.5 + level * 1.5) * multiplier);
    }
    calculateMaxHpBuff(session, skill) {
        if (skill.healing && skill.healing.type === 'hp_buff') {
            const h = skill.healing;
            const baseHp = session.stats.maxHealth;
            let increase = 0;
            if (h.percentOfMaxHp) {
                increase += Math.floor(baseHp * (h.percentOfMaxHp / 100));
            }
            if (h.flatBonus) {
                increase += h.flatBonus;
            }
            if (increase === 0) {
                increase = Math.floor(baseHp * 0.1 + session.stats.level * 5);
            }
            return increase;
        }
        return 0;
    }
    applyBuff(session, skill) {
        this.applyBuffToTarget(session, session.characterId, skill, session);
    }
    applyGuardianBuff(session, skill, targetCharacterId) {
        const now = Date.now();
        const duration = (skill.duration || 300) * 1000;
        session.statusEffects = session.statusEffects.filter(e => e.type !== shared_1.StatusEffectType.BUFF_DAMAGE_REDIRECT);
        session.statusEffects.push({
            id: `buff_${Date.now()}_${Math.random().toString(36).slice(2, 6)}_guardian`,
            type: shared_1.StatusEffectType.BUFF_DAMAGE_REDIRECT,
            sourceId: session.characterId,
            targetId: targetCharacterId,
            potency: 0,
            appliedAt: now,
            duration,
            tickInterval: 0,
            lastTickAt: now,
            stacks: 1,
            skillName: skill.name,
            buffData: { damageRedirectTargetId: targetCharacterId },
        });
    }
    applyBuffToTarget(target, sourceId, skill, casterSession) {
        const now = Date.now();
        const duration = skill.isSong ? 5000 : (skill.duration || 300) * 1000;
        const bt = skill.buffEffectTable;
        const effects = [];
        const pushEffect = (type, potency, buffData, extra) => {
            target.statusEffects = target.statusEffects.filter(e => !(e.skillName === skill.name && e.type === type));
            effects.push({
                id: `buff_${Date.now()}_${Math.random().toString(36).slice(2, 6)}_${type}`,
                type,
                sourceId,
                targetId: target.characterId,
                potency,
                appliedAt: now,
                duration,
                tickInterval: 0,
                lastTickAt: now,
                stacks: 1,
                skillName: skill.name,
                buffData,
                ...extra,
            });
        };
        if (!bt) {
            if (skill.skillType === shared_1.SkillType.HP_BUFF) {
                const baseMaxHp = target.stats.maxHealth;
                const hpIncrease = Math.floor(baseMaxHp * 0.15) + 250;
                pushEffect(shared_1.StatusEffectType.BUFF_MAX_HP, 0, { maxHpFlat: hpIncrease, maxHpPercent: 0.15 });
            }
            else if (effects.length === 0) {
                pushEffect(shared_1.StatusEffectType.BUFF_GENERIC, 0);
            }
            target.statusEffects.push(...effects);
            return;
        }
        if (bt.attackPowerMultiplier) {
            pushEffect(shared_1.StatusEffectType.BUFF_ATTACK, bt.attackPowerMultiplier);
        }
        if (bt.def) {
            pushEffect(shared_1.StatusEffectType.BUFF_DEFENSE, 0, { flatDefense: bt.def });
        }
        if (bt.str || bt.agi || bt.int || bt.spi || bt.dex || bt.sta) {
            pushEffect(shared_1.StatusEffectType.BUFF_STAT, 0, {
                flatStats: {
                    str: bt.str || 0,
                    agi: bt.agi || 0,
                    int: bt.int || 0,
                    spi: bt.spi || 0,
                    dex: bt.dex || 0,
                    sta: bt.sta || 0,
                },
            });
        }
        if (bt.castTime) {
            const reduction = Math.abs(bt.castTime) / 100;
            pushEffect(shared_1.StatusEffectType.BUFF_CAST_SPEED, reduction);
        }
        if (bt.maxHp) {
            pushEffect(shared_1.StatusEffectType.BUFF_MAX_HP, 0, { maxHpFlat: bt.maxHp });
        }
        if (bt.mpRegen) {
            pushEffect(shared_1.StatusEffectType.BUFF_MP_REGEN, bt.mpRegen);
        }
        if (bt.mpRestorePerTick) {
            const cfg = bt.mpRestorePerTick;
            const caster = casterSession || target;
            const statVal = cfg.statScale
                ? (caster.baseStats?.[cfg.statScale] || 0) + (caster.statPoints?.[cfg.statScale] || 0)
                : 0;
            const profVal = cfg.proficiencyStat
                ? (caster.skillAdeptness?.[cfg.proficiencyStat] || 0)
                : 0;
            const mpPerTick = Math.floor(cfg.base + statVal * (cfg.statMultiplier ?? 0) + profVal * (cfg.proficiencyMultiplier ?? 0));
            pushEffect(shared_1.StatusEffectType.BUFF_MP_REGEN, 0, { mpRestorePerTick: { mpPerTick, tickInterval: 3000 } });
        }
        if (bt.physicalDamageReduction) {
            let reductionPercent = 0;
            if (bt.physicalDamageReduction.startsWith('formula:')) {
                const formula = bt.physicalDamageReduction.replace('formula:', '');
                const blessing = casterSession
                    ? (casterSession.skillAdeptness?.['Blessing'] || 0)
                    : (target.skillAdeptness?.['Blessing'] || 0);
                const expr = formula
                    .replace(/blessing/g, String(blessing));
                reductionPercent = (0, shared_1.safeFormulaEval)(expr, { blessing });
            }
            else {
                const parsed = parseFloat(bt.physicalDamageReduction);
                if (!isNaN(parsed))
                    reductionPercent = parsed;
            }
            pushEffect(shared_1.StatusEffectType.BUFF_PHYSICAL_REDUC, reductionPercent);
        }
        if (bt.dodgeChance) {
            pushEffect(shared_1.StatusEffectType.BUFF_DODGE, bt.dodgeChance);
        }
        if (bt.weaponAura) {
            const aura = bt.weaponAura;
            const caster = casterSession || target;
            const subCategory = SKILL_TO_SUBCATEGORY[skill.name];
            const proficiency = subCategory ? (caster.skillAdeptness?.[subCategory] || 0) : 0;
            const casterBaseSPI = (caster.baseStats?.SPI || 0) + (caster.statPoints?.SPI || 0);
            if (aura.spiTiers) {
                const lookupValue = casterBaseSPI + proficiency;
                let matchedTier = aura.spiTiers[0];
                for (const tier of aura.spiTiers) {
                    if (lookupValue >= tier.spi) {
                        matchedTier = tier;
                    }
                    else {
                        break;
                    }
                }
                pushEffect(shared_1.StatusEffectType.WEAPON_AURA, 0, {
                    weaponAura: { element: aura.element, minDamage: matchedTier.min, maxDamage: matchedTier.max },
                });
            }
            else if (aura.formula === 'toxify') {
                const level = caster.stats?.level || 1;
                const auraDamage = Math.floor(level * (100 + proficiency) / 100);
                pushEffect(shared_1.StatusEffectType.WEAPON_AURA, 0, {
                    weaponAura: { element: aura.element, minDamage: auraDamage, maxDamage: auraDamage },
                });
            }
        }
        if (bt.accuracy) {
            pushEffect(shared_1.StatusEffectType.BUFF_ACCURACY, bt.accuracy);
        }
        if (bt.attackSpeed) {
            pushEffect(shared_1.StatusEffectType.BUFF_ATTACK_SPEED, bt.attackSpeed / 100);
        }
        if (bt.resistMods) {
            target.statusEffects = target.statusEffects.filter(e => e.exclusiveGroup !== 'resist_element');
            pushEffect(shared_1.StatusEffectType.BUFF_RESIST, 0, { resistMods: bt.resistMods }, { exclusiveGroup: 'resist_element' });
        }
        if (bt.moveSpeed) {
            pushEffect(shared_1.StatusEffectType.BUFF_MOVE_SPEED, bt.moveSpeed, { moveSpeedFlat: bt.moveSpeed });
        }
        if (bt.critResist) {
            pushEffect(shared_1.StatusEffectType.BUFF_CRIT_RESIST, bt.critResist, { critResistPercent: bt.critResist });
        }
        if (bt.critDamageReduce) {
            pushEffect(shared_1.StatusEffectType.BUFF_CRIT_DAMAGE_REDUCE, bt.critDamageReduce, { critDamageReducePercent: bt.critDamageReduce });
        }
        if (bt.auraDamageReduce) {
            pushEffect(shared_1.StatusEffectType.BUFF_AURA_DAMAGE_REDUCE, bt.auraDamageReduce, { auraDamageReducePercent: bt.auraDamageReduce });
        }
        if (bt.manaShield) {
            target.statusEffects = target.statusEffects.filter(e => e.type !== shared_1.StatusEffectType.BUFF_MANA_SHIELD);
            pushEffect(shared_1.StatusEffectType.BUFF_MANA_SHIELD, 0, { manaShield: true });
        }
        if (bt.invisible) {
            target.statusEffects = target.statusEffects.filter(e => e.type !== shared_1.StatusEffectType.INVISIBLE);
            pushEffect(shared_1.StatusEffectType.INVISIBLE, 0, { invisible: bt.invisible }, { invisible: true, tickInterval: 1000 });
        }
        if (bt.barrierPhysical) {
            target.statusEffects = target.statusEffects.filter(e => e.type !== shared_1.StatusEffectType.BARRIER_PHYSICAL);
            pushEffect(shared_1.StatusEffectType.BARRIER_PHYSICAL, 0, { barrierPhysical: true }, { barrierType: 'physical' });
        }
        if (bt.barrierMagical) {
            target.statusEffects = target.statusEffects.filter(e => e.type !== shared_1.StatusEffectType.BARRIER_MAGICAL);
            pushEffect(shared_1.StatusEffectType.BARRIER_MAGICAL, 0, { barrierMagical: true }, { barrierType: 'magical' });
        }
        if (bt.elementalAbsorption) {
            pushEffect(shared_1.StatusEffectType.BUFF_GENERIC, 0, { elementalAbsorption: bt.elementalAbsorption });
        }
        if (bt.devotion && casterSession) {
            target.statusEffects = target.statusEffects.filter(e => !(e.skillName === skill.name && e.buffData?.devotionLink));
            pushEffect(shared_1.StatusEffectType.BUFF_GENERIC, 0, { devotionLink: { partnerId: sourceId } });
        }
        if (bt.misdirection) {
            target.statusEffects = target.statusEffects.filter(e => !(e.skillName === skill.name && e.buffData?.misdirection));
            pushEffect(shared_1.StatusEffectType.BUFF_GENERIC, 0, { misdirection: true });
        }
        if (bt.extraHit) {
            target.statusEffects = target.statusEffects.filter(e => !(e.skillName === skill.name && e.buffData?.extraHit));
            pushEffect(shared_1.StatusEffectType.BUFF_GENERIC, 0, { extraHit: true });
        }
        if (bt.spellInterruptResist) {
            pushEffect(shared_1.StatusEffectType.BUFF_SPELL_INTERRUPT_RESIST, bt.spellInterruptResist, { spellInterruptResistPercent: bt.spellInterruptResist });
        }
        if (bt.debuffResist) {
            pushEffect(shared_1.StatusEffectType.BUFF_DEBUFF_RESIST, bt.debuffResist, { debuffResistPercent: bt.debuffResist });
        }
        if (bt.blockingStance) {
            target.statusEffects = target.statusEffects.filter(e => e.type !== shared_1.StatusEffectType.BUFF_BLOCKING_STANCE);
            const clearOnBlock = [shared_1.StatusEffectType.STUN, shared_1.StatusEffectType.SLEEP, shared_1.StatusEffectType.KNOCKDOWN];
            target.statusEffects = target.statusEffects.filter(e => !clearOnBlock.includes(e.type));
            pushEffect(shared_1.StatusEffectType.BUFF_BLOCKING_STANCE, 0, { blockingStance: true, blockingRange: bt.blockingRange || 6 });
        }
        if (bt.defensiveMarch) {
            target.statusEffects = target.statusEffects.filter(e => e.type !== shared_1.StatusEffectType.BUFF_BLOCKING_STANCE);
            pushEffect(shared_1.StatusEffectType.BUFF_BLOCKING_STANCE, 0, { blockingStance: true, blockingRange: bt.blockingRange || 7, defensiveMarch: true });
        }
        if (bt.shieldCharge) {
            pushEffect(shared_1.StatusEffectType.BUFF_MOVE_SPEED, 2, { moveSpeedFlat: 2, shieldCharge: true });
        }
        if (bt.blockChance) {
            pushEffect(shared_1.StatusEffectType.BUFF_BLOCK_CHANCE, bt.blockChance, { blockChancePercent: bt.blockChance });
        }
        if (bt.consumableOnAttack) {
            pushEffect(shared_1.StatusEffectType.BUFF_CONSUMABLE_ON_ATTACK, bt.accuracy || 50, { consumableOnAttack: true, accuracyBonusFlat: bt.accuracy || 50 });
        }
        if (bt.dodgeReduction) {
            pushEffect(shared_1.StatusEffectType.BUFF_GENERIC, 0, { dodgeReductionFlat: bt.dodgeReduction });
        }
        if (bt.healingOverTime) {
            const hot = bt.healingOverTime;
            const hotConfig = casterSession?.jobId ? shared_1.HOT_JOB_CONFIG[casterSession.jobId] : undefined;
            const profStat = hotConfig?.proficiencyStat ?? hot.proficiencyStat;
            const profCoef = hotConfig?.coef ?? 0.5;
            const prof = profStat ? (casterSession?.skillAdeptness?.[profStat] || 0) : 0;
            const spi = (casterSession?.statPoints?.SPI || 0) + (casterSession?.baseStats?.SPI || 0);
            const hpPerTick = Math.floor(hot.base + spi * hot.spiScale + prof * profCoef);
            pushEffect(shared_1.StatusEffectType.BUFF_GENERIC, 0, { healOverTime: { hpPerTick, tickInterval: 3000 } });
        }
        if (bt.partyHeal) {
            const healAmount = bt.partyHeal;
            const spi = (casterSession?.statPoints?.SPI || 0) + (casterSession?.baseStats?.SPI || 0);
            const finalHeal = Math.floor(healAmount + spi * 0.5);
            target.stats.health = Math.min(target.stats.maxHealth, target.stats.health + finalHeal);
        }
        if (bt.dispelDebuff) {
            target.statusEffects = target.statusEffects.filter(e => !e.debuffCategory);
        }
        if (bt.dispelBuff) {
            target.statusEffects = target.statusEffects.filter(e => !e.buffData);
        }
        if (bt.attackPowerMultiplierProficiency) {
            const prof = bt.attackPowerMultiplierProficiency;
            const profValue = casterSession?.skillAdeptness?.[prof.proficiencyStat] || 0;
            const multiplier = 1 + profValue * prof.perProficiency;
            pushEffect(shared_1.StatusEffectType.BUFF_ATTACK, multiplier);
        }
        if (bt.cooldownReduction) {
            pushEffect(shared_1.StatusEffectType.BUFF_GENERIC, 0, { cooldownReductionPercent: bt.cooldownReduction });
        }
        if (bt.magicalDamageBonus) {
            pushEffect(shared_1.StatusEffectType.BUFF_GENERIC, 0, { magicalDamageBonusPercent: bt.magicalDamageBonus });
        }
        if (bt.auraDamageIncrease) {
            pushEffect(shared_1.StatusEffectType.BUFF_GENERIC, 0, { auraDamageIncreasePercent: bt.auraDamageIncrease });
        }
        if (bt.songType) {
            const songMap = {
                green: shared_1.StatusEffectType.SONG_GREEN,
                blue: shared_1.StatusEffectType.SONG_BLUE,
                yellow: shared_1.StatusEffectType.SONG_YELLOW,
                red: shared_1.StatusEffectType.SONG_RED,
            };
            const songEffectType = songMap[bt.songType];
            if (songEffectType) {
                target.statusEffects = target.statusEffects.filter(e => ![shared_1.StatusEffectType.SONG_GREEN, shared_1.StatusEffectType.SONG_BLUE, shared_1.StatusEffectType.SONG_YELLOW, shared_1.StatusEffectType.SONG_RED].includes(e.type));
                effects.length = 0;
                pushEffect(songEffectType, 0, { songType: bt.songType, songRadius: 3 });
                effects[effects.length - 1].duration = 999999999;
                effects[effects.length - 1].lastPulseAt = 0;
                target.statusEffects.push(...effects);
                return;
            }
        }
        if (bt.delayExplosion) {
            const delayMs = bt.delayExplosion.minSeconds * 1000 + Math.random() * (bt.delayExplosion.maxSeconds - bt.delayExplosion.minSeconds) * 1000;
            pushEffect(shared_1.StatusEffectType.BUFF_GENERIC, 0, { delayExplosion: { minMs: delayMs, maxMs: delayMs } });
            if (effects.length > 0) {
                const lastEffect = effects[effects.length - 1];
                lastEffect.delayExplosionAt = Date.now() + delayMs;
            }
        }
        if (bt.statTieredValues) {
            const cfg = bt.statTieredValues;
            const caster = casterSession || target;
            const statKey = cfg.stat;
            const totalStat = (caster.baseStats?.[statKey] || 0) + (caster.statPoints?.[statKey] || 0);
            const prof = cfg.proficiencyStat
                ? (caster.skillAdeptness?.[cfg.proficiencyStat] || 0)
                : 0;
            const firstTier = cfg.tiers[0];
            if (firstTier?.profTiers?.[0]) {
                const resultKeys = Object.keys(firstTier.profTiers[0].values);
                for (const resultKey of resultKeys) {
                    const result = (0, shared_1.resolveStatTieredValue)(cfg, totalStat, prof, resultKey);
                    if (result != null) {
                        if (resultKey === 'dodgeChance') {
                            pushEffect(shared_1.StatusEffectType.BUFF_DODGE, result);
                        }
                        else if (resultKey === 'def') {
                            pushEffect(shared_1.StatusEffectType.BUFF_DEFENSE, 0, { flatDefense: result });
                        }
                        else if (resultKey === 'accuracy') {
                            pushEffect(shared_1.StatusEffectType.BUFF_ACCURACY, result);
                        }
                    }
                }
            }
        }
        if (effects.length === 0)
            return;
        target.statusEffects.push(...effects);
    }
    updateCooldowns(session) {
        if (!session.skillCooldowns)
            return;
        const now = Date.now();
        session.skillCooldowns = session.skillCooldowns.filter(c => now < c.readyAt);
    }
    checkCasting(session) {
        if (!session.activeCast)
            return null;
        const elapsed = Date.now() - session.activeCast.startedAt;
        if (elapsed >= session.activeCast.castTime) {
            return {
                completed: true,
                skillName: session.activeCast.skillName,
                targetId: session.activeCast.targetId,
                aoePosition: session.activeCast.aoePosition
            };
        }
        return null;
    }
    findSkillDefinition(skillName) {
        if (CLASS_SPECIFIC_SKILL_LOOKUP.has(skillName)) {
            return CLASS_SPECIFIC_SKILL_LOOKUP.get(skillName);
        }
        return CLASS_SKILL_LOOKUP.get(skillName) || null;
    }
    getSkillType(skillName) {
        const skill = this.findSkillDefinition(skillName);
        if (!skill)
            return undefined;
        return skill.skillType ?? this.inferSkillType(skill);
    }
    getSubCategoryForSkill(skillName) {
        return SKILL_TO_SUBCATEGORY[skillName] || null;
    }
    getAvailableSkills(session) {
        const available = [];
        const proficiencies = session.skillProficiencies || {};
        for (const category of Object.values(shared_2.CLASS_SKILL_DATA)) {
            for (const subSkill of category.skills) {
                const subPoints = proficiencies[subSkill.name] || 0;
                for (const [name, def] of Object.entries(subSkill.skills)) {
                    if ((0, shared_1.isPassiveSkill)(def))
                        continue;
                    if (typeof def.reqPoints === 'number') {
                        if (subPoints >= def.reqPoints) {
                            available.push(name);
                        }
                    }
                    else if (Array.isArray(def.reqPoints)) {
                        if ((0, shared_1.meetsRequirements)(def.reqPoints, (skillName) => proficiencies[skillName] || 0)) {
                            available.push(name);
                        }
                    }
                }
            }
        }
        const jobSkills = (0, shared_3.getClassSpecificSkillsForJob)(session.jobId, session.baseClass);
        for (const [name, def] of Object.entries(jobSkills)) {
            const skillDef = def;
            if ((0, shared_1.isPassiveSkill)(skillDef))
                continue;
            if (skillDef.reqLevel && skillDef.reqLevel > session.stats.level)
                continue;
            if (skillDef.reqPoints && typeof skillDef.reqPoints === 'number')
                continue;
            if (skillDef.reqPoints && Array.isArray(skillDef.reqPoints)) {
                if (!(0, shared_1.meetsRequirements)(skillDef.reqPoints, (skillName) => proficiencies[skillName] || 0))
                    continue;
            }
            available.push(name);
        }
        return available;
    }
    tickStatusEffects(session, now) {
        let damage = 0;
        let mpDamage = 0;
        let healed = 0;
        let mpRestored = 0;
        const expired = [];
        if (!session.statusEffects)
            return { damage: 0, mpDamage: 0, healed: 0, mpRestored: 0, expired: [] };
        for (const effect of session.statusEffects) {
            if (effect.songProximityBuff && effect.lastInRangeAt && now - effect.lastInRangeAt > 5000) {
                expired.push(effect);
                continue;
            }
            if (now - effect.appliedAt >= effect.duration) {
                expired.push(effect);
                continue;
            }
            if (effect.tickInterval > 0 && now - effect.lastTickAt >= effect.tickInterval) {
                effect.lastTickAt = now;
                if (effect.dotHPPercent && effect.dotHPPercent > 0) {
                    damage += Math.floor(session.stats.maxHealth * effect.dotHPPercent);
                }
                else if (effect.potency > 0) {
                    damage += effect.potency;
                }
                if (effect.dotMpDrain) {
                    mpDamage += effect.dotMpDrain;
                }
            }
            if (effect.buffData?.healOverTime && now - effect.lastTickAt >= effect.buffData.healOverTime.tickInterval) {
                effect.lastTickAt = now;
                healed += effect.buffData.healOverTime.hpPerTick;
            }
            if (effect.buffData?.mpRestorePerTick && now - effect.lastTickAt >= effect.buffData.mpRestorePerTick.tickInterval) {
                effect.lastTickAt = now;
                mpRestored += effect.buffData.mpRestorePerTick.mpPerTick;
            }
            if (effect.type === shared_1.StatusEffectType.INVISIBLE && effect.buffData?.invisible && effect.tickInterval > 0 && now - effect.lastTickAt >= effect.tickInterval) {
                effect.lastTickAt = now;
                const mpDrain = effect.buffData.invisible.mpCostPerSec;
                mpDamage += mpDrain;
                if (effect.buffData.invisible.stationaryOnly) {
                    if (session.stats.mana - mpDamage <= 0) {
                        expired.push(effect);
                    }
                }
            }
            const songTypes = shared_1.SONG_TYPES;
            if (songTypes.includes(effect.type) && effect.tickInterval > 0 && now - effect.lastTickAt >= effect.tickInterval) {
                effect.lastTickAt = now;
                if (effect.type === shared_1.StatusEffectType.SONG_RED) {
                    const basePower = 2;
                    const totalINT = (session.statPoints.INT || 0) + (session.baseStats?.INT || 0);
                    const totalSPI = (session.statPoints.SPI || 0) + (session.baseStats?.SPI || 0);
                    damage += Math.floor(basePower * (totalINT + totalSPI * 0.3));
                    mpDamage += Math.floor(basePower * (totalINT + totalSPI * 0.3) * 0.3);
                }
            }
        }
        const expiredSet = new Set(expired);
        session.statusEffects = session.statusEffects.filter(e => !expiredSet.has(e));
        return { damage, mpDamage, healed, mpRestored, expired };
    }
}
exports.SkillSystem = SkillSystem;
