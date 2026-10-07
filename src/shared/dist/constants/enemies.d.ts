import { LootTable } from '../types/items';
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
    skills?: Array<string>;
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
