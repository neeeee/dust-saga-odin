import { LootTable } from '../types/items';
/**
 * A monster skill: presentation rides the same ENTITY_ANIMATION 'Skill'
 * payload as player casts (the client plays the monster glb's own clips by
 * kind — swings 0155-57 physical, cast loop 0171 + end 0172 otherwise), and
 * damage reuses the monster's basic attack roll scaled by powerMult.
 */
export interface EnemySkillDef {
    /** Display name — carried to clients (skill.csv/fx lookup, combat text). */
    name: string;
    kind: 'physical' | 'magical';
    /** Damage multiplier over the enemy definition's `attack`. */
    powerMult: number;
    /** Channel duration before the skill lands (0 = instant). */
    castTimeMs: number;
    cooldownMs: number;
}
export interface EnemyDefinition {
    id: string;
    name: string;
    modelFile: string;
    /** Multiplier applied to the monster's glb model (monster.csv model scale / 100). */
    modelScale?: number;
    level: number;
    health: number;
    attack: number;
    defense: number;
    speed: number;
    experience: number;
    aggroRange: number;
    attackRange: number;
    leashRange: number;
    respawnTime: number;
    lootTable: LootTable;
    patrolSpeed: number;
    fireResist?: number;
    iceResist?: number;
    lightningResist?: number;
    darkResist?: number;
    holyResist?: number;
    poisonResist?: number;
    magicAttack?: number;
    attackCooldown?: number;
    aggroStrategy?: 'first' | 'closest' | 'lowestHp';
    patrolStrategy?: 'random' | 'sequential';
    /** Chance-weighted pool the AI rolls against instead of a basic attack. */
    skills?: EnemySkillDef[];
    immunities?: string[];
    knockbackImmune?: boolean;
    magicDefense?: number;
}
export declare const ENEMY_DATABASE: Record<string, EnemyDefinition>;
export declare function getEnemyDefinition(id: string): EnemyDefinition | undefined;
/**
 * Registers an enemy definition at boot (used by the server's shipped-content
 * loader for the monster.csv roster). Existing entries are never overwritten,
 * so hand-authored definitions always win.
 */
export declare function registerEnemyDefinition(def: EnemyDefinition): boolean;
