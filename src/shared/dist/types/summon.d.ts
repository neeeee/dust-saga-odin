export declare enum SummonType {
    WALL = "wall",
    PLANT = "plant",
    WYVERN = "wyvern",
    TURTLE = "turtle"
}
export declare const COMBAT_SUMMON_TYPES: SummonType[];
export declare const MAX_PLANTS = 2;
export declare const SUMMON_STATS: Record<SummonType, {
    hp: number;
    defense: number;
    attackDamage: number;
    attackRange: number;
    attackCooldown: number;
    speed: number;
}>;
export declare const BANISH_RADIUS = 5;
export interface SummonInstance {
    id: string;
    ownerId: string;
    ownerName: string;
    summonType: SummonType;
    position: {
        x: number;
        y: number;
        z: number;
    };
    spawnPosition: {
        x: number;
        y: number;
        z: number;
    };
    rotation: number;
    health: number;
    maxHealth: number;
    defense: number;
    element?: string;
    attackDamage: number;
    attackRange: number;
    attackCooldown: number;
    lastAttackTime: number;
    duration: number;
    spawnedAt: number;
    targetId: string | null;
    state: 'idle' | 'follow' | 'attack' | 'dead';
    zoneId: string;
    wanderTarget: {
        x: number;
        z: number;
    } | null;
    wanderCooldown: number;
}
