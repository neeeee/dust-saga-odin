export enum SummonType {
  WALL = 'wall',
  PLANT = 'plant',
  WYVERN = 'wyvern',
  TURTLE = 'turtle',
}

export const COMBAT_SUMMON_TYPES: SummonType[] = [SummonType.PLANT, SummonType.WYVERN, SummonType.TURTLE];
export const MAX_PLANTS = 2;

export const SUMMON_STATS: Record<SummonType, {
  hp: number;
  defense: number;
  attackDamage: number;
  attackRange: number;
  attackCooldown: number;
  speed: number;
}> = {
  [SummonType.WALL]: { hp: 5000, defense: 500, attackDamage: 0, attackRange: 0, attackCooldown: 0, speed: 0 },
  [SummonType.PLANT]: { hp: 500, defense: 50, attackDamage: 50, attackRange: 8, attackCooldown: 3, speed: 0 },
  [SummonType.WYVERN]: { hp: 800, defense: 100, attackDamage: 500, attackRange: 5, attackCooldown: 3, speed: 3 },
  [SummonType.TURTLE]: { hp: 1200, defense: 200, attackDamage: 300, attackRange: 6, attackCooldown: 5, speed: 0 },
};

export const BANISH_RADIUS = 5;

export interface SummonInstance {
  id: string;
  ownerId: string;
  ownerName: string;
  summonType: SummonType;
  position: { x: number; y: number; z: number };
  spawnPosition: { x: number; y: number; z: number };
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
  wanderTarget: { x: number; z: number } | null;
  wanderCooldown: number;
}
