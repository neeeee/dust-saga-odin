export enum StatusEffectType {
  POISON = 'poison',
  BURN = 'burn',
  FREEZE = 'freeze',
  STUN = 'stun',
  SILENCE = 'silence',
  SLEEP = 'sleep',
  KNOCKDOWN = 'knockdown',
  CHARM = 'charm',
  BLEED = 'bleed',
  ROOT = 'root',
  SLOW = 'slow',
  HASTE = 'haste',
  BUFF_DEFENSE = 'buff_defense',
  BUFF_CAST_SPEED = 'buff_cast_speed',
  BUFF_MAX_HP = 'buff_max_hp',
  BUFF_MP_REGEN = 'buff_mp_regen',
  BUFF_ATTACK = 'buff_attack',
  BUFF_PHYSICAL_REDUC = 'buff_physical_reduc',
  BUFF_STAT = 'buff_stat',
  BUFF_DODGE = 'buff_dodge',
  BUFF_ACCURACY = 'buff_accuracy',
  BUFF_ATTACK_SPEED = 'buff_attack_speed',
  BUFF_MOVE_SPEED = 'buff_move_speed',
  BUFF_GENERIC = 'buff_generic',
  SEVERE_POISON = 'severe_poison',
  MP_DRAIN = 'mp_drain',
  DEBUFF_DAMAGE_DOWN = 'debuff_damage_down',
  DEBUFF_DEFENSE_DOWN = 'debuff_defense_down',
  DEBUFF_SPEED_DOWN = 'debuff_speed_down',
  DEBUFF_ACCURACY_DOWN = 'debuff_accuracy_down',
  DEBUFF_DODGE_DOWN = 'debuff_dodge_down',
  DEBUFF_CAST_SPEED_DOWN = 'debuff_cast_speed_down',
  DEBUFF_DAMAGE_TAKEN_UP = 'debuff_damage_taken_up',
  WEAPON_AURA = 'weapon_aura',
  BUFF_RESIST = 'buff_resist',
  BUFF_CRIT_RESIST = 'buff_crit_resist',
  BUFF_CRIT_DAMAGE_REDUCE = 'buff_crit_damage_reduce',
  BUFF_AURA_DAMAGE_REDUCE = 'buff_aura_damage_reduce',
  BUFF_MANA_SHIELD = 'buff_mana_shield',
  BUFF_SPELL_INTERRUPT_RESIST = 'buff_spell_interrupt_resist',
  BUFF_DEBUFF_RESIST = 'buff_debuff_resist',
  BUFF_DAMAGE_REDIRECT = 'buff_damage_redirect',
  BUFF_BLOCK_CHANCE = 'buff_block_chance',
  BUFF_BLOCKING_STANCE = 'buff_blocking_stance',
  BUFF_BLOCKING_PROTECTED = 'buff_blocking_protected',
  BUFF_CONSUMABLE_ON_ATTACK = 'buff_consumable_on_attack',
  BUFF_GUARDED = 'buff_guarded',
  BUFF_DAMAGE_NEGATION = 'buff_damage_negation',
  SONG_ACTIVE = 'song_active',
  SONG_GREEN = 'song_green',
  SONG_BLUE = 'song_blue',
  SONG_YELLOW = 'song_yellow',
  SONG_RED = 'song_red',
  FEAR = 'fear',
  CURSE = 'curse',
  PREVENT_FIELD_SPELLS = 'prevent_field_spells',
  PREVENT_RESSURECT = 'prevent_resurrect',
  MP_DAMAGE_DEBUFF = 'mp_damage_debuff',
  INVISIBLE = 'invisible',
  BARRIER_PHYSICAL = 'barrier_physical',
  BARRIER_MAGICAL = 'barrier_magical',
  BUFF_OBELISK = 'buff_obelisk',
}

export const SONG_TYPES: readonly StatusEffectType[] = [
  StatusEffectType.SONG_GREEN,
  StatusEffectType.SONG_BLUE,
  StatusEffectType.SONG_YELLOW,
  StatusEffectType.SONG_RED,
];

export const CC_TYPES: readonly StatusEffectType[] = [
  StatusEffectType.STUN,
  StatusEffectType.FREEZE,
];

