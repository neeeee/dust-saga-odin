import {
  PlayerSession, SkillDefinition, SkillCooldownEntry, ActiveCast,
  isPassiveSkill, meetsRequirements, getRequiredProficiency,
  COMBAT_CONFIG, StatusEffect, StatusEffectType, STATUS_EFFECT_DEFS,
  SKILL_TARGET_RULES, SkillTargetType,
  BuffData, resolveStatTieredValue, SONG_TYPES,
  getEffectiveStats,
  recalculateCategoryTotals, calculateProficiencyGain, ProficiencyGainResult,
  DebuffEffectTable,
  calculateWeaponElementalDamage,
  computeElementalDamageLine,
  getMagicEnhancementBoost,
  calculateDodge,
  calculateAccuracy as calcSharedAccuracy,
  calculateHitChance,
  safeFormulaEval,
  getMinAdeptness, getDesignJobId, SUB_CATEGORY_TO_CATEGORY,
  getEffectiveProficiencies,
  HOT_JOB_CONFIG,
  SkillType, OnHitEffect, HealingEffect, getSkillTargetType,
  AOETargetMode,
} from '@dust-saga/shared';
import { CLASS_SKILL_DATA, CATEGORY_LEVEL_SKILLS, CATEGORY_ID_TO_KEY } from '@dust-saga/shared';
import { CLASS_SPECIFIC_SKILLS, getClassSpecificSkillsForJob } from '@dust-saga/shared';
import { findSkillDefinition as sharedFindSkillDefinition } from '@dust-saga/shared';
import type { ItemSystem } from '../../../systems/ItemSystem';
import { getObeliskBuffForWeapon } from '../../combat/obeliskBuff';

const CLASS_SKILL_LOOKUP: Map<string, SkillDefinition> = ((): Map<string, SkillDefinition> => {
  const lookup = new Map<string, SkillDefinition>();
  for (const category of Object.values(CLASS_SKILL_DATA)) {
    for (const subSkill of category.skills) {
      for (const [name, def] of Object.entries(subSkill.skills)) {
        lookup.set(name, { ...def, name });
      }
    }
  }
  for (const skills of Object.values(CATEGORY_LEVEL_SKILLS)) {
    for (const [name, def] of Object.entries(skills)) {
      lookup.set(name, { ...def, name });
    }
  }
  return lookup;
})();

const CATEGORY_SKILL_TO_KEY: Record<string, string> = {};
for (const [catId, skills] of Object.entries(CATEGORY_LEVEL_SKILLS)) {
  const catKey = CATEGORY_ID_TO_KEY[Number(catId) as keyof typeof CATEGORY_ID_TO_KEY];
  for (const skillName of Object.keys(skills)) {
    CATEGORY_SKILL_TO_KEY[skillName] = catKey;
  }
}

