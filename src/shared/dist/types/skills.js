"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SKILL_TARGET_RULES = exports.BENEFICIAL_SKILL_TYPES = exports.SkillType = exports.SkillTargetType = exports.AOETargetMode = exports.MagicalDamageSubType = exports.PhysicalDamageSubType = exports.DamageType = exports.SkillCategoryId = void 0;
exports.isBeneficialSkillType = isBeneficialSkillType;
exports.isPassiveSkill = isPassiveSkill;
exports.getSkillTargetType = getSkillTargetType;
exports.meetsRequirements = meetsRequirements;
exports.getRequiredProficiency = getRequiredProficiency;
var SkillCategoryId;
(function (SkillCategoryId) {
    SkillCategoryId[SkillCategoryId["MELEE"] = 0] = "MELEE";
    SkillCategoryId[SkillCategoryId["TECHNIQUE"] = 6] = "TECHNIQUE";
    SkillCategoryId[SkillCategoryId["PRAYER"] = 12] = "PRAYER";
    SkillCategoryId[SkillCategoryId["MAGIC"] = 17] = "MAGIC";
    SkillCategoryId[SkillCategoryId["SPECIAL"] = 22] = "SPECIAL";
})(SkillCategoryId || (exports.SkillCategoryId = SkillCategoryId = {}));
var DamageType;
(function (DamageType) {
    DamageType["PHYSICAL"] = "physical";
    DamageType["MAGICAL"] = "magical";
})(DamageType || (exports.DamageType = DamageType = {}));
var PhysicalDamageSubType;
(function (PhysicalDamageSubType) {
    PhysicalDamageSubType["SLASH"] = "slash";
    PhysicalDamageSubType["THRUST"] = "thrust";
    PhysicalDamageSubType["CLEAVE"] = "cleave";
    PhysicalDamageSubType["BASH"] = "bash";
    PhysicalDamageSubType["RANGED"] = "ranged";
})(PhysicalDamageSubType || (exports.PhysicalDamageSubType = PhysicalDamageSubType = {}));
var MagicalDamageSubType;
(function (MagicalDamageSubType) {
    MagicalDamageSubType["FIRE"] = "fire";
    MagicalDamageSubType["ICE"] = "ice";
    MagicalDamageSubType["LIGHTNING"] = "lightning";
    MagicalDamageSubType["DARK"] = "dark";
    MagicalDamageSubType["HOLY"] = "holy";
    MagicalDamageSubType["POISON"] = "poison";
})(MagicalDamageSubType || (exports.MagicalDamageSubType = MagicalDamageSubType = {}));
var AOETargetMode;
(function (AOETargetMode) {
    AOETargetMode["SELF_CENTERED"] = "self_centered";
    AOETargetMode["TARGET_CENTERED"] = "target_centered";
    AOETargetMode["GROUND_TARGETED"] = "ground_targeted";
    AOETargetMode["CONE"] = "cone";
})(AOETargetMode || (exports.AOETargetMode = AOETargetMode = {}));
var SkillTargetType;
(function (SkillTargetType) {
    SkillTargetType["SELF"] = "self";
    SkillTargetType["SELF_OR_TARGET"] = "self_or_target";
    SkillTargetType["PARTY"] = "party";
    SkillTargetType["OTHER_ONLY"] = "other_only";
})(SkillTargetType || (exports.SkillTargetType = SkillTargetType = {}));
var SkillType;
(function (SkillType) {
    SkillType["DAMAGE_PHYSICAL"] = "damage_physical";
    SkillType["DAMAGE_MAGICAL"] = "damage_magical";
    SkillType["HEAL"] = "heal";
    SkillType["HEAL_OVER_TIME"] = "heal_over_time";
    SkillType["PARTY_HEAL"] = "party_heal";
    SkillType["HP_BUFF"] = "hp_buff";
    SkillType["MP_RESTORE"] = "mp_restore";
    SkillType["DRAIN_LIFE"] = "drain_life";
    SkillType["SACRIFICE_HEAL"] = "sacrifice_heal";
    SkillType["REVIVE"] = "revive";
    SkillType["BUFF"] = "buff";
    SkillType["DEBUFF"] = "debuff";
    SkillType["SONG"] = "song";
    SkillType["CRAFT"] = "craft";
    SkillType["UTILITY"] = "utility";
    SkillType["SUMMON"] = "summon";
    SkillType["FIELD_SPELL"] = "field_spell";
    SkillType["MP_DAMAGE"] = "mp_damage";
    SkillType["DISPEL"] = "dispel";
    SkillType["FEAR"] = "fear";
    SkillType["PASSIVE"] = "passive";
    SkillType["PROVOKE"] = "provoke";
    SkillType["INVISIBILITY"] = "invisibility";
    SkillType["BARRIER"] = "barrier";
    SkillType["MANA_SHIELD"] = "mana_shield";
    SkillType["ABSORPTION"] = "absorption";
    SkillType["MANA_SWAP"] = "mana_swap";
    SkillType["SOUL_SWAP"] = "soul_swap";
    SkillType["DEVOTION"] = "devotion";
    SkillType["KNOCKBACK"] = "knockback";
})(SkillType || (exports.SkillType = SkillType = {}));
// Skill types that may be freely cast on other players in non-PvP zones
// (buffs, heals, revives, and other purely beneficial effects).
exports.BENEFICIAL_SKILL_TYPES = new Set([
    SkillType.HEAL,
    SkillType.HEAL_OVER_TIME,
    SkillType.PARTY_HEAL,
    SkillType.HP_BUFF,
    SkillType.MP_RESTORE,
    SkillType.SACRIFICE_HEAL,
    SkillType.REVIVE,
    SkillType.BUFF,
    SkillType.BARRIER,
    SkillType.MANA_SHIELD,
    SkillType.ABSORPTION,
    SkillType.MANA_SWAP,
    SkillType.SOUL_SWAP,
    SkillType.DEVOTION,
    SkillType.SONG,
    SkillType.DISPEL,
]);
function isBeneficialSkillType(type) {
    return exports.BENEFICIAL_SKILL_TYPES.has(type);
}
exports.SKILL_TARGET_RULES = {
    // Melee self buffs
    'Ossify': SkillTargetType.SELF,
    'Concentration': SkillTargetType.SELF,
    // Defensive self buffs
    'Providence': SkillTargetType.PARTY,
    'Quick Step': SkillTargetType.SELF,
    'Avoidance': SkillTargetType.SELF,
    'Mana Shield': SkillTargetType.SELF,
    'Clear Mind': SkillTargetType.SELF,
    'Elemental Absorption': SkillTargetType.SELF,
    'Parapet': SkillTargetType.SELF,
    'Auto-guard': SkillTargetType.SELF,
    'Defensive March': SkillTargetType.SELF,
    'Guardian': SkillTargetType.OTHER_ONLY,
    // Offensive self buffs
    'Toxify': SkillTargetType.SELF,
    'Rush': SkillTargetType.SELF,
    'Gloom': SkillTargetType.SELF,
    'Raging Soul': SkillTargetType.SELF,
    'War Cry': SkillTargetType.SELF,
    'Lunge': SkillTargetType.SELF,
    'Desperado': SkillTargetType.SELF,
    'Magical Aid': SkillTargetType.SELF,
    'Skill Focus': SkillTargetType.SELF,
    // Enchanter song buffs
    'Green Song': SkillTargetType.SELF,
    'Blue Song': SkillTargetType.SELF,
    'Red Song': SkillTargetType.SELF,
    'Yellow Song': SkillTargetType.SELF,
    // Scout buffs
    'Hide': SkillTargetType.SELF,
    'Snipers Nest': SkillTargetType.SELF,
    'Watchful Eye': SkillTargetType.SELF,
    'Horse Archer': SkillTargetType.SELF,
    'Cloak': SkillTargetType.SELF,
    'Invigorate': SkillTargetType.SELF,
    'Sprint': SkillTargetType.SELF,
    'Spurt': SkillTargetType.SELF,
    'Bolster': SkillTargetType.SELF_OR_TARGET,
    'Accelerate': SkillTargetType.SELF_OR_TARGET,
    'Move Stream': SkillTargetType.PARTY,
    'Dash': SkillTargetType.SELF,
    // Elemental resistances
    'Resist Fire': SkillTargetType.SELF_OR_TARGET,
    'Resist Ice': SkillTargetType.SELF_OR_TARGET,
    'Resist Lightning': SkillTargetType.SELF_OR_TARGET,
    'Resist Malice': SkillTargetType.SELF_OR_TARGET,
    'Resist Charm': SkillTargetType.SELF_OR_TARGET,
    // Ascetic buffs
    'Bless Weapon': SkillTargetType.SELF_OR_TARGET,
    'Mana Restore': SkillTargetType.SELF_OR_TARGET,
    'Speedy Gale': SkillTargetType.PARTY,
    'Devotion': SkillTargetType.OTHER_ONLY,
    'Mental Aid': SkillTargetType.SELF_OR_TARGET,
    'Third Eye': SkillTargetType.PARTY,
    'Physical Barrier': SkillTargetType.SELF_OR_TARGET,
    'Magical Barrier': SkillTargetType.SELF_OR_TARGET,
    // Prayer 
    'Lapis Mediow': SkillTargetType.PARTY,
    'Group Barrier': SkillTargetType.PARTY,
    'Tranquil Mind': SkillTargetType.PARTY,
    'Divine Aid': SkillTargetType.PARTY,
    'Restoration': SkillTargetType.PARTY,
    'Regenerate': SkillTargetType.SELF_OR_TARGET,
    'Velox': SkillTargetType.SELF_OR_TARGET,
    'Battle Prayer': SkillTargetType.SELF_OR_TARGET,
    'Enchantment': SkillTargetType.SELF_OR_TARGET,
    'Saltio': SkillTargetType.OTHER_ONLY,
    'Revive': SkillTargetType.OTHER_ONLY,
    'Locomitigation': SkillTargetType.SELF_OR_TARGET,
    'Spirit Protection': SkillTargetType.SELF_OR_TARGET,
    // Debuffs
    'Poison': SkillTargetType.OTHER_ONLY,
    'Mind Venom': SkillTargetType.OTHER_ONLY,
    'Weakness': SkillTargetType.OTHER_ONLY,
    'Weaken': SkillTargetType.OTHER_ONLY,
    'Undermine': SkillTargetType.OTHER_ONLY,
    'Impedimentia': SkillTargetType.OTHER_ONLY,
    'Tangled Fingers': SkillTargetType.OTHER_ONLY,
    'Befuddle': SkillTargetType.OTHER_ONLY,
};
function isPassiveSkill(skill) {
    if (skill.skillType === SkillType.PASSIVE)
        return true;
    if ('isPassive' in skill && skill.isPassive)
        return true;
    if ('name' in skill && skill.name.includes('(Passive)'))
        return true;
    return false;
}
function getSkillTargetType(skill) {
    if ('skillType' in skill && skill.skillType) {
        switch (skill.skillType) {
            case SkillType.REVIVE:
            case SkillType.DEBUFF:
            case SkillType.DAMAGE_PHYSICAL:
            case SkillType.DAMAGE_MAGICAL:
            case SkillType.DISPEL:
            case SkillType.MP_DAMAGE:
            case SkillType.FEAR:
            case SkillType.SONG:
                return SkillTargetType.OTHER_ONLY;
            case SkillType.HEAL:
            case SkillType.PARTY_HEAL:
                return SkillTargetType.PARTY;
            case SkillType.BUFF:
            case SkillType.HEAL_OVER_TIME:
            case SkillType.HP_BUFF:
            case SkillType.MP_RESTORE:
            case SkillType.DRAIN_LIFE:
            case SkillType.SACRIFICE_HEAL:
                return SkillTargetType.SELF;
            case SkillType.CRAFT:
            case SkillType.SUMMON:
            case SkillType.UTILITY:
            case SkillType.FIELD_SPELL:
                return undefined;
        }
    }
    return undefined;
}
function meetsRequirements(reqPoints, getSkillPoints) {
    if (typeof reqPoints === 'number')
        return true;
    return reqPoints.every(r => getSkillPoints(r.skillName) >= r.points);
}
function getRequiredProficiency(reqPoints) {
    if (typeof reqPoints === 'number')
        return reqPoints;
    return Math.max(...reqPoints.map(r => r.points));
}