export function isInvisible(activeEffects: StatusEffect[]): boolean {
  return activeEffects.some(e => e.type === StatusEffectType.INVISIBLE);
}

export function hasBarrier(activeEffects: StatusEffect[], damageType: 'physical' | 'magical'): boolean {
  if (damageType === 'physical') return activeEffects.some(e => e.type === StatusEffectType.BARRIER_PHYSICAL);
  return activeEffects.some(e => e.type === StatusEffectType.BARRIER_MAGICAL);
}

export function consumeBarrier(activeEffects: StatusEffect[], damageType: 'physical' | 'magical'): void {
  const idx = activeEffects.findIndex(e =>
    e.type === (damageType === 'physical' ? StatusEffectType.BARRIER_PHYSICAL : StatusEffectType.BARRIER_MAGICAL)
  );
  if (idx !== -1) activeEffects.splice(idx, 1);
}

export function hasStatusEffectType(activeEffects: StatusEffect[], types: readonly StatusEffectType[]): boolean {
  return activeEffects.some(e => types.includes(e.type));
}

export function isCCImmune(activeEffects: StatusEffect[]): boolean {
  return hasStatusEffectType(activeEffects, CC_TYPES);
}

export function isSilenced(activeEffects: StatusEffect[]): boolean {
  return activeEffects.some(e => e.type === StatusEffectType.SILENCE);
}

export function isRooted(activeEffects: StatusEffect[]): boolean {
  return hasStatusEffectType(activeEffects, [StatusEffectType.ROOT, ...CC_TYPES]);
}

export interface StatValueTier {
  threshold: number;
  profTiers?: Array<{ threshold: number; values: Record<string, number> }>;
}

export interface StatTieredConfig {
  stat: string;
  proficiencyStat?: string;
  tiers: StatValueTier[];
}

export function resolveStatTieredValue(
  config: StatTieredConfig,
  statValue: number,
  profValue: number,
  resultKey: string
): number | null {
  const tiers = config.tiers;
  if (!tiers.length) return null;

  let matchedTier: StatValueTier | null = null;
  for (const tier of tiers) {
    if (statValue >= tier.threshold) {
      matchedTier = tier;
    } else {
      break;
    }
  }

  if (!matchedTier) {
    matchedTier = tiers[0];
  }

  if (!matchedTier.profTiers?.length) return null;

  const firstValue = matchedTier.profTiers[0].values[resultKey];
  if (firstValue === undefined) return null;

  let matchedProf = matchedTier.profTiers[0];
  for (const pt of matchedTier.profTiers) {
    if (profValue >= pt.threshold) {
      matchedProf = pt;
    } else {
      break;
    }
  }

  return matchedProf.values[resultKey] ?? firstValue;
}

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
  mpRestorePerTick?: { base: number; statScale?: string; statMultiplier?: number; proficiencyStat?: string; proficiencyMultiplier?: number };
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
  damageRedirect?: { targetId: string };
  blockChance?: number;
  consumableOnAttack?: boolean;
  cooldownReduction?: number;
  magicalDamageBonus?: number;
  damageNegation?: { base: number; spiScale: number; proficiencyCap: number; proficiencyStat: string };
  dodgeReduction?: number;
  accuracyBonus?: number;
  healingOverTime?: { base: number; spiScale: number; proficiencyStat: string };
  partyHeal?: number;
  healPercent?: number;
  mpDamage?: number;
  mpDamageAOE?: boolean;
  attackPowerMultiplierProficiency?: { baseStat: string; perProficiency: number; proficiencyStat: string };
  fear?: boolean;
  fearAOE?: boolean;
  songType?: 'green' | 'blue' | 'yellow' | 'red';
  delayExplosion?: { minSeconds: number; maxSeconds: number };
  preventResurrect?: boolean;
  preventFieldSpells?: boolean;
  consumableItem?: { itemId: string; quantity: number };
  createItems?: Array<{ itemId: string; quantity: number; consumeItems?: Array<{ itemId: string; quantity: number }> }>;
  sacrificeHeal?: boolean;
  dispelBuff?: boolean;
  dispelDebuff?: boolean;
  revealInvisible?: boolean;
  summonObject?: { objectType: string; duration: number; hp?: number; defense?: number; aoeDamage?: number };
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
  songDamageNegation?: { base: number; spiScale: number; proficiencyCap: number };
  statTieredValues?: StatTieredConfig;
  weaponAura?: {
    element: string;
    spiTiers?: Array<{ spi: number; min: number; max: number }>;
    formula?: 'toxify';
  };
  resistMods?: Record<string, number>;
  invisible?: { stationaryOnly: boolean; mpCostPerSec: number };
  barrierPhysical?: boolean;
  barrierMagical?: boolean;
  elementalAbsorption?: { elements: string[]; convertTo: 'hp' | 'mp' };
  removeResistBuffs?: string[];
  manaSwap?: boolean;
  soulSwap?: boolean;
  devotion?: boolean;
  magicalAid?: { mpRestorePercent: number };
  knockback?: { distance: number };
  misdirection?: boolean;
  extraHit?: boolean;
}

