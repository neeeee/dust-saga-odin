"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.LOOT_DESPAWN_MS = exports.LOOT_ASSIGNMENT_DURATION_MS = exports.MAX_LOOT_POOL = exports.MAX_PARTY_SIZE = exports.PartyVisibility = exports.LootRule = void 0;
exports.normalizeLootRule = normalizeLootRule;
var LootRule;
(function (LootRule) {
    LootRule["FFA"] = "ffa";
    LootRule["ROUND_ROBIN"] = "round_robin";
    LootRule["NEED_GREED"] = "need_greed";
    LootRule["POOL"] = "pool";
    /** @deprecated alias for FFA — kept for back-compat with older party records */
    LootRule["RANDOM"] = "random";
})(LootRule || (exports.LootRule = LootRule = {}));
function normalizeLootRule(rule) {
    if (rule === LootRule.RANDOM)
        return LootRule.FFA;
    if (rule && Object.values(LootRule).includes(rule))
        return rule;
    return LootRule.FFA;
}
var PartyVisibility;
(function (PartyVisibility) {
    PartyVisibility["PRIVATE"] = "private";
    PartyVisibility["OPEN"] = "open";
})(PartyVisibility || (exports.PartyVisibility = PartyVisibility = {}));
exports.MAX_PARTY_SIZE = 8;
exports.MAX_LOOT_POOL = 16;
exports.LOOT_ASSIGNMENT_DURATION_MS = 60000;
exports.LOOT_DESPAWN_MS = 180000;
