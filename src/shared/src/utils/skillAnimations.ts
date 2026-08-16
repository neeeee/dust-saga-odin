export enum SkillAnimationType {
  SLASH = 'Slash',
  THRUST = 'Thrust',
  CLEAVE = 'Cleave',
  BASH = 'Bash',
  DEFEND = 'Block',
  SHOOT = 'Shoot',
  CAST = 'Cast',
  HEAL = 'CastHeal',
  DASH = 'Dash',
  BUFF = 'CastBuff',
  THROW = 'Throw',
  ROAR = 'Roar',
  CHARGE = 'Charge',
  TRIP = 'Trip',
  GENERIC = 'Attack',
}

const SUB_CATEGORY_ANIMATIONS: Record<string, SkillAnimationType> = {
  Slash: SkillAnimationType.SLASH,
  Thrust: SkillAnimationType.THRUST,
  Cleave: SkillAnimationType.CLEAVE,
  Bash: SkillAnimationType.BASH,
  Defend: SkillAnimationType.DEFEND,
  Shot: SkillAnimationType.SHOOT,
  Dodge: SkillAnimationType.DASH,
  Grace: SkillAnimationType.HEAL,
  Blessing: SkillAnimationType.BUFF,
  Exorcism: SkillAnimationType.CAST,
  Hymn: SkillAnimationType.CAST,
  Elemental: SkillAnimationType.CAST,
  Invocation: SkillAnimationType.CAST,
  Darkness: SkillAnimationType.CAST,
  Confusion: SkillAnimationType.CAST,
  Racial: SkillAnimationType.GENERIC,
  Horsemanship: SkillAnimationType.CHARGE,
  Alchemy: SkillAnimationType.CAST,
  Assassination: SkillAnimationType.SLASH,
  Trap: SkillAnimationType.THROW,
};

const SKILL_NAME_OVERRIDES: Record<string, SkillAnimationType> = {
  'Backstep': SkillAnimationType.DASH,
  'Dash': SkillAnimationType.DASH,
  'Quick Step': SkillAnimationType.DASH,
  'Sprint': SkillAnimationType.DASH,
  'Spurt': SkillAnimationType.DASH,
  'Rush': SkillAnimationType.CHARGE,
  'Shield Charge': SkillAnimationType.CHARGE,
  'Assault': SkillAnimationType.CHARGE,
  'Whirling Strike': SkillAnimationType.CLEAVE,
  'True Whirling Strike': SkillAnimationType.CLEAVE,
  'Full Swing': SkillAnimationType.CLEAVE,
  'Swing': SkillAnimationType.CLEAVE,
  'Roar': SkillAnimationType.ROAR,
  'Dagger Throw': SkillAnimationType.THROW,
  'Spear Volley': SkillAnimationType.THROW,
  'Shield Bash': SkillAnimationType.BASH,
  'Parry': SkillAnimationType.DEFEND,
  'Blocking': SkillAnimationType.DEFEND,
  'Riposte': SkillAnimationType.DEFEND,
  'Parapet': SkillAnimationType.DEFEND,
  'Auto-guard': SkillAnimationType.DEFEND,
  'Defensive March': SkillAnimationType.DEFEND,
  'Backstab': SkillAnimationType.SLASH,
  'Blindside': SkillAnimationType.SLASH,
  'Pierce Armor': SkillAnimationType.THRUST,
  'Triple Stab': SkillAnimationType.THRUST,
  'Quadruple Stab': SkillAnimationType.THRUST,
  'Slice': SkillAnimationType.SLASH,
  'Dice': SkillAnimationType.SLASH,
  'Clobber': SkillAnimationType.CLEAVE,
  'Split': SkillAnimationType.CLEAVE,
  'Stun': SkillAnimationType.BASH,
  'Ground Shock': SkillAnimationType.BASH,
  'Stun Hammer': SkillAnimationType.BASH,
};

export function getSkillAnimationName(
  skillName: string,
  subCategory: string,
  castTime: number,
  isPassive: boolean
): string {
  if (isPassive) return '';

  if (SKILL_NAME_OVERRIDES[skillName]) {
    return SKILL_NAME_OVERRIDES[skillName];
  }

  if (castTime > 0) {
    return SkillAnimationType.CAST;
  }

  if (SUB_CATEGORY_ANIMATIONS[subCategory]) {
    return SUB_CATEGORY_ANIMATIONS[subCategory];
  }

  return SkillAnimationType.GENERIC;
}

export function getCategoryForSubCategory(subCategoryId: number): string {
  if (subCategoryId >= 1 && subCategoryId <= 5) return 'melee';
  if (subCategoryId >= 7 && subCategoryId <= 11) return 'technique';
  if (subCategoryId >= 13 && subCategoryId <= 16) return 'prayer';
  if (subCategoryId >= 18 && subCategoryId <= 21) return 'magic';
  if (subCategoryId >= 23 && subCategoryId <= 24) return 'special';
  return 'melee';
}

export function getCategoryColor(category: string): string {
  const colors: Record<string, string> = {
    melee: '#c0392b',
    technique: '#27ae60',
    prayer: '#f39c12',
    magic: '#8e44ad',
    special: '#16a085',
  };
  return colors[category] || '#666';
}
