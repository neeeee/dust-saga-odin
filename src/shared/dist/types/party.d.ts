export declare enum LootRule {
    FFA = "ffa",
    ROUND_ROBIN = "round_robin",
    NEED_GREED = "need_greed",
    POOL = "pool",
    /** @deprecated alias for FFA — kept for back-compat with older party records */
    RANDOM = "random"
}
export declare function normalizeLootRule(rule: LootRule | string | undefined): LootRule;
export declare enum PartyVisibility {
    PRIVATE = "private",
    OPEN = "open"
}
export interface PartyMember {
    characterId: string;
    characterName: string;
    level: number;
    jobId: string;
    health: number;
    maxHealth: number;
    isLeader: boolean;
    zoneId: string;
}
export interface PartySettings {
    visibility: PartyVisibility;
    lootRule: LootRule;
}
export type LootRollKind = 'need' | 'greed' | 'pass';
export interface PartyLootItem {
    lootId: string;
    itemId: string;
    itemName: string;
    quantity: number;
    rolls: Record<string, LootRollKind>;
}
export interface PartyData {
    partyId: string;
    leaderId: string;
    members: PartyMember[];
    settings: PartySettings;
    /** Index of the next member to receive a ROUND_ROBIN assignment. */
    roundRobinIndex?: number;
}
export declare const MAX_PARTY_SIZE = 8;
export declare const MAX_LOOT_POOL = 16;
export declare const LOOT_ASSIGNMENT_DURATION_MS = 60000;
export declare const LOOT_DESPAWN_MS = 180000;
