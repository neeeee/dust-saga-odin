import { LootTable } from '../types/items';

export interface EnemyDefinition {
  id: string;
  name: string;
  modelFile: string;
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

export const ENEMY_DATABASE: Record<string, EnemyDefinition> = {
  'green_slime': {
    id: 'green_slime',
    name: 'Green Slime',
    modelFile: 'Enemy Small.glb',
    level: 1,
    health: 40,
    attack: 5,
    defense: 1,
    speed: 2,
    experience: 15,
    aggroRange: 8,
    attackRange: 1.5,
    leashRange: 20,
    respawnTime: 10000,
    patrolSpeed: 1,
    lootTable: {
      rolls: 1,
      drops: [
        { itemId: 'health_potion', quantity: 1, chance: 0.3 },
        { itemId: 'wolf_pelt', quantity: 1, chance: 0.2 },
        { itemId: 'recipe_health_potion', quantity: 1, chance: 0.04 },
        { itemId: 'recipe_leather_armor', quantity: 1, chance: 0.03 }
      ]
    }
  },
  'dire_wolf': {
    id: 'dire_wolf',
    name: 'Dire Wolf',
    modelFile: 'Enemy Small.glb',
    level: 3,
    health: 80,
    attack: 12,
    defense: 3,
    speed: 4,
    experience: 35,
    aggroRange: 12,
    attackRange: 1.8,
    leashRange: 25,
    respawnTime: 15000,
    patrolSpeed: 2,
    lootTable: {
      rolls: 2,
      drops: [
        { itemId: 'wolf_pelt', quantity: 1, chance: 0.5 },
        { itemId: 'health_potion', quantity: 1, chance: 0.2 },
        { itemId: 'leather_boots', quantity: 1, chance: 0.05 },
        { itemId: 'recipe_leather_boots', quantity: 1, chance: 0.04 },
        { itemId: 'recipe_leather_armor', quantity: 1, chance: 0.03 }
      ]
    }
  },
  'goblin_scout': {
    id: 'goblin_scout',
    name: 'Goblin Scout',
    modelFile: 'Enemy Small.glb',
    level: 5,
    health: 120,
    attack: 18,
    defense: 5,
    speed: 3.5,
    experience: 60,
    aggroRange: 10,
    attackRange: 2,
    leashRange: 25,
    respawnTime: 20000,
    patrolSpeed: 1.5,
    lootTable: {
      rolls: 2,
      drops: [
        { itemId: 'goblin_ear', quantity: 1, chance: 0.6 },
        { itemId: 'iron_sword', quantity: 1, chance: 0.03 },
        { itemId: 'health_potion', quantity: 1, chance: 0.3 },
        { itemId: 'mana_potion', quantity: 1, chance: 0.2 },
        { itemId: 'recipe_iron_sword', quantity: 1, chance: 0.05 },
        { itemId: 'recipe_hunter_crossbow', quantity: 1, chance: 0.04 },
        { itemId: 'recipe_mana_potion', quantity: 1, chance: 0.04 }
      ]
    }
  },
  'forest_troll': {
    id: 'forest_troll',
    name: 'Forest Troll',
    modelFile: 'Enemy Small.glb',
    level: 8,
    health: 200,
    attack: 28,
    defense: 10,
    speed: 2.5,
    experience: 120,
    aggroRange: 10,
    attackRange: 2.5,
    leashRange: 30,
    respawnTime: 30000,
    patrolSpeed: 1,
    lootTable: {
      rolls: 2,
      drops: [
        { itemId: 'chainmail', quantity: 1, chance: 0.05 },
        { itemId: 'steel_blade', quantity: 1, chance: 0.03 },
        { itemId: 'health_potion', quantity: 2, chance: 0.4 },
        { itemId: 'ancient_scroll', quantity: 1, chance: 0.1 },
        { itemId: 'recipe_chainmail', quantity: 1, chance: 0.05 },
        { itemId: 'recipe_steel_blade', quantity: 1, chance: 0.04 },
        { itemId: 'recipe_fire_magic_gem', quantity: 1, chance: 0.03 }
      ]
    }
  },
  'shadow_wraith': {
    id: 'shadow_wraith',
    name: 'Shadow Wraith',
    modelFile: 'Enemy Small.glb',
    level: 12,
    health: 350,
    attack: 40,
    defense: 8,
    speed: 3,
    experience: 250,
    aggroRange: 15,
    attackRange: 2,
    leashRange: 35,
    respawnTime: 45000,
    patrolSpeed: 1.5,
    lootTable: {
      rolls: 3,
      drops: [
        { itemId: 'plate_armor', quantity: 1, chance: 0.04 },
        { itemId: 'swift_boots', quantity: 1, chance: 0.03 },
        { itemId: 'ancient_scroll', quantity: 1, chance: 0.2 },
        { itemId: 'health_potion', quantity: 3, chance: 0.5 },
        { itemId: 'mana_potion', quantity: 2, chance: 0.4 },
        { itemId: 'recipe_plate_armor', quantity: 1, chance: 0.05 },
        { itemId: 'recipe_thunder_helm', quantity: 1, chance: 0.03 },
        { itemId: 'recipe_dark_magic_gem', quantity: 1, chance: 0.05 },
        { itemId: 'recipe_mysterious_potion', quantity: 1, chance: 0.03 },
        { itemId: 'recipe_flame_amulet', quantity: 1, chance: 0.02 }
      ]
    }
  },
  'mountain_bandit': {
    id: 'mountain_bandit',
    name: 'Mountain Bandit',
    modelFile: 'Enemy Small.glb',
    level: 12,
    health: 280,
    attack: 35,
    defense: 12,
    speed: 3.5,
    experience: 180,
    aggroRange: 10,
    attackRange: 2,
    leashRange: 25,
    respawnTime: 20000,
    patrolSpeed: 2,
    lootTable: {
      rolls: 2,
      drops: [
        { itemId: 'health_potion', quantity: 1, chance: 0.4 },
        { itemId: 'iron_sword', quantity: 1, chance: 0.08 },
        { itemId: 'leather_boots', quantity: 1, chance: 0.06 }
      ]
    }
  },
  'rock_golem': {
    id: 'rock_golem',
    name: 'Rock Golem',
    modelFile: 'Enemy Small.glb',
    level: 16,
    health: 500,
    attack: 30,
    defense: 25,
    speed: 1.5,
    experience: 220,
    aggroRange: 8,
    attackRange: 2.5,
    leashRange: 20,
    respawnTime: 30000,
    patrolSpeed: 0.8,
    lootTable: {
      rolls: 2,
      drops: [
        { itemId: 'health_potion', quantity: 2, chance: 0.5 },
        { itemId: 'chainmail', quantity: 1, chance: 0.06 },
        { itemId: 'ancient_scroll', quantity: 1, chance: 0.12 }
      ]
    }
  },
  'frost_wolf': {
    id: 'frost_wolf',
    name: 'Frost Wolf',
    modelFile: 'Enemy Small.glb',
    level: 20,
    health: 400,
    attack: 45,
    defense: 15,
    speed: 5,
    experience: 300,
    aggroRange: 14,
    attackRange: 2,
    leashRange: 30,
    respawnTime: 25000,
    patrolSpeed: 2.5,
    lootTable: {
      rolls: 2,
      drops: [
        { itemId: 'wolf_pelt', quantity: 1, chance: 0.5 },
        { itemId: 'health_potion', quantity: 2, chance: 0.4 },
        { itemId: 'swift_boots', quantity: 1, chance: 0.04 }
      ]
    }
  },
  'mountain_giant': {
    id: 'mountain_giant',
    name: 'Mountain Giant',
    modelFile: 'Enemy Small.glb',
    level: 30,
    health: 1200,
    attack: 65,
    defense: 30,
    speed: 1.8,
    experience: 600,
    aggroRange: 12,
    attackRange: 3.5,
    leashRange: 25,
    respawnTime: 60000,
    patrolSpeed: 1,
    lootTable: {
      rolls: 3,
      drops: [
        { itemId: 'plate_armor', quantity: 1, chance: 0.08 },
        { itemId: 'steel_blade', quantity: 1, chance: 0.06 },
        { itemId: 'health_potion', quantity: 3, chance: 0.6 },
        { itemId: 'ancient_scroll', quantity: 1, chance: 0.15 }
      ]
    }
  },
  'wild_boar': {
    id: 'wild_boar',
    name: 'Wild Boar',
    modelFile: 'Enemy Small.glb',
    level: 13,
    health: 320,
    attack: 32,
    defense: 10,
    speed: 3.5,
    experience: 190,
    aggroRange: 10,
    attackRange: 1.8,
    leashRange: 20,
    respawnTime: 18000,
    patrolSpeed: 2,
    lootTable: {
      rolls: 2,
      drops: [
        { itemId: 'health_potion', quantity: 1, chance: 0.45 },
        { itemId: 'leather_boots', quantity: 1, chance: 0.06 }
      ]
    }
  },
  'plains_lion': {
    id: 'plains_lion',
    name: 'Plains Lion',
    modelFile: 'Enemy Small.glb',
    level: 22,
    health: 550,
    attack: 50,
    defense: 18,
    speed: 4.5,
    experience: 350,
    aggroRange: 14,
    attackRange: 2,
    leashRange: 30,
    respawnTime: 25000,
    patrolSpeed: 2.5,
    lootTable: {
      rolls: 2,
      drops: [
        { itemId: 'wolf_pelt', quantity: 1, chance: 0.4 },
        { itemId: 'health_potion', quantity: 2, chance: 0.45 },
        { itemId: 'swift_boots', quantity: 1, chance: 0.05 }
      ]
    }
  },
  'nomad_raider': {
    id: 'nomad_raider',
    name: 'Nomad Raider',
    modelFile: 'Enemy Small.glb',
    level: 28,
    health: 700,
    attack: 55,
    defense: 22,
    speed: 3.5,
    experience: 450,
    aggroRange: 12,
    attackRange: 2.5,
    leashRange: 28,
    respawnTime: 30000,
    patrolSpeed: 2,
    lootTable: {
      rolls: 3,
      drops: [
        { itemId: 'steel_blade', quantity: 1, chance: 0.07 },
        { itemId: 'chainmail', quantity: 1, chance: 0.06 },
        { itemId: 'health_potion', quantity: 2, chance: 0.5 },
        { itemId: 'mana_potion', quantity: 1, chance: 0.3 }
      ]
    }
  },
  'scorpion': {
    id: 'scorpion',
    name: 'Desert Scorpion',
    modelFile: 'Enemy Small.glb',
    level: 13,
    health: 300,
    attack: 38,
    defense: 14,
    speed: 3,
    experience: 195,
    aggroRange: 10,
    attackRange: 2,
    leashRange: 22,
    respawnTime: 18000,
    patrolSpeed: 1.5,
    lootTable: {
      rolls: 2,
      drops: [
        { itemId: 'health_potion', quantity: 1, chance: 0.45 },
        { itemId: 'ancient_scroll', quantity: 1, chance: 0.08 }
      ]
    }
  },
  'sand_wurm': {
    id: 'sand_wurm',
    name: 'Sand Wurm',
    modelFile: 'Enemy Small.glb',
    level: 20,
    health: 600,
    attack: 48,
    defense: 20,
    speed: 2.5,
    experience: 320,
    aggroRange: 12,
    attackRange: 3,
    leashRange: 28,
    respawnTime: 35000,
    patrolSpeed: 1.5,
    lootTable: {
      rolls: 2,
      drops: [
        { itemId: 'health_potion', quantity: 2, chance: 0.5 },
        { itemId: 'plate_armor', quantity: 1, chance: 0.04 },
        { itemId: 'ancient_scroll', quantity: 1, chance: 0.12 }
      ]
    }
  },
  'desert_raider': {
    id: 'desert_raider',
    name: 'Desert Raider',
    modelFile: 'Enemy Small.glb',
    level: 25,
    health: 650,
    attack: 52,
    defense: 20,
    speed: 3.5,
    experience: 400,
    aggroRange: 12,
    attackRange: 2.5,
    leashRange: 28,
    respawnTime: 28000,
    patrolSpeed: 2,
    lootTable: {
      rolls: 3,
      drops: [
        { itemId: 'steel_blade', quantity: 1, chance: 0.06 },
        { itemId: 'health_potion', quantity: 2, chance: 0.5 },
        { itemId: 'mana_potion', quantity: 1, chance: 0.3 }
      ]
    }
  },
  'mummy_lord': {
    id: 'mummy_lord',
    name: 'Mummy Lord',
    modelFile: 'Enemy Small.glb',
    level: 30,
    health: 900,
    attack: 58,
    defense: 25,
    speed: 2,
    experience: 550,
    aggroRange: 10,
    attackRange: 2.5,
    leashRange: 25,
    respawnTime: 50000,
    patrolSpeed: 1,
    lootTable: {
      rolls: 3,
      drops: [
        { itemId: 'plate_armor', quantity: 1, chance: 0.07 },
        { itemId: 'ancient_scroll', quantity: 1, chance: 0.2 },
        { itemId: 'health_potion', quantity: 3, chance: 0.55 },
        { itemId: 'mana_potion', quantity: 2, chance: 0.4 }
      ]
    }
  },
  'dark_knight': {
    id: 'dark_knight',
    name: 'Dark Knight',
    modelFile: 'Enemy Small.glb',
    level: 40,
    health: 1500,
    attack: 75,
    defense: 35,
    speed: 3,
    experience: 800,
    aggroRange: 12,
    attackRange: 2.5,
    leashRange: 30,
    respawnTime: 60000,
    patrolSpeed: 1.5,
    lootTable: {
      rolls: 3,
      drops: [
        { itemId: 'plate_armor', quantity: 1, chance: 0.1 },
        { itemId: 'steel_blade', quantity: 1, chance: 0.08 },
        { itemId: 'swift_boots', quantity: 1, chance: 0.06 },
        { itemId: 'health_potion', quantity: 3, chance: 0.6 },
        { itemId: 'mana_potion', quantity: 2, chance: 0.45 }
      ]
    }
  },
  'basilisk': {
    id: 'basilisk',
    name: 'Basilisk',
    modelFile: 'Enemy Small.glb',
    level: 42,
    health: 1800,
    attack: 80,
    defense: 30,
    speed: 2.5,
    experience: 900,
    aggroRange: 10,
    attackRange: 3,
    leashRange: 25,
    respawnTime: 70000,
    patrolSpeed: 1.2,
    lootTable: {
      rolls: 4,
      drops: [
        { itemId: 'plate_armor', quantity: 1, chance: 0.1 },
        { itemId: 'steel_blade', quantity: 1, chance: 0.08 },
        { itemId: 'ancient_scroll', quantity: 2, chance: 0.2 },
        { itemId: 'health_potion', quantity: 4, chance: 0.65 }
      ]
    }
  },
  'striking_dummy': {
    id: 'striking_dummy',
    name: 'Striking Dummy',
    modelFile: 'Enemy Small.glb',
    level: 1,
    health: 999999,
    attack: 0,
    defense: 0,
    speed: 0,
    experience: 0,
    aggroRange: 0,
    attackRange: 0,
    leashRange: 0,
    respawnTime: 5000,
    lootTable: { rolls: 0, drops: [] },
    patrolSpeed: 0,
  }
};

export function getEnemyDefinition(id: string): EnemyDefinition | undefined {
  return ENEMY_DATABASE[id];
}
