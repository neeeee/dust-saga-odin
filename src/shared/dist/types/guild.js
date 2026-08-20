"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GUILD_BANK_MAX_SLOTS = exports.GUILD_MOTD_MAX = exports.GUILD_TAG_MAX = exports.GUILD_NAME_MAX = exports.GUILD_MAX_MEMBERS = exports.GUILD_MAX_LEVEL = exports.DEFAULT_GUILD_PERMISSIONS = exports.GUILD_RANK_ORDER = exports.GUILD_RANK_LABELS = exports.GUILD_RANKS = void 0;
exports.guildXpToNext = guildXpToNext;
exports.isGuildRank = isGuildRank;
exports.GUILD_RANKS = ['leader', 'officer', 'member', 'recruit'];
exports.GUILD_RANK_LABELS = {
    leader: 'Leader',
    officer: 'Officer',
    member: 'Member',
    recruit: 'Recruit',
};
/** Rank order for promote/demote comparisons (higher index = lower rank). */
exports.GUILD_RANK_ORDER = {
    leader: 0,
    officer: 1,
    member: 2,
    recruit: 3,
};
exports.DEFAULT_GUILD_PERMISSIONS = {
    leader: { invite: true, kick: true, promote: true, setMotd: true, bankWithdraw: true, bankDeposit: true },
    officer: { invite: true, kick: true, promote: false, setMotd: true, bankWithdraw: false, bankDeposit: true },
    member: { invite: false, kick: false, promote: false, setMotd: false, bankWithdraw: false, bankDeposit: true },
    recruit: { invite: false, kick: false, promote: false, setMotd: false, bankWithdraw: false, bankDeposit: false },
};
exports.GUILD_MAX_LEVEL = 50;
exports.GUILD_MAX_MEMBERS = 40;
exports.GUILD_NAME_MAX = 40;
exports.GUILD_TAG_MAX = 6;
exports.GUILD_MOTD_MAX = 255;
exports.GUILD_BANK_MAX_SLOTS = 64;
/** Cumulative XP required to reach `level + 1` from `level`. */
function guildXpToNext(level) {
    return 500 * level * (level + 1);
}
function isGuildRank(s) {
    return exports.GUILD_RANKS.includes(s);
}
