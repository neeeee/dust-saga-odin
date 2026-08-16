"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SkillAnimationType = void 0;
exports.getSkillAnimationName = getSkillAnimationName;
exports.getCategoryForSubCategory = getCategoryForSubCategory;
exports.getCategoryColor = getCategoryColor;
var SkillAnimationType;
(function (SkillAnimationType) {
    SkillAnimationType["SLASH"] = "Slash";
    SkillAnimationType["THRUST"] = "Thrust";
    SkillAnimationType["CLEAVE"] = "Cleave";
    SkillAnimationType["BASH"] = "Bash";
    SkillAnimationType["DEFEND"] = "Block";
    SkillAnimationType["SHOOT"] = "Shoot";
    SkillAnimationType["CAST"] = "Cast";
    SkillAnimationType["HEAL"] = "CastHeal";
    SkillAnimationType["DASH"] = "Dash";
    SkillAnimationType["BUFF"] = "CastBuff";
    SkillAnimationType["THROW"] = "Throw";
    SkillAnimationType["ROAR"] = "Roar";
    SkillAnimationType["CHARGE"] = "Charge";
    SkillAnimationType["TRIP"] = "Trip";
    SkillAnimationType["GENERIC"] = "Attack";
})(SkillAnimationType || (exports.SkillAnimationType = SkillAnimationType = {}));
const SUB_CATEGORY_ANIMATIONS = {
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
const SKILL_NAME_OVERRIDES = {
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
function getSkillAnimationName(skillName, subCategory, castTime, isPassive) {
    if (isPassive)
        return '';
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
function getCategoryForSubCategory(subCategoryId) {
    if (subCategoryId >= 1 && subCategoryId <= 5)
        return 'melee';
    if (subCategoryId >= 7 && subCategoryId <= 11)
        return 'technique';
    if (subCategoryId >= 13 && subCategoryId <= 16)
        return 'prayer';
    if (subCategoryId >= 18 && subCategoryId <= 21)
        return 'magic';
    if (subCategoryId >= 23 && subCategoryId <= 24)
        return 'special';
    return 'melee';
}
function getCategoryColor(category) {
    const colors = {
        melee: '#c0392b',
        technique: '#27ae60',
        prayer: '#f39c12',
        magic: '#8e44ad',
        special: '#16a085',
    };
    return colors[category] || '#666';
}
