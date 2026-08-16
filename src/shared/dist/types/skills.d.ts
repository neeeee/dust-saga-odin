import { StatusEffectType } from './status';
import type { BuffEffectTable } from './status';
import type { DebuffEffectTable } from '../constants/debuffs';
export declare enum SkillCategoryId {
    MELEE = 0,
    TECHNIQUE = 6,
    PRAYER = 12,
    MAGIC = 17,
    SPECIAL = 22
}
export declare enum DamageType {
    PHYSICAL = "physical",
    MAGICAL = "magical"
}
export declare enum PhysicalDamageSubType {
    SLASH = "slash",
    THRUST = "thrust",
    CLEAVE = "cleave",
    BASH = "bash",
    RANGED = "ranged"
}
export declare enum MagicalDamageSubType {
    FIRE = "fire",
    ICE = "ice",
    LIGHTNING = "lightning",
    DARK = "dark",
    HOLY = "holy",
    POISON = "poison"
}
export type DamageSubType = PhysicalDamageSubType | MagicalDamageSubType;
export interface SkillRequirement {
    skillName: string;
    points: number;
}
export type SkillReqPoints = number | SkillRequirement[];
export declare enum AOETargetMode {
    SELF_CENTERED = "self_centered",
    TARGET_CENTERED = "target_centered",
    GROUND_TARGETED = "ground_targeted",
    CONE = "cone"
}
import { WeaponType } from './items';
export interface SkillDefinition {
    name: string;
    reqPoints: SkillReqPoints;
    reqLevel?: number;
    mpCost: number;
    castTime: number;
    cooldown: number;
    duration: number;
    description: string;
    damageType?: DamageType;
    damageSubType?: DamageSubType;
    skillType?: SkillType;
    isPassive?: boolean;
    isAOE?: boolean;
    aoeTargetMode?: AOETargetMode;
    aoeRadius?: number;
    range?: number;
    isBuff?: boolean;
    isDebuff?: boolean;
    hasDebuff?: boolean;
    selfBuffOnly?: boolean;
    isRevive?: boolean;
    buffEffectTable?: BuffEffectTable;
    debuffEffectTable?: DebuffEffectTable;
    debuffDuration?: number;
    basePower?: number;
    baseHits?: number;
    pulseCount?: number;
    pulseInterval?: number;
    consumableItem?: string;
    consumableItemQuantity?: number;
    createItems?: Array<{
        itemId: string;
        quantity: number;
        consumeItems?: Array<{
            itemId: string;
            quantity: number;
        }>;
    }>;
    sacrificeHeal?: boolean;
    hidden?: boolean;
    isSong?: boolean;
    mpDamage?: boolean;
    onHitEffects?: OnHitEffect[];
    healing?: HealingEffect;
    delayExplosion?: {
        minSeconds: number;
        maxSeconds: number;
    };
    dispelBuff?: boolean;
    dispelDebuff?: boolean;
    revealInvisible?: boolean;
    summonObject?: SummonObject;
    banishObject?: boolean;
    banishRadius?: number;
    negateFieldSpells?: boolean;
    fieldSpellNegationRadius?: number;
    damageVsLowDefense?: boolean;
    fearAOE?: boolean;
    preventResurrect?: boolean;
    curse?: boolean;
    blockOnly?: boolean;
    shieldRequired?: boolean;
    requiredWeaponType?: WeaponType[];
    invisible?: {
        stationaryOnly: boolean;
        mpCostPerSec: number;
    };
    barrier?: 'physical' | 'magical';
    elementalAbsorption?: {
        elements: string[];
        convertTo: 'hp' | 'mp';
    };
    manaShield?: {
        mpPerHp: number;
    };
    manaSwap?: boolean;
    soulSwap?: boolean;
    devotion?: boolean;
    magicalAid?: {
        mpRestorePercent: number;
    };
    removeResistBuffs?: string[];
    misdirection?: boolean;
    lineOfSightRequired?: boolean;
    scalingStat?: 'STR' | 'DEX' | 'INT' | 'SPI' | 'AGI' | 'STA';
    proficiencyBonus?: number;
    elementalPower?: number;
    dualPhysical?: {
        basePower: number;
        damageSubType?: PhysicalDamageSubType;
        scalingStat?: 'STR' | 'DEX' | 'INT' | 'SPI' | 'AGI' | 'STA';
    };
    knockback?: number;
    coneAngle?: number;
    coneRange?: number;
    bladeWidth?: number;
    bladeCount?: number;
}
export interface SkillSubCategory {
    id: number;
    name: string;
    skills: Record<string, SkillDefinition>;
    hidden?: boolean;
}
export interface SkillCategoryData {
    name: string;
    skills: SkillSubCategory[];
}
export interface ClassSpecificSkill {
    reqLevel?: number;
    reqPoints?: SkillReqPoints;
    mpCost: number;
    castTime: number;
    cooldown: number;
    duration: number;
    description: string;
    damageType?: DamageType;
    damageSubType?: DamageSubType;
    skillType?: SkillType;
    isAOE?: boolean;
    aoeTargetMode?: AOETargetMode;
    aoeRadius?: number;
    range?: number;
    buffEffectTable?: BuffEffectTable;
    debuffEffectTable?: DebuffEffectTable;
    debuffDuration?: number;
    basePower?: number;
    baseHits?: number;
    pulseCount?: number;
    pulseInterval?: number;
    onHitEffects?: OnHitEffect[];
    healing?: HealingEffect;
    consumableItem?: string;
    consumableItemQuantity?: number;
    isPassive?: boolean;
    isBuff?: boolean;
    isDebuff?: boolean;
    hasDebuff?: boolean;
    selfBuffOnly?: boolean;
    isRevive?: boolean;
    isSong?: boolean;
    sacrificeHeal?: boolean;
    mpDamage?: boolean;
    createItems?: Array<{
        itemId: string;
        quantity: number;
        consumeItems?: Array<{
            itemId: string;
            quantity: number;
        }>;
    }>;
    hidden?: boolean;
    delayExplosion?: {
        minSeconds: number;
        maxSeconds: number;
    };
    dispelBuff?: boolean;
    dispelDebuff?: boolean;
    revealInvisible?: boolean;
    summonObject?: SummonObject;
    banishObject?: boolean;
    negateFieldSpells?: boolean;
    fieldSpellNegationRadius?: number;
    damageVsLowDefense?: boolean;
    fearAOE?: boolean;
    preventResurrect?: boolean;
    curse?: boolean;
    blockOnly?: boolean;
    shieldRequired?: boolean;
    invisible?: {
        stationaryOnly: boolean;
        mpCostPerSec: number;
    };
    barrier?: 'physical' | 'magical';
    elementalAbsorption?: {
        elements: string[];
        convertTo: 'hp' | 'mp';
    };
    manaShield?: {
        mpPerHp: number;
    };
    manaSwap?: boolean;
    soulSwap?: boolean;
    devotion?: boolean;
    magicalAid?: {
        mpRestorePercent: number;
    };
    removeResistBuffs?: string[];
    misdirection?: boolean;
    lineOfSightRequired?: boolean;
    scalingStat?: 'STR' | 'DEX' | 'INT' | 'SPI' | 'AGI' | 'STA';
    proficiencyBonus?: number;
    dualPhysical?: {
        basePower: number;
        damageSubType?: PhysicalDamageSubType;
        scalingStat?: 'STR' | 'DEX' | 'INT' | 'SPI' | 'AGI' | 'STA';
    };
    knockback?: number;
    coneAngle?: number;
    coneRange?: number;
    bladeWidth?: number;
    bladeCount?: number;
}
export type ClassSpecificSkills = Record<string, ClassSpecificSkill>;
export interface SkillCooldownEntry {
    skillName: string;
    readyAt: number;
}
export interface ActiveCast {
    skillName: string;
    startedAt: number;
    castTime: number;
    targetId: string | null;
    aoePosition?: {
        x: number;
        y: number;
        z: number;
    };
}
export interface SkillAllocation {
    skillId: number;
    points: number;
}
export type SkillAllocations = SkillAllocation[];
export declare enum SkillTargetType {
    SELF = "self",
    SELF_OR_TARGET = "self_or_target",
    PARTY = "party",
    OTHER_ONLY = "other_only"
}
export declare enum SkillType {
    DAMAGE_PHYSICAL = "damage_physical",
    DAMAGE_MAGICAL = "damage_magical",
    HEAL = "heal",
    HEAL_OVER_TIME = "heal_over_time",
    PARTY_HEAL = "party_heal",
    HP_BUFF = "hp_buff",
    MP_RESTORE = "mp_restore",
    DRAIN_LIFE = "drain_life",
    SACRIFICE_HEAL = "sacrifice_heal",
    REVIVE = "revive",
    BUFF = "buff",
    DEBUFF = "debuff",
    SONG = "song",
    CRAFT = "craft",
    UTILITY = "utility",
    SUMMON = "summon",
    FIELD_SPELL = "field_spell",
    MP_DAMAGE = "mp_damage",
    DISPEL = "dispel",
    FEAR = "fear",
    PASSIVE = "passive",
    PROVOKE = "provoke",
    INVISIBILITY = "invisibility",
    BARRIER = "barrier",
    MANA_SHIELD = "mana_shield",
    ABSORPTION = "absorption",
    MANA_SWAP = "mana_swap",
    SOUL_SWAP = "soul_swap",
    DEVOTION = "devotion",
    KNOCKBACK = "knockback"
}
export declare const BENEFICIAL_SKILL_TYPES: ReadonlySet<SkillType>;
export declare function isBeneficialSkillType(type: SkillType): boolean;
export interface OnHitEffect {
    type: StatusEffectType;
    chance?: number;
    potency?: number | {
        formula?: string;
        stat?: string;
        [key: string]: unknown;
    };
    duration?: number;
}
export interface HealingEffect {
    type: 'single' | 'party' | 'over_time' | 'hp_buff';
    baseAmount?: number;
    statMultipliers?: Record<string, number>;
    percentOfMaxHp?: number;
    flatBonus?: number;
    tickInterval?: number;
    proficiencyStat?: string;
    mpCostScaling?: number;
}
export interface SummonObject {
    objectType: string;
    duration: number;
    hp?: number;
    defense?: number;
    aoeDamage?: number;
    attackDamage?: number;
    attackRange?: number;
    attackCooldown?: number;
}
export declare const SKILL_TARGET_RULES: Record<string, SkillTargetType>;
export declare function isPassiveSkill(skill: SkillDefinition | ClassSpecificSkill): boolean;
export declare function getSkillTargetType(skill: SkillDefinition | ClassSpecificSkill): SkillTargetType | undefined;
export declare function meetsRequirements(reqPoints: SkillReqPoints, getSkillPoints: (skillName: string) => number): boolean;
export declare function getRequiredProficiency(reqPoints: SkillReqPoints): number;