const CLASS_SPECIFIC_SKILL_LOOKUP: Map<string, SkillDefinition> = ((): Map<string, SkillDefinition> => {
  const lookup = new Map<string, SkillDefinition>();
  for (const jobSkills of Object.values(CLASS_SPECIFIC_SKILLS)) {
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

const SKILL_TO_SUBCATEGORY: Record<string, string> = {};
for (const category of Object.values(CLASS_SKILL_DATA)) {
  for (const subSkill of category.skills) {
    for (const skillName of Object.keys(subSkill.skills)) {
      SKILL_TO_SUBCATEGORY[skillName] = subSkill.name;
      }
    }
  }

export interface TargetStats {
  defense: number;
  magicDefense: number;
  health: number;
  level: number;
  dodge: number;
  damageTakenMultiplier?: number;
  physicalDamageReduction?: number;
  fireResist?: number;
  iceResist?: number;
  lightningResist?: number;
  darkResist?: number;
  holyResist?: number;
  poisonResist?: number;
}

export interface SkillUseResult {
  success: boolean;
  damage?: number;
  physicalDamage?: number;
  physicalElementalDamage?: Array<{ element: string; damage: number }>;
  healing?: number;
  mpRestored?: number;
  mpDamage?: number;
  maxHpIncrease?: number;
  isCritical?: boolean;
  missed?: boolean;
  damageType?: 'physical' | 'magical';
  statusEffects?: StatusEffect[];
  revived?: boolean;
  error?: string;
  debugCalc?: string;
  elementalDamage?: Array<{ element: string; damage: number }>;
  hits?: Array<{
    damage: number;
    isCritical: boolean;
    missed?: boolean;
    elementalDamage?: Array<{ element: string; damage: number }>;
  }>;
  createdItems?: Array<{ itemId: string; quantity: number; consumeItems?: Array<{ itemId: string; quantity: number }> }>;
  sacrificeHeal?: boolean;
  targetId?: string;
  dispelBuff?: boolean;
  dispelDebuff?: boolean;
  revealInvisible?: boolean;
  fear?: boolean;
  provoked?: boolean;
  summonObject?: { objectType: string; duration: number; hp?: number; defense?: number; aoeDamage?: number };
  banishObject?: boolean;
  banishRadius?: number;
  blockOnly?: boolean;
  element?: string;
  songToggledOff?: boolean;
  defensiveMarchToggledOff?: boolean;
  guardianToggledOff?: boolean;
  guardianApplied?: string;
  guardianRemovedTarget?: string;
  manaSwap?: boolean;
  soulSwap?: boolean;
}

type DamageType = 'physical' | 'magical';

export class SkillSystem {
  itemSys!: ItemSystem;
  private gcd: number = 1000;
  private globalCooldowns: Map<string, number> = new Map();
  lastBuffDebug: string | undefined;
  lastProficiencyGain: ProficiencyGainResult | undefined;
  lastCooldownDebug: { skillName: string; totalINT: number; cooldownReduction: number; baseCd: number; effective: number } | undefined;

  private createStatusEffect(
    type: StatusEffectType,
    potency: number,
    sourceId: string,
    targetId: string,
    overrides?: Partial<StatusEffect>
  ): StatusEffect | null {
    const def = STATUS_EFFECT_DEFS[type];
    if (!def) return null;
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

  gainProficiency(session: PlayerSession, skillName: string): ProficiencyGainResult | null {
    const subCategory = SKILL_TO_SUBCATEGORY[skillName];
    if (!subCategory) return null;

    const skill = this.findSkillDefinition(skillName);
    if (!skill) return null;

    const cap = session.skillProficiencies[subCategory] || 0;
    const current = session.skillAdeptness[subCategory] || 0;
    const hasCastTime = (skill.castTime || 0) > 0.1;

    const result = calculateProficiencyGain(current, cap, hasCastTime);
    if (!result) return null;

    session.skillAdeptness[subCategory] = result.newAdeptness;
    recalculateCategoryTotals(session.skillAdeptness);

    result.subCategory = subCategory;
    this.lastProficiencyGain = result;
    return result;
  }

  private getWeaponElement(session: PlayerSession): string | undefined {
    const weapon = session.equipment?.weapon;
    if (!weapon) return undefined;
    const enh = weapon.stats?.enhancementElement;
    if (enh) {
      return enh.startsWith('magic_') ? enh.slice(6) : enh;
    }
    return weapon.stats?.weaponElement || undefined;
  }

  private inferSkillType(skill: SkillDefinition): SkillType | undefined {
    if (skill.isPassive) return SkillType.PASSIVE;
    if (skill.isRevive) return SkillType.REVIVE;
    if (skill.isSong) return SkillType.SONG;
    if (skill.sacrificeHeal) return SkillType.SACRIFICE_HEAL;
    if (skill.mpDamage) return SkillType.MP_DAMAGE;
    const isMagical = skill.damageType === 'magical'
      || (skill.damageType !== 'physical' && skill.damageSubType && ['fire','ice','lightning','dark','holy','poison'].includes(skill.damageSubType as string));
    if (skill.basePower && skill.basePower > 0) {
      return isMagical ? SkillType.DAMAGE_MAGICAL : SkillType.DAMAGE_PHYSICAL;
    }
    if (skill.isDebuff || skill.debuffEffectTable) return SkillType.DEBUFF;
    if (skill.invisible) return SkillType.INVISIBILITY;
    if (skill.barrier) return SkillType.BARRIER;
    if (skill.healing) return SkillType.HEAL;
    if (skill.isBuff || skill.buffEffectTable) return SkillType.BUFF;
    if (skill.createItems) return SkillType.CRAFT;
    if (skill.summonObject) return SkillType.SUMMON;
    return undefined;
  }

  private getDamageType(st: SkillType | undefined, skill: SkillDefinition): DamageType {
    if (st === SkillType.DAMAGE_MAGICAL || st === SkillType.MP_DAMAGE) return 'magical';
    if (st === SkillType.DAMAGE_PHYSICAL || st === SkillType.DRAIN_LIFE) return 'physical';
    return skill.damageType === 'magical' ? 'magical' : 'physical';
  }

  canUseSkill(
    session: PlayerSession,
    skillName: string,
    targetId: string | null
  ): { canUse: boolean; error?: string } {
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

    const cooldown = session.skillCooldowns?.find(
      c => c.skillName === skillName && now < c.readyAt
    );
    if (cooldown) {
      return { canUse: false, error: 'cooldown' };
    }

    const skill = this.findSkillDefinition(skillName);
    if (!skill) {
      return { canUse: false, error: 'not_found' };
    }

    if (isPassiveSkill(skill)) {
      return { canUse: false, error: 'passive' };
    }

    const proficiencies = session.skillProficiencies || {};
    const subCategory = SKILL_TO_SUBCATEGORY[skillName];
    const designJobId = getDesignJobId(session.jobId || 'warrior');
    const effectiveProficiencies = getEffectiveProficiencies(proficiencies, designJobId);

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
        } else {
          const subPoints = subCategory ? (effectiveProficiencies[subCategory] || 0) : 0;
          if (subPoints < skill.reqPoints) {
            return { canUse: false, error: 'insufficient_proficiency' };
          }
        }
      } else if (Array.isArray(skill.reqPoints)) {
        if (!meetsRequirements(skill.reqPoints, (name: string) => effectiveProficiencies[name] || 0)) {
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
      const hasBlockingStance = session.statusEffects?.some(e =>
        e.type === StatusEffectType.BUFF_BLOCKING_STANCE || e.buffData?.blockingStance || e.buffData?.defensiveMarch
      );
      if (!hasBlockingStance) {
        return { canUse: false, error: 'not_blocking' };
      }
    }

    const isBlockStancing = session.statusEffects?.some(e =>
      e.type === StatusEffectType.BUFF_BLOCKING_STANCE && e.buffData?.blockingStance
    );
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
      const weapon = session.equipment?.weapon as any;
      if (!weapon) {
        return { canUse: false, error: 'wrong_weapon' };
      }
      const weaponDef = this.itemSys.getItemDefinition(weapon.itemId);
      if (!weaponDef?.weaponType || !skill.requiredWeaponType.includes(weaponDef.weaponType)) {
        return { canUse: false, error: 'wrong_weapon' };
      }
    }

    if (skill.negateFieldSpells || skill.debuffEffectTable?.preventFieldSpells) {
      const hasPrevent = session.statusEffects?.some(e => e.type === StatusEffectType.PREVENT_FIELD_SPELLS);
      if (hasPrevent) {
        return { canUse: false, error: 'field_blocked' };
      }
    }

    if (session.statusEffects?.some(e => e.type === StatusEffectType.SILENCE && skill.mpCost > 0)) {
      return { canUse: false, error: 'silenced' };
    }

    if (session.statusEffects?.some(e => e.type === StatusEffectType.BURN) && skill.damageType === 'physical' && skill.basePower && skill.basePower > 0) {
      return { canUse: false, error: 'burn' };
    }

    if (session.statusEffects?.some(e => e.disablePhysicalAttacks)) {
      const isPhysicalDamage = skill.damageType === 'physical' && skill.basePower && skill.basePower > 0;
      if (isPhysicalDamage) {
        return { canUse: false, error: 'disabled' };
      }
    }

    const inferredType = skill.skillType ?? this.inferSkillType(skill);
    const isSinging = session.statusEffects?.some(e =>
      e.type === StatusEffectType.SONG_GREEN ||
      e.type === StatusEffectType.SONG_BLUE ||
      e.type === StatusEffectType.SONG_YELLOW ||
      e.type === StatusEffectType.SONG_RED
    );
    if (isSinging && inferredType !== SkillType.SONG) {
      return { canUse: false, error: 'singing' };
    }

    if (session.statusEffects?.some(e =>
      e.type === StatusEffectType.STUN ||
      e.type === StatusEffectType.SLEEP ||
      e.type === StatusEffectType.FREEZE
    )) {
      return { canUse: false, error: 'cc' };
    }

    if (session.currentNpcId) {
      return { canUse: false, error: 'busy' };
    }

    let targetType = getSkillTargetType(skill) || SKILL_TARGET_RULES[skillName];

    if (!targetType) {
      const isGroundTargeted = skill.isAOE && skill.aoeTargetMode === AOETargetMode.GROUND_TARGETED;
      if (!isGroundTargeted && inferredType) {
        const typesRequiringTarget = new Set([
          SkillType.DAMAGE_PHYSICAL, SkillType.DAMAGE_MAGICAL,
          SkillType.DEBUFF, SkillType.DRAIN_LIFE, SkillType.MP_DAMAGE,
          SkillType.DISPEL, SkillType.FEAR, SkillType.PROVOKE, SkillType.KNOCKBACK,
        ]);
        if (typesRequiringTarget.has(inferredType)) {
          targetType = SkillTargetType.OTHER_ONLY;
        }
      }
    }

    if (targetType) {
      if (targetType === SkillTargetType.OTHER_ONLY) {
        if (!targetId) {
          return { canUse: false, error: 'no_target' };
        }
        if (targetId === session.characterId) {
          return { canUse: false, error: 'no_self_target' };
        }
      } else if (targetType !== SkillTargetType.SELF && targetType !== SkillTargetType.SELF_OR_TARGET) {
        if (targetId === session.characterId) {
          return { canUse: false, error: 'no_self_target' };
        }
      }
    }

    return { canUse: true };
  }

  beginCast(
    session: PlayerSession,
    skillName: string,
    targetId: string | null,
    aoePosition?: { x: number; y: number; z: number }
  ): { started: boolean; castTime: number } {
    const skill = this.findSkillDefinition(skillName);
    if (!skill) return { started: false, castTime: 0 };

    const baseCastTime = skill.castTime * 1000;
    if (baseCastTime <= 0) {
      return { started: true, castTime: 0 };
    }

    const castSpd = session.stats.castSpeed || 100;

    const effective = session.effectiveStats ?? getEffectiveStats(
      session.stats,
      session.statPoints,
      session.statusEffects || []
    );
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

  executeSkill(
    session: PlayerSession,
    skillName: string,
    targetId: string | null,
    getTargetStats: (id: string) => TargetStats | null
  ): SkillUseResult {
    const skill = this.findSkillDefinition(skillName);
    if (!skill) return { success: false, error: 'not_found' };
    const st = skill.skillType ?? this.inferSkillType(skill);

    if (st === SkillType.SONG) {
      const songMap: Record<string, StatusEffectType> = {
        green: StatusEffectType.SONG_GREEN,
        blue: StatusEffectType.SONG_BLUE,
        yellow: StatusEffectType.SONG_YELLOW,
        red: StatusEffectType.SONG_RED,
      };
      const songType = skill.buffEffectTable?.songType as string | undefined;
      const songEffectType = songType ? songMap[songType] : undefined;
      if (songEffectType && session.statusEffects?.some(e => e.type === songEffectType)) {
        session.statusEffects = session.statusEffects.filter(e => e.type !== songEffectType && e.skillName !== skill.name);
        session.activeCast = null;
        return { success: true, songToggledOff: true };
      }
    }

    session.stats.mana -= skill.mpCost;

    const now = Date.now();
    if (!session.skillCooldowns) session.skillCooldowns = [];
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

    if (st === SkillType.REVIVE && targetId) {
      return { success: true, revived: true };
    }

    if (st === SkillType.PROVOKE) {
      return { success: true, provoked: true, targetId: targetId || undefined };
    }

    if (st === SkillType.DEBUFF || st === SkillType.FEAR || st === SkillType.DISPEL) {
      if (skill.debuffEffectTable) {
        const debuffEffects = this.buildDebuffEffects(session, skill);
        return { success: true, statusEffects: debuffEffects.length > 0 ? debuffEffects : undefined };
      }
      if (st === SkillType.FEAR) {
        return { success: true, fear: true };
      }
      if (st === SkillType.DISPEL) {
        return { success: true, dispelBuff: skill.dispelBuff, dispelDebuff: skill.dispelDebuff };
      }
      if (skill.onHitEffects && skill.onHitEffects.length > 0) {
        const statusEffects = this.buildStatusEffects(session, skill, 0);
        return { success: true, statusEffects: statusEffects.length > 0 ? statusEffects : undefined };
      }
      return { success: true };
    }

    if (st === SkillType.CRAFT && skill.createItems && skill.createItems.length > 0) {
      return { success: true, createdItems: skill.createItems };
    }

    if (st === SkillType.SACRIFICE_HEAL && targetId) {
      return { success: true, sacrificeHeal: true, targetId };
    }

    if (st === SkillType.MP_DAMAGE && targetId) {
      const basePower = skill.basePower ?? 1;
      const mpTotalINT = (session.statPoints.INT || 0) + (session.baseStats?.INT || 0);
      const mpTotalSPI = (session.statPoints.SPI || 0) + (session.baseStats?.SPI || 0);
      const mpDamageAmount = Math.floor(basePower * (mpTotalINT + mpTotalSPI * 0.3) * 0.5);
      return { success: true, mpDamage: mpDamageAmount, damageType: 'magical' };
    }

    const isBuffLike = st === SkillType.BUFF || st === SkillType.SONG
      || st === SkillType.HP_BUFF || st === SkillType.MP_RESTORE
      || st === SkillType.HEAL_OVER_TIME
      || st === SkillType.INVISIBILITY || st === SkillType.BARRIER;
    if ((isBuffLike && skill.duration > 0) || (skill.buffEffectTable && skill.duration === 0)) {
      if (skill.buffEffectTable?.defensiveMarch) {
        const existing = session.statusEffects?.find(e => e.type === StatusEffectType.BUFF_BLOCKING_STANCE && e.buffData?.defensiveMarch && e.skillName === skillName);
        if (existing) {
          session.statusEffects = session.statusEffects.filter(e => e !== existing);
          return { success: true, defensiveMarchToggledOff: true };
        }
      }

      if (skill.buffEffectTable?.damageRedirect && targetId) {
        const existing = session.statusEffects?.find(e => e.type === StatusEffectType.BUFF_DAMAGE_REDIRECT && e.skillName === skillName);
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

    if (st === SkillType.MP_RESTORE) {
      const mpAmount = this.calculateMpRegen(session, skill);
      session.stats.mana = Math.min(session.stats.maxMana, session.stats.mana + mpAmount);
      return { success: true, mpRestored: mpAmount };
    }

    if (st === SkillType.HEAL || st === SkillType.HEAL_OVER_TIME || st === SkillType.PARTY_HEAL) {
      const healAmount = this.calculateHealing(session, skill);
      return { success: true, healing: healAmount };
    }

    if (st === SkillType.HP_BUFF && (!targetId || targetId === session.characterId)) {
      const hpIncrease = this.calculateMaxHpBuff(session, skill);
      const healthRatio = session.stats.maxHealth > 0 ? session.stats.health / session.stats.maxHealth : 1;
      session.stats.maxHealth += hpIncrease;
      session.stats.health = Math.min(session.stats.maxHealth, Math.floor(session.stats.maxHealth * healthRatio) + hpIncrease);
      return { success: true, maxHpIncrease: hpIncrease, healing: hpIncrease };
    }

    if ((st === SkillType.DAMAGE_PHYSICAL || st === SkillType.DAMAGE_MAGICAL) && targetId) {
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

    if (st === SkillType.DRAIN_LIFE && targetId) {
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

    if (st === SkillType.SUMMON && skill.summonObject) {
      let element: string | undefined;
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

  private applyDualPhysical(
    session: PlayerSession,
    skill: SkillDefinition,
    target: TargetStats,
    result: SkillUseResult
  ): void {
    if (!skill.dualPhysical) return;
    const physSkill: SkillDefinition = {
      ...skill,
      basePower: skill.dualPhysical.basePower,
      damageType: 'physical' as SkillDefinition['damageType'],
      damageSubType: (skill.dualPhysical.damageSubType ?? 'slash') as SkillDefinition['damageSubType'],
      scalingStat: skill.dualPhysical.scalingStat,
      debuffEffectTable: undefined,
      hasDebuff: false,
    };
    const physResult = this.calculateSkillDamageInternal(session, physSkill, target, 'physical');
    result.physicalDamage = physResult.damage;
    result.physicalElementalDamage = physResult.elementalDamage;
  }

  calculateAOEDamage(
    session: PlayerSession,
    skillName: string,
    targetId: string,
    getTargetStats: (id: string) => TargetStats | null
  ): SkillUseResult {
    const skill = this.findSkillDefinition(skillName);
    if (!skill) return { success: false, error: 'not_found' };

    const st = skill.skillType ?? this.inferSkillType(skill);
    const isDamage = st === SkillType.DAMAGE_PHYSICAL || st === SkillType.DAMAGE_MAGICAL
      || st === SkillType.DRAIN_LIFE || st === SkillType.MP_DAMAGE;
    if (!isDamage) return { success: true };

    const target = getTargetStats(targetId);
    if (!target) return { success: true, missed: true };

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

  private calculateSkillDamage(
    session: PlayerSession,
    skill: SkillDefinition,
    target: TargetStats,
    damageType: 'physical' | 'magical'
  ): SkillUseResult {
    return this.calculateSkillDamageInternal(session, skill, target, damageType);
  }

  private calculateSkillDamageInternal(
    session: PlayerSession,
    skill: SkillDefinition,
    target: TargetStats,
    damageType: 'physical' | 'magical'
  ): SkillUseResult {
    const isMagical = damageType === 'magical';
    const numHits = skill.baseHits || 1;
    const hitChance = this.calculateAccuracy(session, target);
    const effectiveStats = session.effectiveStats ?? getEffectiveStats(session.stats, session.statPoints, session.statusEffects || []);

    const basePower = skill.basePower ?? 1;
    const baseStats = session.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };

    let primaryStat: number;
    if (isMagical) {
      primaryStat = session.stats.magicAttack || ((session.statPoints.INT || 0) + (baseStats.INT || 0));
    } else if (skill.scalingStat) {
      const stat = skill.scalingStat;
      primaryStat = (session.statPoints[stat] || 0) + (baseStats[stat] || 0);
    } else {
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

    const hasBurn = !isMagical && session.statusEffects?.some(e => e.type === StatusEffectType.BURN);
    const hasAttackHalved = !isMagical && session.statusEffects?.some(e => e.attackHalved);
    const effectivePrimaryStat = hasBurn ? Math.floor(primaryStat * 0.5) : hasAttackHalved ? Math.floor(primaryStat * 0.5) : primaryStat;

    const defenseStat = isMagical ? target.magicDefense : target.defense;

    let attackMultiplier = 1;
    const attackBuff = session.statusEffects?.find(e => e.type === StatusEffectType.BUFF_ATTACK);
    if (attackBuff && !isMagical) {
      attackMultiplier = attackBuff.potency;
    }

    const magicalAidBuff = isMagical ? session.statusEffects?.find(e => e.buffData?.magicalAid) : null;
    if (magicalAidBuff) {
      attackMultiplier *= 1.2;
    }

    const baseDamage = skill.damageVsLowDefense
      ? Math.floor(
          basePower * (effectivePrimaryStat + secondaryStat * 0.3) * attackMultiplier
          + defenseStat * 0.5
        )
      : Math.floor(
          basePower * (effectivePrimaryStat + secondaryStat * 0.3) * attackMultiplier
          - defenseStat * 0.5
        );

    let elementalResistMultiplier = 1;
    if (isMagical && skill.damageSubType) {
      const resistMap: Record<string, number | undefined> = {
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
      const obelisk = getObeliskBuffForWeapon(this.itemSys, session.equipment?.weapon);
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
    const critChance = COMBAT_CONFIG.CRITICAL_CHANCE + totalDex * 0.002;

    const levelDiff = session.stats.level - target.level;
    let levelMultiplier = 1;
    if (levelDiff > 0) {
      levelMultiplier = 1 + levelDiff * 0.03;
    } else if (levelDiff < 0) {
      const penalty = 1 - 0.5 * (1 - Math.exp(levelDiff * 0.03));
      levelMultiplier = Math.max(0.25, penalty);
    }

    const totalSPI = (session.statPoints.SPI || 0) + (baseStats.SPI || 0);
    const totalINT = (session.statPoints.INT || 0) + (baseStats.INT || 0);
    const targetResists: Record<string, number | undefined> = {
      fireResist: target.fireResist,
      iceResist: target.iceResist,
      lightningResist: target.lightningResist,
      darkResist: target.darkResist,
      holyResist: target.holyResist,
      poisonResist: target.poisonResist,
    };

    const steps: string[] = [];
    if (isMagical) {
      steps.push(`basePower=${basePower} magicAttack=${primaryStat}(INT=${session.statPoints.INT + baseStats.INT}) SPI=${secondaryStat}`);
    } else {
      steps.push(`basePower=${basePower} STR=${primaryStat}(base${baseStats.STR}+alloc${session.statPoints.STR}) DEX=${secondaryStat}`);
    }
    steps.push(`raw=${basePower}×(${primaryStat}+${secondaryStat}×0.3)×${attackMultiplier}-${defenseStat}×0.5=${baseDamage}`);

    const hits: Array<{ damage: number; isCritical: boolean; missed?: boolean; elementalDamage?: Array<{ element: string; damage: number }> }> = [];
    let totalDamage = 0;
    let anyCritical = false;
    let anyMissed = false;

    for (let h = 0; h < numHits; h++) {
      if (Math.random() > hitChance) {
        hits.push({ damage: 0, isCritical: false, missed: true });
        anyMissed = true;
        if (numHits > 1) steps.push(`hit${h + 1}: miss`);
        continue;
      }

      let damage = baseDamage;

      const weaponEnhElement = (session.equipment?.weapon as any)?.enhancementElement;
      const weaponEnhLevel = (session.equipment?.weapon as any)?.enhancementLevel;
      const magicBoost = getMagicEnhancementBoost(weaponEnhElement, weaponEnhLevel, skill.damageSubType);
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
        damage = Math.floor(damage * COMBAT_CONFIG.CRITICAL_MULTIPLIER);
        anyCritical = true;
      }

      damage = Math.floor(damage * levelMultiplier);

      const varianceRoll = 0.9 + Math.random() * 0.2;
      damage = Math.floor(damage * varianceRoll);
      damage = Math.max(COMBAT_CONFIG.MIN_DAMAGE, damage);

      if (target.damageTakenMultiplier && target.damageTakenMultiplier > 1) {
        damage = Math.floor(damage * target.damageTakenMultiplier);
      }

      const allElemental: Array<{ element: string; damage: number }> = [];

      if (damageType !== 'magical') {
        const skillElement = skill.damageSubType;
        if (skillElement && ['fire', 'ice', 'lightning', 'dark', 'holy', 'poison'].includes(skillElement as string)) {
          const elemPower = skill.elementalPower ?? skill.basePower ?? 1;
          allElemental.push(computeElementalDamageLine(elemPower, totalSPI, totalINT, session.stats.level, skillElement as string, targetResists));
        }
        const skillWeaponDef = this.itemSys.getItemDefinition(session.equipment?.weapon?.itemId);
        const weaponElem = calculateWeaponElementalDamage(
          skillWeaponDef?.stats.weaponElement, skillWeaponDef?.stats.weaponElementPower,
          session.statusEffects || [],
          totalSPI,
          totalINT,
          session.stats.level,
          targetResists,
          (session.equipment?.weapon as any)?.enhancementElement,
          (session.equipment?.weapon as any)?.enhancementLevel,
          effectiveStats.auraDamageMultiplier
        );
        allElemental.push(...weaponElem);
      }

      hits.push({
        damage,
        isCritical: isCrit,
        elementalDamage: allElemental.length > 0 ? allElemental : undefined,
      });

      totalDamage += damage;
      if (numHits === 1) {
        if (isCrit) steps.push(`crit=${damage}`);
      } else {
        steps.push(`hit${h + 1}=${damage}${isCrit ? '(crit)' : ''}`);
      }
    }

    steps.push(`total=${totalDamage}`);

    const statusEffects = this.buildStatusEffects(session, skill, totalDamage);

    const result: SkillUseResult = {
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
    } else if (hits.length > 0 && hits[0].elementalDamage) {
      result.elementalDamage = hits[0].elementalDamage;
    }

    return result;
  }

  private buildStatusEffects(session: PlayerSession, skill: SkillDefinition, damage: number): StatusEffect[] {
    if (!skill.onHitEffects || skill.onHitEffects.length === 0) return [];

    const effects: StatusEffect[] = [];
    const now = Date.now();

    for (const oh of skill.onHitEffects) {
      const chance = oh.chance ?? 1;
      if (Math.random() > chance) continue;

      let potency = oh.potency ?? 0;
      if (typeof potency === 'object' && potency !== null) {
        const base = potency.formula || '0';
        const statName = potency.stat || 'INT';
        const statValue = (session.statPoints[statName as keyof typeof session.statPoints] || 0)
          + (session.baseStats?.[statName as keyof typeof session.baseStats] || 0);
        const vars: Record<string, number> = { ...(potency as Record<string, number>), damage, [statName]: statValue };
        potency = safeFormulaEval(base, vars);
      }

      const effect = this.createStatusEffect(oh.type, potency, session.characterId, '', {
        duration: oh.duration,
      });
      if (effect) effects.push(effect);
    }

    return effects;
  }

  buildDebuffEffects(casterSession: PlayerSession, skill: SkillDefinition): StatusEffect[] {
    const dt = skill.debuffEffectTable!;
    const effects: StatusEffect[] = [];
    const now = Date.now();
    const duration = (skill.debuffDuration || skill.duration || 30) * 1000;
    const category = dt.debuffCategory;

    const addEffect = (type: StatusEffectType, potency: number, extra?: Partial<StatusEffect>) => {
      const def = STATUS_EFFECT_DEFS[type];
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
      let statusType: StatusEffectType;

      switch (dt.dot) {
        case 'poison':
          statusType = StatusEffectType.POISON;
          break;
        case 'severe_poison':
          statusType = StatusEffectType.SEVERE_POISON;
          break;
        case 'bleed':
          statusType = StatusEffectType.BLEED;
          break;
        case 'mp_drain':
          statusType = StatusEffectType.MP_DRAIN;
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

    const DEBUFF_PROPERTY_MAP: Array<{ prop: keyof DebuffEffectTable; effectType: StatusEffectType; extra?: Partial<StatusEffect> }> = [
      { prop: 'attackDown', effectType: StatusEffectType.DEBUFF_DAMAGE_DOWN },
      { prop: 'defenseDown', effectType: StatusEffectType.DEBUFF_DEFENSE_DOWN },
      { prop: 'speedDown', effectType: StatusEffectType.DEBUFF_SPEED_DOWN },
      { prop: 'accuracyDown', effectType: StatusEffectType.DEBUFF_ACCURACY_DOWN },
      { prop: 'dodgeDown', effectType: StatusEffectType.DEBUFF_DODGE_DOWN },
      { prop: 'castSpeedDown', effectType: StatusEffectType.DEBUFF_CAST_SPEED_DOWN },
      { prop: 'damageTakenUp', effectType: StatusEffectType.DEBUFF_DAMAGE_TAKEN_UP, extra: { consumable: dt.consumable || false } },
      { prop: 'moveSpeedDown', effectType: StatusEffectType.SLOW },
      { prop: 'hasFreeze', effectType: StatusEffectType.FREEZE, extra: { duration: (dt.hasFreeze as any)?.duration * 1000 } },
      { prop: 'hasSleep', effectType: StatusEffectType.SLEEP, extra: { duration: (dt.hasSleep as any)?.duration * 1000 } },
      { prop: 'hasStun', effectType: StatusEffectType.STUN, extra: { duration: (dt.hasStun as any)?.duration * 1000 } },
      { prop: 'hasSilence', effectType: StatusEffectType.SILENCE, extra: { duration: (dt.hasSilence as any)?.duration * 1000 } },
      { prop: 'disablePhysicalAttacks', effectType: StatusEffectType.BUFF_GENERIC, extra: { disablePhysicalAttacks: true } },
      { prop: 'attackHalved', effectType: StatusEffectType.BUFF_GENERIC, extra: { attackHalved: true } },
      { prop: 'preventFieldSpells', effectType: StatusEffectType.PREVENT_FIELD_SPELLS },
      { prop: 'preventResurrect', effectType: StatusEffectType.PREVENT_RESSURECT },
      { prop: 'curse', effectType: StatusEffectType.CURSE },
      { prop: 'revealInvisible', effectType: StatusEffectType.BUFF_GENERIC },
    ];

    for (const mapping of DEBUFF_PROPERTY_MAP) {
      const value = dt[mapping.prop];
      if (value === undefined || value === null || value === false) continue;
      let potency = typeof value === 'number' ? value : 0;
      const extra = typeof value === 'object' && value !== null ? mapping.extra : undefined;
      const effect = this.createStatusEffect(mapping.effectType, potency, casterSession.characterId, '', {
        skillName: skill.name,
        debuffCategory: category,
        ...extra,
      });
      if (effect) effects.push(effect);
    }

    if (dt.mpDamage && dt.mpDamageDirect) {
      const effect = this.createStatusEffect(StatusEffectType.MP_DAMAGE_DEBUFF, dt.mpDamage, casterSession.characterId, '', { mpDamageDirect: dt.mpDamage });
      if (effect) effects.push(effect);
    }

    if (dt.removeResistBuffs && dt.removeResistBuffs.length > 0) {
      const effect = this.createStatusEffect(StatusEffectType.BUFF_GENERIC, 0, casterSession.characterId, '', {
        skillName: skill.name,
        debuffCategory: category,
        removeResistBuffs: dt.removeResistBuffs,
      });
      if (effect) effects.push(effect);
    }

    return effects;
  }

  private calculateAccuracy(session: PlayerSession, target: TargetStats): number {
    if (target.dodge === 0) return 0.99;
    const baseStats = session.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
    const totalDex = (session.statPoints.DEX || 0) + (baseStats.DEX || 0);
    const attackerAccuracy = calcSharedAccuracy(session.stats.level, totalDex, 0);
    const hitChance = calculateHitChance(attackerAccuracy, target.dodge);
    return Math.min(0.99, Math.max(0.01, hitChance));
  }

  private calculateHealing(session: PlayerSession, skill: SkillDefinition): number {
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
    const spiScale = (h.statMultipliers as Record<string, number> | undefined)?.SPI ?? 0.3;
    const intScale = (h.statMultipliers as Record<string, number> | undefined)?.INT ?? 0.6;
    const levelScale = (h.statMultipliers as Record<string, number> | undefined)?.level ?? 1.0;
    const profScale = (h.statMultipliers as Record<string, number> | undefined)?.prof ?? 2.0;

    const mpMult = h.mpCostScaling
      ? 1.0 + (skill.mpCost / h.mpCostScaling)
      : 1.0 + (skill.mpCost / 30);

    const healPercent = session.statBreakdown?.healPercent || 0;
    const gearMult = 1 + (healPercent / 100);

    return Math.floor((baseAmount + totalSPI * spiScale + totalINT * intScale + level * levelScale + prof * profScale) * mpMult * gearMult);
  }

  private calculateMpRegen(session: PlayerSession, skill: SkillDefinition): number {
    const spi = session.statPoints.SPI;
    const level = session.stats.level;
    const multiplier = 1.0 + (skill.mpCost / 15);
    return Math.floor((spi * 1.5 + level * 1.5) * multiplier);
  }

  calculateMaxHpBuff(session: PlayerSession, skill: SkillDefinition): number {
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

  private applyBuff(session: PlayerSession, skill: SkillDefinition): void {
    this.applyBuffToTarget(session, session.characterId, skill, session);
  }

  private applyGuardianBuff(session: PlayerSession, skill: SkillDefinition, targetCharacterId: string): void {
    const now = Date.now();
    const duration = (skill.duration || 300) * 1000;
    session.statusEffects = session.statusEffects.filter(e => e.type !== StatusEffectType.BUFF_DAMAGE_REDIRECT);
    session.statusEffects.push({
      id: `buff_${Date.now()}_${Math.random().toString(36).slice(2, 6)}_guardian`,
      type: StatusEffectType.BUFF_DAMAGE_REDIRECT,
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

  applyBuffToTarget(
    target: PlayerSession,
    sourceId: string,
    skill: SkillDefinition,
    casterSession?: PlayerSession | null
  ): void {
    const now = Date.now();
    const duration = skill.isSong ? 5000 : (skill.duration || 300) * 1000;
    const bt = skill.buffEffectTable;

    const effects: StatusEffect[] = [];
    const pushEffect = (type: StatusEffectType, potency: number, buffData?: BuffData, extra?: Partial<StatusEffect>) => {
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
      if (skill.skillType === SkillType.HP_BUFF) {
        const baseMaxHp = target.stats.maxHealth;
        const hpIncrease = Math.floor(baseMaxHp * 0.15) + 250;
        pushEffect(StatusEffectType.BUFF_MAX_HP, 0, { maxHpFlat: hpIncrease, maxHpPercent: 0.15 });
      } else if (effects.length === 0) {
        pushEffect(StatusEffectType.BUFF_GENERIC, 0);
      }
      target.statusEffects.push(...effects);
      return;
    }

    if (bt.attackPowerMultiplier) {
      pushEffect(StatusEffectType.BUFF_ATTACK, bt.attackPowerMultiplier);
    }

    if (bt.def) {
      pushEffect(StatusEffectType.BUFF_DEFENSE, 0, { flatDefense: bt.def });
    }

    if (bt.str || bt.agi || bt.int || bt.spi || bt.dex || bt.sta) {
      pushEffect(StatusEffectType.BUFF_STAT, 0, {
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
      pushEffect(StatusEffectType.BUFF_CAST_SPEED, reduction);
    }

    if (bt.maxHp) {
      pushEffect(StatusEffectType.BUFF_MAX_HP, 0, { maxHpFlat: bt.maxHp });
    }

    if (bt.mpRegen) {
      pushEffect(StatusEffectType.BUFF_MP_REGEN, bt.mpRegen);
    }

    if (bt.mpRestorePerTick) {
      const cfg = bt.mpRestorePerTick;
      const caster = casterSession || target;
      const statVal = cfg.statScale
        ? (caster.baseStats?.[cfg.statScale as keyof typeof caster.baseStats] || 0) + ((caster.statPoints as unknown as Record<string, number>)?.[cfg.statScale] || 0)
        : 0;
      const profVal = cfg.proficiencyStat
        ? (caster.skillAdeptness?.[cfg.proficiencyStat] || 0)
        : 0;
      const mpPerTick = Math.floor(cfg.base + statVal * (cfg.statMultiplier ?? 0) + profVal * (cfg.proficiencyMultiplier ?? 0));
      pushEffect(StatusEffectType.BUFF_MP_REGEN, 0, { mpRestorePerTick: { mpPerTick, tickInterval: 3000 } });
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
        reductionPercent = safeFormulaEval(expr, { blessing });
      } else {
        const parsed = parseFloat(bt.physicalDamageReduction);
        if (!isNaN(parsed)) reductionPercent = parsed;
      }
      pushEffect(StatusEffectType.BUFF_PHYSICAL_REDUC, reductionPercent);
    }

    if (bt.dodgeChance) {
      pushEffect(StatusEffectType.BUFF_DODGE, bt.dodgeChance);
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
          } else {
            break;
          }
        }
        pushEffect(StatusEffectType.WEAPON_AURA, 0, {
          weaponAura: { element: aura.element, minDamage: matchedTier.min, maxDamage: matchedTier.max },
        });
      } else if (aura.formula === 'toxify') {
        const level = caster.stats?.level || 1;
        const auraDamage = Math.floor(level * (100 + proficiency) / 100);
        pushEffect(StatusEffectType.WEAPON_AURA, 0, {
          weaponAura: { element: aura.element, minDamage: auraDamage, maxDamage: auraDamage },
        });
      }
    }

    if (bt.accuracy) {
      pushEffect(StatusEffectType.BUFF_ACCURACY, bt.accuracy);
    }

    if (bt.attackSpeed) {
      pushEffect(StatusEffectType.BUFF_ATTACK_SPEED, bt.attackSpeed / 100);
    }

    if (bt.resistMods) {
      target.statusEffects = target.statusEffects.filter(e => e.exclusiveGroup !== 'resist_element');
      pushEffect(StatusEffectType.BUFF_RESIST, 0, { resistMods: bt.resistMods }, { exclusiveGroup: 'resist_element' });
    }

    if (bt.moveSpeed) {
      pushEffect(StatusEffectType.BUFF_MOVE_SPEED, bt.moveSpeed, { moveSpeedFlat: bt.moveSpeed });
    }

    if (bt.critResist) {
      pushEffect(StatusEffectType.BUFF_CRIT_RESIST, bt.critResist, { critResistPercent: bt.critResist });
    }

    if (bt.critDamageReduce) {
      pushEffect(StatusEffectType.BUFF_CRIT_DAMAGE_REDUCE, bt.critDamageReduce, { critDamageReducePercent: bt.critDamageReduce });
    }

    if (bt.auraDamageReduce) {
      pushEffect(StatusEffectType.BUFF_AURA_DAMAGE_REDUCE, bt.auraDamageReduce, { auraDamageReducePercent: bt.auraDamageReduce });
    }

    if (bt.manaShield) {
      target.statusEffects = target.statusEffects.filter(e => e.type !== StatusEffectType.BUFF_MANA_SHIELD);
      pushEffect(StatusEffectType.BUFF_MANA_SHIELD, 0, { manaShield: true });
    }

    if (bt.invisible) {
      target.statusEffects = target.statusEffects.filter(e => e.type !== StatusEffectType.INVISIBLE);
      pushEffect(StatusEffectType.INVISIBLE, 0, { invisible: bt.invisible }, { invisible: true, tickInterval: 1000 });
    }

    if (bt.barrierPhysical) {
      target.statusEffects = target.statusEffects.filter(e => e.type !== StatusEffectType.BARRIER_PHYSICAL);
      pushEffect(StatusEffectType.BARRIER_PHYSICAL, 0, { barrierPhysical: true }, { barrierType: 'physical' });
    }

    if (bt.barrierMagical) {
      target.statusEffects = target.statusEffects.filter(e => e.type !== StatusEffectType.BARRIER_MAGICAL);
      pushEffect(StatusEffectType.BARRIER_MAGICAL, 0, { barrierMagical: true }, { barrierType: 'magical' });
    }

    if (bt.elementalAbsorption) {
      pushEffect(StatusEffectType.BUFF_GENERIC, 0, { elementalAbsorption: bt.elementalAbsorption });
    }

    if (bt.devotion && casterSession) {
      target.statusEffects = target.statusEffects.filter(e => !(e.skillName === skill.name && e.buffData?.devotionLink));
      pushEffect(StatusEffectType.BUFF_GENERIC, 0, { devotionLink: { partnerId: sourceId } });
    }

    if (bt.misdirection) {
      target.statusEffects = target.statusEffects.filter(e => !(e.skillName === skill.name && e.buffData?.misdirection));
      pushEffect(StatusEffectType.BUFF_GENERIC, 0, { misdirection: true });
    }

    if (bt.extraHit) {
      target.statusEffects = target.statusEffects.filter(e => !(e.skillName === skill.name && e.buffData?.extraHit));
      pushEffect(StatusEffectType.BUFF_GENERIC, 0, { extraHit: true });
    }

    if (bt.spellInterruptResist) {
      pushEffect(StatusEffectType.BUFF_SPELL_INTERRUPT_RESIST, bt.spellInterruptResist, { spellInterruptResistPercent: bt.spellInterruptResist });
    }

    if (bt.debuffResist) {
      pushEffect(StatusEffectType.BUFF_DEBUFF_RESIST, bt.debuffResist, { debuffResistPercent: bt.debuffResist });
    }

    if (bt.blockingStance) {
      target.statusEffects = target.statusEffects.filter(e => e.type !== StatusEffectType.BUFF_BLOCKING_STANCE);
      const clearOnBlock = [StatusEffectType.STUN, StatusEffectType.SLEEP, StatusEffectType.KNOCKDOWN];
      target.statusEffects = target.statusEffects.filter(e => !clearOnBlock.includes(e.type));
      pushEffect(StatusEffectType.BUFF_BLOCKING_STANCE, 0, { blockingStance: true, blockingRange: bt.blockingRange || 6 });
    }

    if (bt.defensiveMarch) {
      target.statusEffects = target.statusEffects.filter(e => e.type !== StatusEffectType.BUFF_BLOCKING_STANCE);
      pushEffect(StatusEffectType.BUFF_BLOCKING_STANCE, 0, { blockingStance: true, blockingRange: bt.blockingRange || 7, defensiveMarch: true });
    }

    if (bt.shieldCharge) {
      pushEffect(StatusEffectType.BUFF_MOVE_SPEED, 2, { moveSpeedFlat: 2, shieldCharge: true });
    }

    if (bt.blockChance) {
      pushEffect(StatusEffectType.BUFF_BLOCK_CHANCE, bt.blockChance, { blockChancePercent: bt.blockChance });
    }

    if (bt.consumableOnAttack) {
      pushEffect(StatusEffectType.BUFF_CONSUMABLE_ON_ATTACK, bt.accuracy || 50, { consumableOnAttack: true, accuracyBonusFlat: bt.accuracy || 50 });
    }

    if (bt.dodgeReduction) {
      pushEffect(StatusEffectType.BUFF_GENERIC, 0, { dodgeReductionFlat: bt.dodgeReduction });
    }

    if (bt.healingOverTime) {
      const hot = bt.healingOverTime;
      const hotConfig = casterSession?.jobId ? HOT_JOB_CONFIG[casterSession.jobId] : undefined;
      const profStat = hotConfig?.proficiencyStat ?? hot.proficiencyStat;
      const profCoef = hotConfig?.coef ?? 0.5;
      const prof = profStat ? (casterSession?.skillAdeptness?.[profStat] || 0) : 0;
      const spi = (casterSession?.statPoints?.SPI || 0) + (casterSession?.baseStats?.SPI || 0);
      const hpPerTick = Math.floor(hot.base + spi * hot.spiScale + prof * profCoef);
      pushEffect(StatusEffectType.BUFF_GENERIC, 0, { healOverTime: { hpPerTick, tickInterval: 3000 } });
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
      pushEffect(StatusEffectType.BUFF_ATTACK, multiplier);
    }

    if (bt.cooldownReduction) {
      pushEffect(StatusEffectType.BUFF_GENERIC, 0, { cooldownReductionPercent: bt.cooldownReduction });
    }

    if (bt.magicalDamageBonus) {
      pushEffect(StatusEffectType.BUFF_GENERIC, 0, { magicalDamageBonusPercent: bt.magicalDamageBonus });
    }

    if (bt.auraDamageIncrease) {
      pushEffect(StatusEffectType.BUFF_GENERIC, 0, { auraDamageIncreasePercent: bt.auraDamageIncrease });
    }

    if (bt.songType) {
      const songMap: Record<string, StatusEffectType> = {
        green: StatusEffectType.SONG_GREEN,
        blue: StatusEffectType.SONG_BLUE,
        yellow: StatusEffectType.SONG_YELLOW,
        red: StatusEffectType.SONG_RED,
      };
      const songEffectType = songMap[bt.songType];
      if (songEffectType) {
        target.statusEffects = target.statusEffects.filter(e => ![StatusEffectType.SONG_GREEN, StatusEffectType.SONG_BLUE, StatusEffectType.SONG_YELLOW, StatusEffectType.SONG_RED].includes(e.type));
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
      pushEffect(StatusEffectType.BUFF_GENERIC, 0, { delayExplosion: { minMs: delayMs, maxMs: delayMs } });
      if (effects.length > 0) {
        const lastEffect = effects[effects.length - 1];
        lastEffect.delayExplosionAt = Date.now() + delayMs;
      }
    }

    if (bt.statTieredValues) {
      const cfg = bt.statTieredValues;
      const caster = casterSession || target;
      const statKey = cfg.stat as keyof typeof caster.baseStats;
      const totalStat = (caster.baseStats?.[statKey] || 0) + ((caster.statPoints as unknown as Record<string, number>)?.[statKey] || 0);
      const prof = cfg.proficiencyStat
        ? (caster.skillAdeptness?.[cfg.proficiencyStat] || 0)
        : 0;

      const firstTier = cfg.tiers[0];
      if (firstTier?.profTiers?.[0]) {
        const resultKeys = Object.keys(firstTier.profTiers[0].values) as string[];
        for (const resultKey of resultKeys) {
          const result = resolveStatTieredValue(cfg, totalStat, prof, resultKey);
          if (result != null) {
            if (resultKey === 'dodgeChance') {
              pushEffect(StatusEffectType.BUFF_DODGE, result);
            } else if (resultKey === 'def') {
              pushEffect(StatusEffectType.BUFF_DEFENSE, 0, { flatDefense: result });
            } else if (resultKey === 'accuracy') {
              pushEffect(StatusEffectType.BUFF_ACCURACY, result);
            }
          }
        }
      }
    }

    if (effects.length === 0) return;
    target.statusEffects.push(...effects);
  }

  updateCooldowns(session: PlayerSession): void {
    if (!session.skillCooldowns) return;
    const now = Date.now();
    session.skillCooldowns = session.skillCooldowns.filter(c => now < c.readyAt);
  }

  checkCasting(session: PlayerSession): { completed: boolean; skillName: string; targetId: string | null; aoePosition?: { x: number; y: number; z: number } } | null {
    if (!session.activeCast) return null;

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

  findSkillDefinition(skillName: string): SkillDefinition | null {
    if (CLASS_SPECIFIC_SKILL_LOOKUP.has(skillName)) {
      return CLASS_SPECIFIC_SKILL_LOOKUP.get(skillName)!;
    }
    return CLASS_SKILL_LOOKUP.get(skillName) || null;
  }

  getSkillType(skillName: string): SkillType | undefined {
    const skill = this.findSkillDefinition(skillName);
    if (!skill) return undefined;
    return skill.skillType ?? this.inferSkillType(skill);
  }

  getSubCategoryForSkill(skillName: string): string | null {
    return SKILL_TO_SUBCATEGORY[skillName] || null;
  }

  getAvailableSkills(session: PlayerSession): string[] {
    const available: string[] = [];
    const proficiencies = session.skillProficiencies || {};

    for (const category of Object.values(CLASS_SKILL_DATA)) {
      for (const subSkill of category.skills) {
        const subPoints = proficiencies[subSkill.name] || 0;
        for (const [name, def] of Object.entries(subSkill.skills)) {
          if (isPassiveSkill(def)) continue;
          if (typeof def.reqPoints === 'number') {
            if (subPoints >= def.reqPoints) {
              available.push(name);
            }
          } else if (Array.isArray(def.reqPoints)) {
            if (meetsRequirements(def.reqPoints, (skillName: string) => proficiencies[skillName] || 0)) {
              available.push(name);
            }
          }
        }
      }
    }

    const jobSkills = getClassSpecificSkillsForJob(session.jobId, session.baseClass);
    for (const [name, def] of Object.entries(jobSkills)) {
      const skillDef = def as any;
      if (isPassiveSkill(skillDef)) continue;
      if (skillDef.reqLevel && skillDef.reqLevel > session.stats.level) continue;
      if (skillDef.reqPoints && typeof skillDef.reqPoints === 'number') continue;
      if (skillDef.reqPoints && Array.isArray(skillDef.reqPoints)) {
        if (!meetsRequirements(skillDef.reqPoints, (skillName: string) => proficiencies[skillName] || 0)) continue;
      }
      available.push(name);
    }

    return available;
  }

  tickStatusEffects(session: PlayerSession, now: number): { damage: number; mpDamage: number; healed: number; mpRestored: number; expired: StatusEffect[] } {
    let damage = 0;
    let mpDamage = 0;
    let healed = 0;
    let mpRestored = 0;
    const expired: StatusEffect[] = [];

    if (!session.statusEffects) return { damage: 0, mpDamage: 0, healed: 0, mpRestored: 0, expired: [] };

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
        } else if (effect.potency > 0) {
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

      if (effect.type === StatusEffectType.INVISIBLE && effect.buffData?.invisible && effect.tickInterval > 0 && now - effect.lastTickAt >= effect.tickInterval) {
        effect.lastTickAt = now;
        const mpDrain = effect.buffData.invisible.mpCostPerSec;
        mpDamage += mpDrain;
        if (effect.buffData.invisible.stationaryOnly) {
          if (session.stats.mana - mpDamage <= 0) {
            expired.push(effect);
          }
        }
      }

      const songTypes = SONG_TYPES;
      if (songTypes.includes(effect.type) && effect.tickInterval > 0 && now - effect.lastTickAt >= effect.tickInterval) {
        effect.lastTickAt = now;
        if (effect.type === StatusEffectType.SONG_RED) {
          const basePower = 2;
          const totalINT = (session.statPoints.INT || 0) + (session.baseStats?.INT || 0);
          const totalSPI = (session.statPoints.SPI || 0) + (session.baseStats?.SPI || 0);
          damage += Math.floor(basePower * (totalINT + totalSPI * 0.3));
          mpDamage += Math.floor(basePower * (totalINT + totalSPI * 0.3) * 0.3);
        }
      }
    }

    const expiredSet = new Set(expired);
    session.statusEffects = session.statusEffects.filter(
      e => !expiredSet.has(e)
    );

    return { damage, mpDamage, healed, mpRestored, expired };
  }
}
