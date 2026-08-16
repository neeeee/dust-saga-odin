export declare enum StatusEffectType {
    POISON = "poison",
    BURN = "burn",
    FREEZE = "freeze",
    STUN = "stun",
    SILENCE = "silence",
    SLEEP = "sleep",
    KNOCKDOWN = "knockdown",
    CHARM = "charm",
    BLEED = "bleed",
    ROOT = "root",
    SLOW = "slow",
    HASTE = "haste",
    BUFF_DEFENSE = "buff_defense",
    BUFF_CAST_SPEED = "buff_cast_speed",
    BUFF_MAX_HP = "buff_max_hp",
    BUFF_MP_REGEN = "buff_mp_regen",
    BUFF_ATTACK = "buff_attack",
    BUFF_PHYSICAL_REDUC = "buff_physical_reduc",
    BUFF_STAT = "buff_stat",
    BUFF_DODGE = "buff_dodge",
    BUFF_ACCURACY = "buff_accuracy",
    BUFF_ATTACK_SPEED = "buff_attack_speed",
    BUFF_MOVE_SPEED = "buff_move_speed",
    BUFF_GENERIC = "buff_generic",
    SEVERE_POISON = "severe_poison",
    MP_DRAIN = "mp_drain",
    DEBUFF_DAMAGE_DOWN = "debuff_damage_down",
    DEBUFF_DEFENSE_DOWN = "debuff_defense_down",
    DEBUFF_SPEED_DOWN = "debuff_speed_down",
    DEBUFF_ACCURACY_DOWN = "debuff_accuracy_down",
    DEBUFF_DODGE_DOWN = "debuff_dodge_down",
    DEBUFF_CAST_SPEED_DOWN = "debuff_cast_speed_down",
    DEBUFF_DAMAGE_TAKEN_UP = "debuff_damage_taken_up",
    WEAPON_AURA = "weapon_aura",
    BUFF_RESIST = "buff_resist",
    BUFF_CRIT_RESIST = "buff_crit_resist",
    BUFF_CRIT_DAMAGE_REDUCE = "buff_crit_damage_reduce",
    BUFF_AURA_DAMAGE_REDUCE = "buff_aura_damage_reduce",
    BUFF_MANA_SHIELD = "buff_mana_shield",
    BUFF_SPELL_INTERRUPT_RESIST = "buff_spell_interrupt_resist",
    BUFF_DEBUFF_RESIST = "buff_debuff_resist",
    BUFF_DAMAGE_REDIRECT = "buff_damage_redirect",
    BUFF_BLOCK_CHANCE = "buff_block_chance",
    BUFF_BLOCKING_STANCE = "buff_blocking_stance",
    BUFF_BLOCKING_PROTECTED = "buff_blocking_protected",
    BUFF_CONSUMABLE_ON_ATTACK = "buff_consumable_on_attack",
    BUFF_GUARDED = "buff_guarded",
    BUFF_DAMAGE_NEGATION = "buff_damage_negation",
    SONG_ACTIVE = "song_active",
    SONG_GREEN = "song_green",
    SONG_BLUE = "song_blue",
    SONG_YELLOW = "song_yellow",
    SONG_RED = "song_red",
    FEAR = "fear",
    CURSE = "curse",
    PREVENT_FIELD_SPELLS = "prevent_field_spells",
    PREVENT_RESSURECT = "prevent_resurrect",
    MP_DAMAGE_DEBUFF = "mp_damage_debuff",
    INVISIBLE = "invisible",
    BARRIER_PHYSICAL = "barrier_physical",
    BARRIER_MAGICAL = "barrier_magical",
    BUFF_OBELISK = "buff_obelisk"
}
export declare const SONG_TYPES: readonly StatusEffectType[];
export declare const CC_TYPES: readonly StatusEffectType[];
export declare function isInvisible(activeEffects: StatusEffect[]): boolean;
export declare function hasBarrier(activeEffects: StatusEffect[], damageType: 'physical' | 'magical'): boolean;
export declare function consumeBarrier(activeEffects: StatusEffect[], damageType: 'physical' | 'magical'): void;
export declare function hasStatusEffectType(activeEffects: StatusEffect[], types: readonly StatusEffectType[]): boolean;
export declare function isCCImmune(activeEffects: StatusEffect[]): boolean;
export declare function isSilenced(activeEffects: StatusEffect[]): boolean;
export declare function isRooted(activeEffects: StatusEffect[]): boolean;
export interface StatValueTier {
    threshold: number;
    profTiers?: Array<{
        threshold: number;
        values: Record<string, number>;
    }>;
}
export interface StatTieredConfig {
    stat: string;
    proficiencyStat?: string;
    tiers: StatValueTier[];
}
export declare function resolveStatTieredValue(config: StatTieredConfig, statValue: number, profValue: number, resultKey: string): number | null;
export interface BuffEffectTable {
    attackPowerMultiplier?: number;
    def?: number;
    str?: number;
    agi?: number;
    int?: number;
    spi?: number;
    dex?: number;
    sta?: number;
    castTime?: number;
    maxHp?: number;
    mpRegen?: number;
    mpRestorePerTick?: {
        base: number;
        statScale?: string;
        statMultiplier?: number;
        proficiencyStat?: string;
        proficiencyMultiplier?: number;
    };
    physicalDamageReduction?: string;
    dodgeChance?: number;
    accuracy?: number;
    attackSpeed?: number;
    moveSpeed?: number;
    critResist?: number;
    critDamageReduce?: number;
    auraDamageReduce?: number;
    auraDamageIncrease?: number;
    manaShield?: boolean;
    spellInterruptResist?: number;
    debuffResist?: number;
    damageRedirect?: {
        targetId: string;
    };
    blockChance?: number;
    consumableOnAttack?: boolean;
    cooldownReduction?: number;
    magicalDamageBonus?: number;
    damageNegation?: {
        base: number;
        spiScale: number;
        proficiencyCap: number;
        proficiencyStat: string;
    };
    dodgeReduction?: number;
    accuracyBonus?: number;
    healingOverTime?: {
        base: number;
        spiScale: number;
        proficiencyStat: string;
    };
    partyHeal?: number;
    healPercent?: number;
    mpDamage?: number;
    mpDamageAOE?: boolean;
    attackPowerMultiplierProficiency?: {
        baseStat: string;
        perProficiency: number;
        proficiencyStat: string;
    };
    fear?: boolean;
    fearAOE?: boolean;
    songType?: 'green' | 'blue' | 'yellow' | 'red';
    delayExplosion?: {
        minSeconds: number;
        maxSeconds: number;
    };
    preventResurrect?: boolean;
    preventFieldSpells?: boolean;
    consumableItem?: {
        itemId: string;
        quantity: number;
    };
    createItems?: Array<{
        itemId: string;
        quantity: number;
        consumeItems?: Array<{
            itemId: string;
            quantity: number;
        }>;
    }>;
    sacrificeHeal?: boolean;
    dispelBuff?: boolean;
    dispelDebuff?: boolean;
    revealInvisible?: boolean;
    summonObject?: {
        objectType: string;
        duration: number;
        hp?: number;
        defense?: number;
        aoeDamage?: number;
    };
    banishObject?: boolean;
    negateFieldSpells?: boolean;
    fieldSpellNegationRadius?: number;
    blockingStance?: boolean;
    blockingRange?: number;
    shieldCharge?: boolean;
    defensiveMarch?: boolean;
    skillDisableAOE?: boolean;
    damageVsLowDefense?: boolean;
    songRadius?: number;
    songCooldownReduction?: number;
    songMagicalDamageBonus?: number;
    songDamageNegation?: {
        base: number;
        spiScale: number;
        proficiencyCap: number;
    };
    statTieredValues?: StatTieredConfig;
    weaponAura?: {
        element: string;
        spiTiers?: Array<{
            spi: number;
            min: number;
            max: number;
        }>;
        formula?: 'toxify';
    };
    resistMods?: Record<string, number>;
    invisible?: {
        stationaryOnly: boolean;
        mpCostPerSec: number;
    };
    barrierPhysical?: boolean;
    barrierMagical?: boolean;
    elementalAbsorption?: {
        elements: string[];
        convertTo: 'hp' | 'mp';
    };
    removeResistBuffs?: string[];
    manaSwap?: boolean;
    soulSwap?: boolean;
    devotion?: boolean;
    magicalAid?: {
        mpRestorePercent: number;
    };
    knockback?: {
        distance: number;
    };
    misdirection?: boolean;
    extraHit?: boolean;
}
export interface BuffData {
    flatStats?: Partial<{
        str: number;
        agi: number;
        int: number;
        spi: number;
        dex: number;
        sta: number;
    }>;
    flatDefense?: number;
    defenseMultiplier?: number;
    attackMultiplier?: number;
    castTimeReductionPercent?: number;
    maxHpFlat?: number;
    maxHpPercent?: number;
    mpRegenFlat?: number;
    physicalDamageReductionPercent?: number;
    dodgeFlat?: number;
    accuracyFlat?: number;
    attackSpeedPercent?: number;
    moveSpeedFlat?: number;
    moveSpeedMultiplier?: number;
    weaponAura?: {
        element: string;
        minDamage: number;
        maxDamage: number;
    };
    resistMods?: Record<string, number>;
    critResistPercent?: number;
    critDamageReducePercent?: number;
    auraDamageReducePercent?: number;
    auraDamageIncreasePercent?: number;
    manaShield?: boolean;
    invisible?: {
        stationaryOnly: boolean;
        mpCostPerSec: number;
    };
    barrierPhysical?: boolean;
    barrierMagical?: boolean;
    elementalAbsorption?: {
        elements: string[];
        convertTo: 'hp' | 'mp';
    };
    devotionLink?: {
        partnerId: string;
    };
    magicalAid?: {
        mpRestorePercent: number;
    };
    misdirection?: boolean;
    spellInterruptResistPercent?: number;
    debuffResistPercent?: number;
    damageRedirectTargetId?: string;
    guardedBy?: string;
    blockingProtectedBy?: string;
    blockChancePercent?: number;
    consumableOnAttack?: boolean;
    cooldownReductionPercent?: number;
    magicalDamageBonusPercent?: number;
    dodgeReductionFlat?: number;
    accuracyBonusFlat?: number;
    healOverTime?: {
        hpPerTick: number;
        tickInterval: number;
    };
    mpRestorePerTick?: {
        mpPerTick: number;
        tickInterval: number;
    };
    fear?: boolean;
    delayExplosion?: {
        minMs: number;
        maxMs: number;
    };
    preventResurrect?: boolean;
    preventFieldSpells?: boolean;
    blockingStance?: boolean;
    blockingRange?: number;
    defensiveMarch?: boolean;
    shieldCharge?: boolean;
    songType?: 'green' | 'blue' | 'yellow' | 'red';
    songRadius?: number;
    damageNegation?: {
        base: number;
        spiScale: number;
        proficiencyCap: number;
    };
    damageNegationThreshold?: number;
    healPercent?: number;
    extraHit?: boolean;
    /** Obelisk weapon buff: magic-resistance points ignored on magic attacks. */
    obeliskResistIgnore?: number;
    /** Obelisk weapon buff: percent reduction to all incoming damage. */
    obeliskDamageReduction?: number;
}
export interface StatusEffect {
    id: string;
    type: StatusEffectType;
    sourceId: string;
    targetId: string;
    potency: number;
    appliedAt: number;
    duration: number;
    tickInterval: number;
    lastTickAt: number;
    stacks: number;
    skillName?: string;
    buffData?: BuffData;
    dotMpDrain?: number;
    dotHPPercent?: number;
    consumable?: boolean;
    debuffCategory?: 'ailment' | 'disorder' | 'stun' | 'trip' | 'freeze' | 'burn' | 'curse' | 'bleed' | 'sleep' | 'weakness' | 'weaken' | 'knockdown' | 'knockback';
    exclusiveGroup?: string;
    mpDamageDirect?: number;
    summonObjectId?: string;
    summonObjectType?: string;
    delayExplosionAt?: number;
    delayExplosionTargetId?: number;
    preventResurrect?: boolean;
    preventFieldSpells?: boolean;
    fearDirection?: {
        x: number;
        y: number;
        z: number;
    };
    invisible?: boolean;
    barrierType?: 'physical' | 'magical';
    knockbackVelocity?: {
        dx: number;
        dz: number;
        remaining: number;
    };
    removeResistBuffs?: string[];
    disablePhysicalAttacks?: boolean;
    attackHalved?: boolean;
    lastInRangeAt?: number;
    songProximityBuff?: boolean;
    lastPulseAt?: number;
}
export interface StatusEffectDefinition {
    type: StatusEffectType;
    duration: number;
    tickInterval: number;
    potency: number;
    isDoT: boolean;
    isCC: boolean;
}
export declare const STATUS_EFFECT_DEFS: Partial<Record<StatusEffectType, StatusEffectDefinition>>;
export interface EffectiveStats {
    attack: number;
    defense: number;
    magicAttack: number;
    maxHealth: number;
    maxMana: number;
    speed: number;
    physicalDamageReduction: number;
    dodgeBonus: number;
    accuracyBonus: number;
    castTimeReduction: number;
    attackSpeedMultiplier: number;
    damageTakenMultiplier: number;
    castSpeedPenalty: number;
    speedMultiplier: number;
    auraDamageMultiplier: number;
    healPercent: number;
}
export declare function getEffectiveStats(baseStats: {
    attack: number;
    defense: number;
    magicAttack: number;
    maxHealth: number;
    maxMana: number;
    speed: number;
}, statPoints: {
    STR: number;
    AGI: number;
    INT: number;
    SPI: number;
    DEX: number;
    STA: number;
}, statusEffects: StatusEffect[]): {
    attack: number;
    defense: number;
    magicAttack: number;
    maxHealth: number;
    maxMana: number;
    speed: number;
    speedMultiplier: number;
    physicalDamageReduction: number;
    dodgeBonus: number;
    accuracyBonus: number;
    castTimeReduction: number;
    attackSpeedMultiplier: number;
    damageTakenMultiplier: number;
    castSpeedPenalty: number;
    auraDamageMultiplier: number;
    healPercent: number;
};
export interface EnhancementBonus {
    attack: number;
    defense: number;
    health: number;
    magicAttackPercent: number;
    dodge: number;
}
export interface StatBonusBreakdown {
    gear: {
        STA: number;
        STR: number;
        AGI: number;
        DEX: number;
        SPI: number;
        INT: number;
    };
    buffs: {
        STA: number;
        STR: number;
        AGI: number;
        DEX: number;
        SPI: number;
        INT: number;
    };
    gearCombat?: {
        accuracy: number;
        dodge: number;
        attackSpeed: number;
        fireResist: number;
        iceResist: number;
        lightningResist: number;
        poisonResist: number;
        darkResist: number;
        holyResist: number;
        ailmentResist: number;
        disorderResist: number;
        stunResist: number;
        tripResist: number;
        freezeResist: number;
        burnResist: number;
        curseResist: number;
        bleedResist: number;
        sleepResist: number;
        weaknessResist: number;
        weakenResist: number;
        knockdownResist: number;
        knockbackResist: number;
    };
    enhancement?: EnhancementBonus;
    totalAccuracy?: number;
    totalDodge?: number;
    totalAilmentResist?: number;
    totalDisorderResist?: number;
    buffCooldownReduction?: number;
    healPercent?: number;
}
export declare function computeStatBreakdown(statPoints: {
    STA: number;
    STR: number;
    AGI: number;
    DEX: number;
    SPI: number;
    INT: number;
}, statusEffects: StatusEffect[], gearBonuses: {
    STA: number;
    STR: number;
    AGI: number;
    DEX: number;
    SPI: number;
    INT: number;
}, gearCombat?: {
    accuracy: number;
    dodge: number;
    attackSpeed: number;
    fireResist: number;
    iceResist: number;
    lightningResist: number;
    poisonResist: number;
    darkResist: number;
    holyResist: number;
    ailmentResist: number;
    disorderResist: number;
    stunResist: number;
    tripResist: number;
    freezeResist: number;
    burnResist: number;
    curseResist: number;
    bleedResist: number;
    sleepResist: number;
    weaknessResist: number;
    weakenResist: number;
    knockdownResist: number;
    knockbackResist: number;
}): StatBonusBreakdown;
