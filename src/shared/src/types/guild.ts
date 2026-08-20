export type GuildRank = 'leader' | 'officer' | 'member' | 'recruit';

export const GUILD_RANKS: GuildRank[] = ['leader', 'officer', 'member', 'recruit'];
export const GUILD_RANK_LABELS: Record<GuildRank, string> = {
  leader: 'Leader',
  officer: 'Officer',
  member: 'Member',
  recruit: 'Recruit',
};

/** Rank order for promote/demote comparisons (higher index = lower rank). */
export const GUILD_RANK_ORDER: Record<GuildRank, number> = {
  leader: 0,
  officer: 1,
  member: 2,
  recruit: 3,
};

export interface GuildPermissions {
  invite: boolean;
  kick: boolean;
  promote: boolean;
  setMotd: boolean;
  bankWithdraw: boolean;
  /** Deposits are always allowed for members (and leader). */
  bankDeposit: boolean;
}

export const DEFAULT_GUILD_PERMISSIONS: Record<GuildRank, GuildPermissions> = {
  leader:   { invite: true,  kick: true,  promote: true,  setMotd: true,  bankWithdraw: true,  bankDeposit: true },
  officer:  { invite: true,  kick: true,  promote: false, setMotd: true,  bankWithdraw: false, bankDeposit: true },
  member:   { invite: false, kick: false, promote: false, setMotd: false, bankWithdraw: false, bankDeposit: true },
  recruit:  { invite: false, kick: false, promote: false, setMotd: false, bankWithdraw: false, bankDeposit: false },
};

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

export const GUILD_MAX_LEVEL = 50;
export const GUILD_MAX_MEMBERS = 40;
export const GUILD_NAME_MAX = 40;
export const GUILD_TAG_MAX = 6;
export const GUILD_MOTD_MAX = 255;
export const GUILD_BANK_MAX_SLOTS = 64;

/** Cumulative XP required to reach `level + 1` from `level`. */
export function guildXpToNext(level: number): number {
  return 500 * level * (level + 1);
}

export function isGuildRank(s: string): s is GuildRank {
  return (GUILD_RANKS as string[]).includes(s);
}