export interface BuffData {
  flatStats?: Partial<{ str: number; agi: number; int: number; spi: number; dex: number; sta: number }>;
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
  weaponAura?: { element: string; minDamage: number; maxDamage: number };
  resistMods?: Record<string, number>;
  critResistPercent?: number;
  critDamageReducePercent?: number;
  auraDamageReducePercent?: number;
  auraDamageIncreasePercent?: number;
  manaShield?: boolean;
  invisible?: { stationaryOnly: boolean; mpCostPerSec: number };
  barrierPhysical?: boolean;
  barrierMagical?: boolean;
  elementalAbsorption?: { elements: string[]; convertTo: 'hp' | 'mp' };
  devotionLink?: { partnerId: string };
  magicalAid?: { mpRestorePercent: number };
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
  healOverTime?: { hpPerTick: number; tickInterval: number };
  mpRestorePerTick?: { mpPerTick: number; tickInterval: number };
  fear?: boolean;
  delayExplosion?: { minMs: number; maxMs: number };
  preventResurrect?: boolean;
  preventFieldSpells?: boolean;
  blockingStance?: boolean;
  blockingRange?: number;
  defensiveMarch?: boolean;
  shieldCharge?: boolean;
  songType?: 'green' | 'blue' | 'yellow' | 'red';
  songRadius?: number;
  damageNegation?: { base: number; spiScale: number; proficiencyCap: number };
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
  fearDirection?: { x: number; y: number; z: number };
  invisible?: boolean;
  barrierType?: 'physical' | 'magical';
  knockbackVelocity?: { dx: number; dz: number; remaining: number };
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

export const STATUS_EFFECT_DEFS: Partial<Record<StatusEffectType, StatusEffectDefinition>> = {
  [StatusEffectType.POISON]: { type: StatusEffectType.POISON, duration: 10000, tickInterval: 2000, potency: 0, isDoT: true, isCC: false },
  [StatusEffectType.BURN]: { type: StatusEffectType.BURN, duration: 5000, tickInterval: 1000, potency: 0, isDoT: true, isCC: false },
  [StatusEffectType.FREEZE]: { type: StatusEffectType.FREEZE, duration: 3000, tickInterval: 0, potency: 0.5, isDoT: false, isCC: true },
  [StatusEffectType.STUN]: { type: StatusEffectType.STUN, duration: 2000, tickInterval: 0, potency: 0, isDoT: false, isCC: true },
  [StatusEffectType.SILENCE]: { type: StatusEffectType.SILENCE, duration: 5000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.SLEEP]: { type: StatusEffectType.SLEEP, duration: 8000, tickInterval: 0, potency: 0, isDoT: false, isCC: true },
  [StatusEffectType.KNOCKDOWN]: { type: StatusEffectType.KNOCKDOWN, duration: 2000, tickInterval: 0, potency: 0, isDoT: false, isCC: true },
  [StatusEffectType.CHARM]: { type: StatusEffectType.CHARM, duration: 5000, tickInterval: 0, potency: 0, isDoT: false, isCC: true },
  [StatusEffectType.BLEED]: { type: StatusEffectType.BLEED, duration: 8000, tickInterval: 2000, potency: 0, isDoT: true, isCC: false },
  [StatusEffectType.ROOT]: { type: StatusEffectType.ROOT, duration: 3000, tickInterval: 0, potency: 0, isDoT: false, isCC: true },
  [StatusEffectType.SLOW]: { type: StatusEffectType.SLOW, duration: 5000, tickInterval: 0, potency: 0.3, isDoT: false, isCC: false },
  [StatusEffectType.HASTE]: { type: StatusEffectType.HASTE, duration: 10000, tickInterval: 0, potency: 0.3, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_DEFENSE]: { type: StatusEffectType.BUFF_DEFENSE, duration: 480000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_CAST_SPEED]: { type: StatusEffectType.BUFF_CAST_SPEED, duration: 90000, tickInterval: 0, potency: 0.5, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_MAX_HP]: { type: StatusEffectType.BUFF_MAX_HP, duration: 480000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_MP_REGEN]: { type: StatusEffectType.BUFF_MP_REGEN, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_ATTACK]: { type: StatusEffectType.BUFF_ATTACK, duration: 480000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_PHYSICAL_REDUC]: { type: StatusEffectType.BUFF_PHYSICAL_REDUC, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_STAT]: { type: StatusEffectType.BUFF_STAT, duration: 480000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_DODGE]: { type: StatusEffectType.BUFF_DODGE, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_ACCURACY]: { type: StatusEffectType.BUFF_ACCURACY, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_ATTACK_SPEED]: { type: StatusEffectType.BUFF_ATTACK_SPEED, duration: 480000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_GENERIC]: { type: StatusEffectType.BUFF_GENERIC, duration: 300000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.SEVERE_POISON]: { type: StatusEffectType.SEVERE_POISON, duration: 30000, tickInterval: 3000, potency: 0, isDoT: true, isCC: false },
  [StatusEffectType.MP_DRAIN]: { type: StatusEffectType.MP_DRAIN, duration: 30000, tickInterval: 3000, potency: 0, isDoT: true, isCC: false },
  [StatusEffectType.DEBUFF_DAMAGE_DOWN]: { type: StatusEffectType.DEBUFF_DAMAGE_DOWN, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.DEBUFF_DEFENSE_DOWN]: { type: StatusEffectType.DEBUFF_DEFENSE_DOWN, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.DEBUFF_SPEED_DOWN]: { type: StatusEffectType.DEBUFF_SPEED_DOWN, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.DEBUFF_ACCURACY_DOWN]: { type: StatusEffectType.DEBUFF_ACCURACY_DOWN, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.DEBUFF_DODGE_DOWN]: { type: StatusEffectType.DEBUFF_DODGE_DOWN, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.DEBUFF_CAST_SPEED_DOWN]: { type: StatusEffectType.DEBUFF_CAST_SPEED_DOWN, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.DEBUFF_DAMAGE_TAKEN_UP]: { type: StatusEffectType.DEBUFF_DAMAGE_TAKEN_UP, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.WEAPON_AURA]: { type: StatusEffectType.WEAPON_AURA, duration: 480000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_RESIST]: { type: StatusEffectType.BUFF_RESIST, duration: 30000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_CRIT_RESIST]: { type: StatusEffectType.BUFF_CRIT_RESIST, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_CRIT_DAMAGE_REDUCE]: { type: StatusEffectType.BUFF_CRIT_DAMAGE_REDUCE, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_AURA_DAMAGE_REDUCE]: { type: StatusEffectType.BUFF_AURA_DAMAGE_REDUCE, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_MANA_SHIELD]: { type: StatusEffectType.BUFF_MANA_SHIELD, duration: 999999999, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_SPELL_INTERRUPT_RESIST]: { type: StatusEffectType.BUFF_SPELL_INTERRUPT_RESIST, duration: 80000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_DEBUFF_RESIST]: { type: StatusEffectType.BUFF_DEBUFF_RESIST, duration: 15000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_DAMAGE_REDIRECT]: { type: StatusEffectType.BUFF_DAMAGE_REDIRECT, duration: 300000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_BLOCK_CHANCE]: { type: StatusEffectType.BUFF_BLOCK_CHANCE, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_BLOCKING_STANCE]: { type: StatusEffectType.BUFF_BLOCKING_STANCE, duration: 999999999, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_BLOCKING_PROTECTED]: { type: StatusEffectType.BUFF_BLOCKING_PROTECTED, duration: 999999999, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_CONSUMABLE_ON_ATTACK]: { type: StatusEffectType.BUFF_CONSUMABLE_ON_ATTACK, duration: 120000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_GUARDED]: { type: StatusEffectType.BUFF_GUARDED, duration: 300000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_DAMAGE_NEGATION]: { type: StatusEffectType.BUFF_DAMAGE_NEGATION, duration: 5000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_MOVE_SPEED]: { type: StatusEffectType.BUFF_MOVE_SPEED, duration: 2000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.SONG_GREEN]: { type: StatusEffectType.SONG_GREEN, duration: 999999999, tickInterval: 3000, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.SONG_BLUE]: { type: StatusEffectType.SONG_BLUE, duration: 999999999, tickInterval: 3000, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.SONG_YELLOW]: { type: StatusEffectType.SONG_YELLOW, duration: 999999999, tickInterval: 3000, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.SONG_RED]: { type: StatusEffectType.SONG_RED, duration: 999999999, tickInterval: 3000, potency: 0, isDoT: false, isCC: true },
  [StatusEffectType.SONG_ACTIVE]: { type: StatusEffectType.SONG_ACTIVE, duration: 999999999, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.FEAR]: { type: StatusEffectType.FEAR, duration: 2000, tickInterval: 0, potency: 0, isDoT: true, isCC: true },
  [StatusEffectType.CURSE]: { type: StatusEffectType.CURSE, duration: 60000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.PREVENT_FIELD_SPELLS]: { type: StatusEffectType.PREVENT_FIELD_SPELLS, duration: 60000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.PREVENT_RESSURECT]: { type: StatusEffectType.PREVENT_RESSURECT, duration: 60000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.MP_DAMAGE_DEBUFF]: { type: StatusEffectType.MP_DAMAGE_DEBUFF, duration: 10000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.INVISIBLE]: { type: StatusEffectType.INVISIBLE, duration: 999999999, tickInterval: 1000, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BARRIER_PHYSICAL]: { type: StatusEffectType.BARRIER_PHYSICAL, duration: 30000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BARRIER_MAGICAL]: { type: StatusEffectType.BARRIER_MAGICAL, duration: 30000, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
  [StatusEffectType.BUFF_OBELISK]: { type: StatusEffectType.BUFF_OBELISK, duration: 999999999, tickInterval: 0, potency: 0, isDoT: false, isCC: false },
};

const STAT_TO_COMBAT: Record<string, (stat: number, stats: EffectiveStats) => void> = {
  str: (v, s) => { s.attack += Math.floor(v * 1.5); },
  int: (v, s) => { s.magicAttack += Math.floor(v * 1.5); },
  sta: (v, s) => { s.maxHealth += Math.floor(v * 0.8); },
  spi: (v, s) => { s.maxMana += Math.floor(v * 0.8); },
  agi: (v, s) => { s.speed += Math.floor(v * 0.5); },
};

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

const ROOT_TYPES = new Set([StatusEffectType.ROOT, StatusEffectType.FREEZE, StatusEffectType.STUN]);

export function getEffectiveStats(
  baseStats: { attack: number; defense: number; magicAttack: number; maxHealth: number; maxMana: number; speed: number },
  statPoints: { STR: number; AGI: number; INT: number; SPI: number; DEX: number; STA: number },
  statusEffects: StatusEffect[]
): { attack: number; defense: number; magicAttack: number; maxHealth: number; maxMana: number; speed: number; speedMultiplier: number; physicalDamageReduction: number; dodgeBonus: number; accuracyBonus: number; castTimeReduction: number; attackSpeedMultiplier: number; damageTakenMultiplier: number; castSpeedPenalty: number; auraDamageMultiplier: number; healPercent: number } {
  const s: EffectiveStats = {
    attack: baseStats.attack,
    defense: baseStats.defense,
    magicAttack: baseStats.magicAttack,
    maxHealth: baseStats.maxHealth,
    maxMana: baseStats.maxMana,
    speed: baseStats.speed,
    physicalDamageReduction: 0,
    dodgeBonus: 0,
    accuracyBonus: 0,
    castTimeReduction: 0,
    attackSpeedMultiplier: 1.0,
    damageTakenMultiplier: 1.0,
    castSpeedPenalty: 0,
    speedMultiplier: 1,
    auraDamageMultiplier: 1,
    healPercent: 0,
  };

  const now = Date.now();

  for (const effect of statusEffects) {
    if (effect.appliedAt + effect.duration < now) continue;

    switch (effect.type) {
      case StatusEffectType.BUFF_ATTACK:
        s.attack = Math.floor(s.attack * effect.potency);
        break;
      case StatusEffectType.BUFF_DEFENSE:
        if (effect.buffData?.flatDefense) s.defense += effect.buffData.flatDefense;
        if (effect.buffData?.defenseMultiplier) s.defense = Math.floor(s.defense * effect.buffData.defenseMultiplier);
        break;
      case StatusEffectType.BUFF_MAX_HP:
        if (effect.buffData?.maxHpFlat) s.maxHealth += effect.buffData.maxHpFlat;
        if (effect.buffData?.maxHpPercent) s.maxHealth += Math.floor(baseStats.maxHealth * effect.buffData.maxHpPercent);
        break;
      case StatusEffectType.BUFF_CAST_SPEED:
        s.castTimeReduction += effect.potency;
        break;
      case StatusEffectType.BUFF_PHYSICAL_REDUC:
        s.physicalDamageReduction += effect.potency;
        break;
      case StatusEffectType.BUFF_DODGE:
        s.dodgeBonus += effect.potency;
        break;
      case StatusEffectType.BUFF_ACCURACY:
        s.accuracyBonus += effect.potency;
        break;
      case StatusEffectType.BUFF_ATTACK_SPEED:
        s.attackSpeedMultiplier *= (1 + effect.potency);
        break;
      case StatusEffectType.BUFF_STAT:
        if (effect.buffData?.flatStats) {
          for (const [stat, val] of Object.entries(effect.buffData.flatStats)) {
            STAT_TO_COMBAT[stat]?.(val, s);
          }
        }
        break;
      case StatusEffectType.BUFF_GENERIC:
        if (effect.buffData) {
          const bd = effect.buffData;
          if (bd.flatDefense) s.defense += bd.flatDefense;
          if (bd.defenseMultiplier) s.defense = Math.floor(s.defense * bd.defenseMultiplier);
          if (bd.flatStats) {
            for (const [stat, val] of Object.entries(bd.flatStats)) {
              STAT_TO_COMBAT[stat]?.(val, s);
            }
          }
          if (bd.physicalDamageReductionPercent) s.physicalDamageReduction += bd.physicalDamageReductionPercent;
          if (bd.dodgeFlat) s.dodgeBonus += bd.dodgeFlat;
          if (bd.accuracyFlat) s.accuracyBonus += bd.accuracyFlat;
          if (bd.castTimeReductionPercent) s.castTimeReduction += bd.castTimeReductionPercent;
          if (bd.attackSpeedPercent) s.attackSpeedMultiplier *= (1 + bd.attackSpeedPercent);
          if (bd.magicalDamageBonusPercent) s.magicAttack = Math.floor(s.magicAttack * (1 + bd.magicalDamageBonusPercent));
          if (bd.auraDamageIncreasePercent) s.auraDamageMultiplier *= (1 + bd.auraDamageIncreasePercent);
          if (bd.healPercent) s.healPercent += bd.healPercent;
        }
        break;
      case StatusEffectType.DEBUFF_DAMAGE_DOWN:
        s.attack = Math.floor(s.attack * (1 - (effect.potency || 0)));
        break;
      case StatusEffectType.DEBUFF_DEFENSE_DOWN:
        s.defense = Math.floor(s.defense * (1 - (effect.potency || 0)));
        break;
      case StatusEffectType.DEBUFF_SPEED_DOWN:
      case StatusEffectType.SLOW:
        s.speed = Math.floor(s.speed * (1 - (effect.potency || 0)));
        s.speedMultiplier *= (1 - (effect.potency || 0));
        break;
      case StatusEffectType.DEBUFF_ACCURACY_DOWN:
        s.accuracyBonus -= Math.floor(100 * (effect.potency || 0));
        break;
      case StatusEffectType.DEBUFF_DODGE_DOWN:
        s.dodgeBonus = Math.floor(s.dodgeBonus * (1 - (effect.potency || 0)));
        break;
      case StatusEffectType.DEBUFF_CAST_SPEED_DOWN:
        s.castSpeedPenalty += (effect.potency || 0);
        break;
      case StatusEffectType.DEBUFF_DAMAGE_TAKEN_UP:
        s.damageTakenMultiplier *= (1 + (effect.potency || 0));
        break;
      case StatusEffectType.BUFF_MOVE_SPEED:
        s.speedMultiplier += (effect.potency || 0);
        break;
      case StatusEffectType.ROOT:
      case StatusEffectType.FREEZE:
      case StatusEffectType.STUN:
        s.speedMultiplier = 0;
        break;
      case StatusEffectType.SONG_GREEN:
      case StatusEffectType.SONG_BLUE:
      case StatusEffectType.SONG_YELLOW:
      case StatusEffectType.SONG_RED:
        if (!effect.songProximityBuff) {
          s.speedMultiplier *= 0.15;
        }
        break;
    }
  }

  return {
    attack: s.attack,
    defense: s.defense,
    magicAttack: s.magicAttack,
    maxHealth: s.maxHealth,
    maxMana: s.maxMana,
    speed: s.speed,
    speedMultiplier: s.speedMultiplier,
    physicalDamageReduction: s.physicalDamageReduction,
    dodgeBonus: s.dodgeBonus,
    accuracyBonus: s.accuracyBonus,
    castTimeReduction: s.castTimeReduction,
    attackSpeedMultiplier: s.attackSpeedMultiplier,
    damageTakenMultiplier: s.damageTakenMultiplier,
    castSpeedPenalty: s.castSpeedPenalty,
    auraDamageMultiplier: s.auraDamageMultiplier,
    healPercent: s.healPercent,
  };
}

export interface EnhancementBonus {
  attack: number;
  defense: number;
  health: number;
  magicAttackPercent: number;
  dodge: number;
}

export interface StatBonusBreakdown {
  gear: { STA: number; STR: number; AGI: number; DEX: number; SPI: number; INT: number };
  buffs: { STA: number; STR: number; AGI: number; DEX: number; SPI: number; INT: number };
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

export function computeStatBreakdown(
  statPoints: { STA: number; STR: number; AGI: number; DEX: number; SPI: number; INT: number },
  statusEffects: StatusEffect[],
  gearBonuses: { STA: number; STR: number; AGI: number; DEX: number; SPI: number; INT: number },
  gearCombat?: { accuracy: number; dodge: number; attackSpeed: number; fireResist: number; iceResist: number; lightningResist: number; poisonResist: number; darkResist: number; holyResist: number; ailmentResist: number; disorderResist: number; stunResist: number; tripResist: number; freezeResist: number; burnResist: number; curseResist: number; bleedResist: number; sleepResist: number; weaknessResist: number; weakenResist: number; knockdownResist: number; knockbackResist: number }
): StatBonusBreakdown {
  const buffs = { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };

  for (const effect of statusEffects) {
    const bd = effect.buffData;
    if (!bd?.flatStats) continue;
    if (bd.flatStats.sta) buffs.STA += bd.flatStats.sta;
    if (bd.flatStats.str) buffs.STR += bd.flatStats.str;
    if (bd.flatStats.agi) buffs.AGI += bd.flatStats.agi;
    if (bd.flatStats.spi) buffs.SPI += bd.flatStats.spi;
    if (bd.flatStats.int) buffs.INT += bd.flatStats.int;
    if (bd.flatStats.dex) buffs.DEX += bd.flatStats.dex;
  }

  return { gear: { ...gearBonuses }, buffs, gearCombat: gearCombat || undefined };
}
