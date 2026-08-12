export interface ZoneSpawn {
  enemyType: string;
  count: number;
  spawnArea: { centerX: number; centerZ: number; radius: number };
  patrolPoints?: Array<{ x: number; y: number; z: number }>;
}

export enum ZoneType {
  SAFE = 'safe',
  PVE = 'pve',
  PVP = 'pvp',
  NATION = 'nation',
  WAR = 'war',
  DUNGEON = 'dungeon'
}

export interface ZoneDefinition {
  id: string;
  name: string;
  description: string;
  type: ZoneType;
  levelRange: [number, number];
  groundColor: { r: number; g: number; b: number };
  fogColor: { r: number; g: number; b: number };
  fogDensity: number;
  size: number;
  playerSpawn: { x: number; y: number; z: number };
  spawns: ZoneSpawn[];
  connections: string[];
  environmentObjects: Array<{
    type: 'tree' | 'rock' | 'bush' | 'house';
    positions: Array<{ x: number; y: number; z: number; scale?: number; rotation?: number }>;
  }>;
  nation?: 'varik' | 'pfelstein' | 'latugan';
  isPvpEnabled: boolean;
  musicTrack?: string;
  /** If false, the zone requires unlocking via a quest's `unlocksZones` field. */
  unlockedByDefault?: boolean;
}

