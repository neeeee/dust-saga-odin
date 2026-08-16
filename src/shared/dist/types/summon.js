"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BANISH_RADIUS = exports.SUMMON_STATS = exports.MAX_PLANTS = exports.COMBAT_SUMMON_TYPES = exports.SummonType = void 0;
var SummonType;
(function (SummonType) {
    SummonType["WALL"] = "wall";
    SummonType["PLANT"] = "plant";
    SummonType["WYVERN"] = "wyvern";
    SummonType["TURTLE"] = "turtle";
})(SummonType || (exports.SummonType = SummonType = {}));
exports.COMBAT_SUMMON_TYPES = [SummonType.PLANT, SummonType.WYVERN, SummonType.TURTLE];
exports.MAX_PLANTS = 2;
exports.SUMMON_STATS = {
    [SummonType.WALL]: { hp: 5000, defense: 500, attackDamage: 0, attackRange: 0, attackCooldown: 0, speed: 0 },
    [SummonType.PLANT]: { hp: 500, defense: 50, attackDamage: 50, attackRange: 8, attackCooldown: 3, speed: 0 },
    [SummonType.WYVERN]: { hp: 800, defense: 100, attackDamage: 500, attackRange: 5, attackCooldown: 3, speed: 3 },
    [SummonType.TURTLE]: { hp: 1200, defense: 200, attackDamage: 300, attackRange: 6, attackCooldown: 5, speed: 0 },
};
exports.BANISH_RADIUS = 5;
