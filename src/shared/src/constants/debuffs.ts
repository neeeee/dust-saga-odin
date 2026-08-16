export type DebuffDOTType = 'poison' | 'severe_poison' | 'bleed' | 'mp_drain';

export type DebuffCategory = 'ailment' | 'disorder' | 'stun' | 'trip' | 'freeze' | 'burn' | 'curse' | 'bleed' | 'sleep' | 'weakness' | 'weaken' | 'knockdown' | 'knockback';

export interface DebuffEffectTable {
  debuffCategory?: DebuffCategory;
  dot?: DebuffDOTType;
  dotPotency?: number;
  dotHPPercent?: number;
  dotTickInterval?: number;
  dotMpDrain?: number;
  dotSPIBase?: number;
  dotSPIMax?: number;
  dotSPICap?: number;
  attackDown?: number;
  defenseDown?: number;
  speedDown?: number;
  accuracyDown?: number;
  castSpeedDown?: number;
  damageTakenUp?: number;
  moveSpeedDown?: number;
  dodgeDown?: number;
  mpDamage?: number;
  mpDamageDirect?: boolean;
  hasFreeze?: { duration: number };
  hasSleep?: { duration: number };
  hasStun?: { duration: number };
  hasSilence?: { duration: number };
  hasKnockback?: {
    knockbackDistance: number;
  };
  preventEquipment?: {
    equipmentSlotDisabled: string;
  };
  consumable?: boolean;
  preventFieldSpells?: boolean;
  preventSpellCast?: boolean;
  preventResurrect?: boolean;
  curse?: boolean;
  revealInvisible?: boolean;
  disablePhysicalAttacks?: boolean;
  attackHalved?: boolean;
  removeResistBuffs?: string[];
}