export const ZONE_DATABASE: Record<string, ZoneDefinition> = {
  'starter_zone': {
    id: 'starter_zone',
    name: 'Meadow of Beginnings',
    description: 'A peaceful meadow where new adventurers begin their journey.',
    type: ZoneType.PVE,
    levelRange: [1, 3],
    groundColor: { r: 0.35, g: 0.55, b: 0.25 },
    fogColor: { r: 0.7, g: 0.85, b: 0.95 },
    fogDensity: 0.003,
    size: 120,
    playerSpawn: { x: 0, y: 0, z: -50 },
    connections: ['forest_zone', 'astir_central'],
    spawns: [
      {
        enemyType: 'striking_dummy',
        count: 1,
        spawnArea: { centerX: 5, centerZ: -45, radius: 2 }
      },
      {
        enemyType: 'green_slime',
        count: 8,
        spawnArea: { centerX: 30, centerZ: 30, radius: 25 }
      },
      {
        enemyType: 'dire_wolf',
        count: 4,
        spawnArea: { centerX: -20, centerZ: 25, radius: 15 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  },
  'forest_zone': {
    id: 'forest_zone',
    name: 'Whispering Woods',
    description: 'A dense forest filled with dangerous creatures and hidden treasures.',
    type: ZoneType.PVE,
    levelRange: [3, 8],
    groundColor: { r: 0.2, g: 0.35, b: 0.15 },
    fogColor: { r: 0.5, g: 0.65, b: 0.45 },
    fogDensity: 0.008,
    size: 150,
    playerSpawn: { x: 0, y: 0, z: -60 },
    connections: ['starter_zone', 'dungeon_zone'],
    spawns: [
      {
        enemyType: 'dire_wolf',
        count: 6,
        spawnArea: { centerX: 0, centerZ: 0, radius: 40 }
      },
      {
        enemyType: 'goblin_scout',
        count: 5,
        spawnArea: { centerX: 30, centerZ: 20, radius: 25 }
      },
      {
        enemyType: 'forest_troll',
        count: 3,
        spawnArea: { centerX: -30, centerZ: 30, radius: 20 }
      }
    ],
    environmentObjects: [
      {
        type: 'tree',
        positions: [
          { x: -10, y: 0, z: -10, scale: 1.5 },
          { x: 8, y: 0, z: -25, scale: 1.3 },
          { x: -25, y: 0, z: 5, scale: 1.6 },
          { x: 15, y: 0, z: 10, scale: 1.2 },
          { x: -5, y: 0, z: 20, scale: 1.4 },
          { x: 30, y: 0, z: -5, scale: 1.1 },
          { x: -35, y: 0, z: -15, scale: 1.5 },
          { x: 20, y: 0, z: 30, scale: 1.3 },
          { x: -15, y: 0, z: 35, scale: 1.6 },
          { x: 40, y: 0, z: 15, scale: 1.2 },
          { x: -40, y: 0, z: 25, scale: 1.4 },
          { x: 5, y: 0, z: -45, scale: 1.5 },
          { x: -20, y: 0, z: -40, scale: 1.3 },
          { x: 25, y: 0, z: -35, scale: 1.1 },
          { x: -30, y: 0, z: 40, scale: 1.6 },
          { x: 35, y: 0, z: -20, scale: 1.2 },
          { x: -45, y: 0, z: 5, scale: 1.4 },
          { x: 45, y: 0, z: 30, scale: 1.3 },
          { x: -50, y: 0, z: -30, scale: 1.5 },
          { x: 50, y: 0, z: 0, scale: 1.1 }
        ]
      },
      {
        type: 'rock',
        positions: [
          { x: 12, y: 0, z: 5, scale: 1.2 },
          { x: -18, y: 0, z: 15, scale: 1.0 },
          { x: 25, y: 0, z: -15, scale: 1.5 },
          { x: -8, y: 0, z: -30, scale: 0.8 },
          { x: 35, y: 0, z: 25, scale: 1.3 },
          { x: -30, y: 0, z: -20, scale: 1.1 },
          { x: 40, y: 0, z: -10, scale: 0.9 },
          { x: -45, y: 0, z: 15, scale: 1.4 }
        ]
      }
    ],
    isPvpEnabled: false
  },
  'dungeon_zone': {
    id: 'dungeon_zone',
    name: 'Crypt of Shadows',
    description: 'A dark dungeon filled with undead creatures and ancient evil.',
    type: ZoneType.DUNGEON,
    levelRange: [8, 15],
    groundColor: { r: 0.15, g: 0.15, b: 0.2 },
    fogColor: { r: 0.2, g: 0.15, b: 0.3 },
    fogDensity: 0.015,
    size: 80,
    playerSpawn: { x: 0, y: 0, z: 35 },
    connections: ['forest_zone'],
    spawns: [
      {
        enemyType: 'forest_troll',
        count: 4,
        spawnArea: { centerX: 0, centerZ: 0, radius: 25 }
      },
      {
        enemyType: 'shadow_wraith',
        count: 3,
        spawnArea: { centerX: 10, centerZ: -15, radius: 20 }
      }
    ],
    environmentObjects: [
      {
        type: 'rock',
        positions: [
          { x: -15, y: 0, z: -15, scale: 2.0 },
          { x: 15, y: 0, z: -10, scale: 1.8 },
          { x: 0, y: 0, z: -25, scale: 2.2 },
          { x: -20, y: 0, z: 5, scale: 1.5 },
          { x: 20, y: 0, z: 10, scale: 1.7 },
          { x: -10, y: 0, z: 20, scale: 1.3 },
          { x: 10, y: 0, z: 25, scale: 1.6 }
        ]
      }
    ],
    isPvpEnabled: false
  },
  'astir_central': {
    id: 'astir_central',
    name: 'Astir Central Plaza',
    description: 'The central hub of Astir. A safe zone where all nations gather in peace.',
    type: ZoneType.SAFE,
    levelRange: [1, 60],
    groundColor: { r: 0.65, g: 0.6, b: 0.5 },
    fogColor: { r: 0.85, g: 0.85, b: 0.9 },
    fogDensity: 0.002,
    size: 200,
    playerSpawn: { x: 0, y: 0, z: 0 },
    connections: ['starter_zone', 'northern_confederation_road', 'eastern_royal_street', 'western_imperial_way'],
    spawns: [],
    environmentObjects: [
      {
        type: 'house',
        positions: [
          { x: -30, y: 0, z: -30, scale: 1.2 },
          { x: 30, y: 0, z: -30, scale: 1.0 },
          { x: -30, y: 0, z: 30, scale: 1.1 },
          { x: 30, y: 0, z: 30, scale: 1.3 },
          { x: 0, y: 0, z: -50, scale: 1.5 }
        ]
      }
    ],
    isPvpEnabled: false,
    musicTrack: 'town'
  },
  'northern_confederation_road': {
    id: 'northern_confederation_road',
    name: 'Northern Confederation Road',
    description: 'The road north from Astir leading toward the Varik Confederation.',
    type: ZoneType.PVE,
    levelRange: [10, 18],
    groundColor: { r: 0.4, g: 0.45, b: 0.35 },
    fogColor: { r: 0.6, g: 0.7, b: 0.8 },
    fogDensity: 0.005,
    size: 180,
    playerSpawn: { x: 0, y: 0, z: -75 },
    connections: ['astir_central', 'northern_soplar_highway'],
    spawns: [
      {
        enemyType: 'mountain_bandit',
        count: 6,
        spawnArea: { centerX: 20, centerZ: 0, radius: 35 }
      },
      {
        enemyType: 'rock_golem',
        count: 4,
        spawnArea: { centerX: -25, centerZ: 30, radius: 25 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  },
  'northern_soplar_highway': {
    id: 'northern_soplar_highway',
    name: 'Northern Soplar Highway',
    description: 'A winding highway through the northern highlands. Bandits and beasts lurk here.',
    type: ZoneType.PVE,
    levelRange: [15, 25],
    groundColor: { r: 0.35, g: 0.38, b: 0.3 },
    fogColor: { r: 0.55, g: 0.65, b: 0.75 },
    fogDensity: 0.006,
    size: 200,
    playerSpawn: { x: 0, y: 0, z: -80 },
    connections: ['northern_confederation_road', 'mountains_of_jortio'],
    spawns: [
      {
        enemyType: 'mountain_bandit',
        count: 5,
        spawnArea: { centerX: -30, centerZ: -20, radius: 30 }
      },
      {
        enemyType: 'rock_golem',
        count: 4,
        spawnArea: { centerX: 30, centerZ: 20, radius: 30 }
      },
      {
        enemyType: 'frost_wolf',
        count: 5,
        spawnArea: { centerX: 0, centerZ: 50, radius: 40 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  },
  'mountains_of_jortio': {
    id: 'mountains_of_jortio',
    name: 'Mountains of Jortio',
    description: 'Towering peaks and treacherous passes. Only the strong survive here.',
    type: ZoneType.PVE,
    levelRange: [22, 35],
    groundColor: { r: 0.45, g: 0.42, b: 0.4 },
    fogColor: { r: 0.6, g: 0.6, b: 0.7 },
    fogDensity: 0.01,
    size: 220,
    playerSpawn: { x: 0, y: 0, z: -90 },
    connections: ['northern_soplar_highway', 'varik_confederation'],
    spawns: [
      {
        enemyType: 'rock_golem',
        count: 5,
        spawnArea: { centerX: -40, centerZ: 0, radius: 35 }
      },
      {
        enemyType: 'frost_wolf',
        count: 6,
        spawnArea: { centerX: 30, centerZ: -30, radius: 35 }
      },
      {
        enemyType: 'mountain_giant',
        count: 3,
        spawnArea: { centerX: 0, centerZ: 50, radius: 30 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  },
  'varik_confederation': {
    id: 'varik_confederation',
    name: 'Varik Confederation',
    description: 'The mountain stronghold of the Varik nation. A bustling city carved from stone.',
    type: ZoneType.NATION,
    levelRange: [1, 60],
    groundColor: { r: 0.55, g: 0.5, b: 0.45 },
    fogColor: { r: 0.75, g: 0.75, b: 0.8 },
    fogDensity: 0.003,
    size: 200,
    playerSpawn: { x: 0, y: 0, z: 0 },
    connections: ['mountains_of_jortio', 'leapoltz_gorge'],
    spawns: [],
    environmentObjects: [
      {
        type: 'house',
        positions: [
          { x: -40, y: 0, z: -40, scale: 1.3 },
          { x: 40, y: 0, z: -40, scale: 1.1 },
          { x: -40, y: 0, z: 40, scale: 1.2 },
          { x: 40, y: 0, z: 40, scale: 1.0 },
          { x: 0, y: 0, z: -60, scale: 1.4 },
          { x: -60, y: 0, z: 0, scale: 1.1 },
          { x: 60, y: 0, z: 0, scale: 1.2 }
        ]
      }
    ],
    nation: 'varik',
    isPvpEnabled: false,
    musicTrack: 'town'
  },
  'leapoltz_gorge': {
    id: 'leapoltz_gorge',
    name: 'Leapoltz Gorge',
    description: 'A treacherous gorge beyond Varik territory. High-level monsters dwell in its depths.',
    type: ZoneType.PVE,
    levelRange: [35, 50],
    groundColor: { r: 0.3, g: 0.28, b: 0.25 },
    fogColor: { r: 0.4, g: 0.4, b: 0.5 },
    fogDensity: 0.012,
    size: 200,
    playerSpawn: { x: 0, y: 0, z: -80 },
    connections: ['varik_confederation'],
    spawns: [
      {
        enemyType: 'mountain_giant',
        count: 5,
        spawnArea: { centerX: 0, centerZ: 0, radius: 50 }
      },
      {
        enemyType: 'dark_knight',
        count: 4,
        spawnArea: { centerX: -30, centerZ: 40, radius: 30 }
      },
      {
        enemyType: 'basilisk',
        count: 3,
        spawnArea: { centerX: 30, centerZ: -30, radius: 25 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  },
  'eastern_royal_street': {
    id: 'eastern_royal_street',
    name: 'Eastern Royal Street',
    description: 'The grand road east from Astir leading toward the Kingdom of St. Pfelstein.',
    type: ZoneType.PVE,
    levelRange: [10, 18],
    groundColor: { r: 0.4, g: 0.5, b: 0.3 },
    fogColor: { r: 0.7, g: 0.8, b: 0.65 },
    fogDensity: 0.004,
    size: 180,
    playerSpawn: { x: 0, y: 0, z: -75 },
    connections: ['astir_central', 'eastern_soplar_highway'],
    spawns: [
      {
        enemyType: 'goblin_scout',
        count: 6,
        spawnArea: { centerX: 25, centerZ: 10, radius: 35 }
      },
      {
        enemyType: 'wild_boar',
        count: 5,
        spawnArea: { centerX: -20, centerZ: 25, radius: 30 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  },
  'eastern_soplar_highway': {
    id: 'eastern_soplar_highway',
    name: 'Eastern Soplar Highway',
    description: 'The eastern highway through rolling plains. Goblins and wild beasts are common.',
    type: ZoneType.PVE,
    levelRange: [15, 25],
    groundColor: { r: 0.45, g: 0.55, b: 0.3 },
    fogColor: { r: 0.65, g: 0.75, b: 0.6 },
    fogDensity: 0.005,
    size: 200,
    playerSpawn: { x: 0, y: 0, z: -80 },
    connections: ['eastern_royal_street', 'nelstadt_plains'],
    spawns: [
      {
        enemyType: 'goblin_scout',
        count: 5,
        spawnArea: { centerX: -25, centerZ: -10, radius: 30 }
      },
      {
        enemyType: 'wild_boar',
        count: 5,
        spawnArea: { centerX: 20, centerZ: 30, radius: 35 }
      },
      {
        enemyType: 'plains_lion',
        count: 4,
        spawnArea: { centerX: 0, centerZ: 50, radius: 40 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  },
  'nelstadt_plains': {
    id: 'nelstadt_plains',
    name: 'Nelstadt Plains',
    description: 'Vast grasslands stretching to the horizon. Lions and horsemen roam freely.',
    type: ZoneType.PVE,
    levelRange: [22, 35],
    groundColor: { r: 0.5, g: 0.55, b: 0.3 },
    fogColor: { r: 0.7, g: 0.8, b: 0.6 },
    fogDensity: 0.004,
    size: 220,
    playerSpawn: { x: 0, y: 0, z: -90 },
    connections: ['eastern_soplar_highway', 'kingdom_pfelstein'],
    spawns: [
      {
        enemyType: 'plains_lion',
        count: 6,
        spawnArea: { centerX: 30, centerZ: 0, radius: 40 }
      },
      {
        enemyType: 'wild_boar',
        count: 5,
        spawnArea: { centerX: -30, centerZ: 30, radius: 35 }
      },
      {
        enemyType: 'nomad_raider',
        count: 4,
        spawnArea: { centerX: 0, centerZ: -40, radius: 30 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  },
  'kingdom_pfelstein': {
    id: 'kingdom_pfelstein',
    name: 'Kingdom of St. Pfelstein',
    description: 'The royal capital of the Kingdom. A grand city of chivalry and faith.',
    type: ZoneType.NATION,
    levelRange: [1, 60],
    groundColor: { r: 0.6, g: 0.58, b: 0.5 },
    fogColor: { r: 0.8, g: 0.8, b: 0.85 },
    fogDensity: 0.003,
    size: 200,
    playerSpawn: { x: 0, y: 0, z: 0 },
    connections: ['nelstadt_plains', 'montorie_plains'],
    spawns: [],
    environmentObjects: [
      {
        type: 'house',
        positions: [
          { x: -40, y: 0, z: -40, scale: 1.4 },
          { x: 40, y: 0, z: -40, scale: 1.2 },
          { x: -40, y: 0, z: 40, scale: 1.3 },
          { x: 40, y: 0, z: 40, scale: 1.1 },
          { x: 0, y: 0, z: -70, scale: 1.6 },
          { x: -60, y: 0, z: 0, scale: 1.2 },
          { x: 60, y: 0, z: 0, scale: 1.1 }
        ]
      }
    ],
    nation: 'pfelstein',
    isPvpEnabled: false,
    musicTrack: 'town'
  },
  'montorie_plains': {
    id: 'montorie_plains',
    name: 'Montorie Plains',
    description: 'Plains beyond the Kingdom. Fierce nomadic warriors patrol these lands.',
    type: ZoneType.PVE,
    levelRange: [35, 50],
    groundColor: { r: 0.45, g: 0.5, b: 0.28 },
    fogColor: { r: 0.65, g: 0.7, b: 0.55 },
    fogDensity: 0.006,
    size: 200,
    playerSpawn: { x: 0, y: 0, z: -80 },
    connections: ['kingdom_pfelstein'],
    spawns: [
      {
        enemyType: 'nomad_raider',
        count: 5,
        spawnArea: { centerX: -30, centerZ: 0, radius: 40 }
      },
      {
        enemyType: 'plains_lion',
        count: 5,
        spawnArea: { centerX: 30, centerZ: -30, radius: 35 }
      },
      {
        enemyType: 'dark_knight',
        count: 3,
        spawnArea: { centerX: 0, centerZ: 40, radius: 30 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  },
  'western_imperial_way': {
    id: 'western_imperial_way',
    name: 'Western Imperial Way',
    description: 'The desert road west from Astir leading toward the Latugan Empire.',
    type: ZoneType.PVE,
    levelRange: [10, 18],
    groundColor: { r: 0.7, g: 0.6, b: 0.4 },
    fogColor: { r: 0.9, g: 0.8, b: 0.6 },
    fogDensity: 0.005,
    size: 180,
    playerSpawn: { x: 0, y: 0, z: -75 },
    connections: ['astir_central', 'western_soplar_highway'],
    spawns: [
      {
        enemyType: 'scorpion',
        count: 6,
        spawnArea: { centerX: 25, centerZ: 15, radius: 35 }
      },
      {
        enemyType: 'sand_wurm',
        count: 3,
        spawnArea: { centerX: -20, centerZ: 30, radius: 25 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  },
  'western_soplar_highway': {
    id: 'western_soplar_highway',
    name: 'Western Soplar Highway',
    description: 'The scorching highway through the western desert. Scorpions and wurms abound.',
    type: ZoneType.PVE,
    levelRange: [15, 25],
    groundColor: { r: 0.75, g: 0.65, b: 0.4 },
    fogColor: { r: 0.85, g: 0.75, b: 0.5 },
    fogDensity: 0.007,
    size: 200,
    playerSpawn: { x: 0, y: 0, z: -80 },
    connections: ['western_imperial_way', 'himurart_desert'],
    spawns: [
      {
        enemyType: 'scorpion',
        count: 5,
        spawnArea: { centerX: -25, centerZ: -15, radius: 35 }
      },
      {
        enemyType: 'sand_wurm',
        count: 4,
        spawnArea: { centerX: 30, centerZ: 25, radius: 30 }
      },
      {
        enemyType: 'desert_raider',
        count: 4,
        spawnArea: { centerX: 0, centerZ: 50, radius: 40 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  },
  'himurart_desert': {
    id: 'himurart_desert',
    name: 'Himurart Desert',
    description: 'An endless sea of sand. Ancient ruins and deadly creatures lie beneath the dunes.',
    type: ZoneType.PVE,
    levelRange: [22, 35],
    groundColor: { r: 0.8, g: 0.7, b: 0.45 },
    fogColor: { r: 0.9, g: 0.8, b: 0.55 },
    fogDensity: 0.008,
    size: 220,
    playerSpawn: { x: 0, y: 0, z: -90 },
    connections: ['western_soplar_highway', 'latugan_empire'],
    spawns: [
      {
        enemyType: 'desert_raider',
        count: 5,
        spawnArea: { centerX: 30, centerZ: -10, radius: 40 }
      },
      {
        enemyType: 'sand_wurm',
        count: 4,
        spawnArea: { centerX: -30, centerZ: 30, radius: 35 }
      },
      {
        enemyType: 'mummy_lord',
        count: 3,
        spawnArea: { centerX: 0, centerZ: 50, radius: 30 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  },
  'latugan_empire': {
    id: 'latugan_empire',
    name: 'Latugan Empire',
    description: 'The imperial capital of the Latugan Empire. A city of sandstone and splendor.',
    type: ZoneType.NATION,
    levelRange: [1, 60],
    groundColor: { r: 0.7, g: 0.62, b: 0.45 },
    fogColor: { r: 0.85, g: 0.8, b: 0.65 },
    fogDensity: 0.004,
    size: 200,
    playerSpawn: { x: 0, y: 0, z: 0 },
    connections: ['himurart_desert', 'tumblejean_sand_sea'],
    spawns: [],
    environmentObjects: [
      {
        type: 'house',
        positions: [
          { x: -40, y: 0, z: -40, scale: 1.3 },
          { x: 40, y: 0, z: -40, scale: 1.4 },
          { x: -40, y: 0, z: 40, scale: 1.1 },
          { x: 40, y: 0, z: 40, scale: 1.2 },
          { x: 0, y: 0, z: -65, scale: 1.5 },
          { x: -55, y: 0, z: 0, scale: 1.1 },
          { x: 55, y: 0, z: 0, scale: 1.3 }
        ]
      }
    ],
    nation: 'latugan',
    isPvpEnabled: false,
    musicTrack: 'town'
  },
  'tumblejean_sand_sea': {
    id: 'tumblejean_sand_sea',
    name: 'Tumblejean Sand Sea',
    description: 'The most dangerous desert in the world. Mummy lords and ancient beasts rule here.',
    type: ZoneType.PVE,
    levelRange: [35, 50],
    groundColor: { r: 0.75, g: 0.65, b: 0.4 },
    fogColor: { r: 0.85, g: 0.75, b: 0.5 },
    fogDensity: 0.01,
    size: 200,
    playerSpawn: { x: 0, y: 0, z: -80 },
    connections: ['latugan_empire'],
    spawns: [
      {
        enemyType: 'mummy_lord',
        count: 5,
        spawnArea: { centerX: -30, centerZ: 0, radius: 40 }
      },
      {
        enemyType: 'basilisk',
        count: 4,
        spawnArea: { centerX: 30, centerZ: -25, radius: 35 }
      },
      {
        enemyType: 'dark_knight',
        count: 3,
        spawnArea: { centerX: 0, centerZ: 40, radius: 30 }
      }
    ],
    environmentObjects: [],
    isPvpEnabled: false
  }
};

export function getZoneDefinition(id: string): ZoneDefinition | undefined {
  return ZONE_DATABASE[id];
}

export function isZonePvpEnabled(zoneId: string): boolean {
  return ZONE_DATABASE[zoneId]?.isPvpEnabled === true;
}

export const NATION_ZONE_MAP: Record<string, { nation: 'varik' | 'pfelstein' | 'latugan'; zoneId: string; borderZoneId: string }> = {
  varik: { nation: 'varik', zoneId: 'varik_confederation', borderZoneId: 'mountains_of_jortio' },
  pfelstein: { nation: 'pfelstein', zoneId: 'kingdom_pfelstein', borderZoneId: 'nelstadt_plains' },
  latugan: { nation: 'latugan', zoneId: 'latugan_empire', borderZoneId: 'himurart_desert' },
};
