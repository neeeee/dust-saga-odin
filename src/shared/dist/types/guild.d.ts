export type GuildRank = 'leader' | 'officer' | 'member' | 'recruit';
export declare const GUILD_RANKS: GuildRank[];
export declare const GUILD_RANK_LABELS: Record<GuildRank, string>;
/** Rank order for promote/demote comparisons (higher index = lower rank). */
export declare const GUILD_RANK_ORDER: Record<GuildRank, number>;
export interface GuildPermissions {
    invite: boolean;
    kick: boolean;
    promote: boolean;
    setMotd: boolean;
    bankWithdraw: boolean;
    /** Deposits are always allowed for members (and leader). */
    bankDeposit: boolean;
}
export declare const DEFAULT_GUILD_PERMISSIONS: Record<GuildRank, GuildPermissions>;
export interface GuildBankItem {
    itemId: string;
    quantity: number;
}
export interface GuildMemberInfo {
    characterId: string;
    name: string;
    level: number;
    jobId: string;
    rank: GuildRank;
    online: boolean;
}
export declare const GUILD_MAX_LEVEL = 50;
export declare const GUILD_MAX_MEMBERS = 40;
export declare const GUILD_NAME_MAX = 40;
export declare const GUILD_TAG_MAX = 6;
export declare const GUILD_MOTD_MAX = 255;
export declare const GUILD_BANK_MAX_SLOTS = 64;
/** Cumulative XP required to reach `level + 1` from `level`. */
export declare function guildXpToNext(level: number): number;
export declare function isGuildRank(s: string): s is GuildRank;
