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
    connections: ['starter_zone', 'northern_confederation_road', 'eastern_royal_street', 'western_imperial_way', '99999999'],
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
  },
  '1001001': {
    id: '1001001',
    name: 'T01_01',
    description: 'Pandora Saga area T01_01 (town; terrain map_T01_01.glb).',
    type: ZoneType.SAFE,
    levelRange: [1, 60],
    groundColor: { r: 0.75, g: 0.6706, b: 0.5265 },
    fogColor: { r: 1.0, g: 0.8941, b: 0.702 },
    fogDensity: 0.0008,
    size: 520,
    playerSpawn: { x: -12, y: 0, z: 52 },
    connections: ['1001002', '9001001', '99999999'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false,
    musicTrack: 'town'
  },
  '1001002': {
    id: '1001002',
    name: 'T01_02',
    description: 'Pandora Saga area T01_02 (town; terrain map_T01_02.glb).',
    type: ZoneType.SAFE,
    levelRange: [1, 60],
    groundColor: { r: 0.75, g: 0.6706, b: 0.5265 },
    fogColor: { r: 1.0, g: 0.8941, b: 0.702 },
    fogDensity: 0.0008,
    size: 480,
    playerSpawn: { x: 20, y: 0, z: 32 },
    connections: ['1001001', '1001003'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false,
    musicTrack: 'town'
  },
  '1001003': {
    id: '1001003',
    name: 'T01_03',
    description: 'Pandora Saga area T01_03 (town; terrain map_T01_03.glb).',
    type: ZoneType.SAFE,
    levelRange: [1, 60],
    groundColor: { r: 0.75, g: 0.6706, b: 0.5265 },
    fogColor: { r: 1.0, g: 0.8941, b: 0.702 },
    fogDensity: 0.0008,
    size: 460,
    playerSpawn: { x: 15, y: 0, z: -17 },
    connections: ['1001002', '1001004'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false,
    musicTrack: 'town'
  },
  '1001004': {
    id: '1001004',
    name: 'T01_04',
    description: 'Pandora Saga area T01_04 (town; terrain map_T01_04.glb).',
    type: ZoneType.SAFE,
    levelRange: [1, 60],
    groundColor: { r: 0.75, g: 0.6765, b: 0.5265 },
    fogColor: { r: 1.0, g: 0.902, b: 0.702 },
    fogDensity: 0.0008,
    size: 440,
    playerSpawn: { x: 0, y: 0, z: -24 },
    connections: ['1001003', '2002001'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false,
    musicTrack: 'town'
  },
  '1002001': {
    id: '1002001',
    name: 'T02',
    description: 'Pandora Saga area T02 (town; terrain map_T02.glb).',
    type: ZoneType.SAFE,
    levelRange: [1, 60],
    groundColor: { r: 0.6353, g: 0.6853, b: 0.65 },
    fogColor: { r: 0.8471, g: 0.9137, b: 0.8667 },
    fogDensity: 0.0008,
    size: 300,
    playerSpawn: { x: 6, y: 0, z: 1 },
    connections: ['2007001'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false,
    musicTrack: 'town'
  },
  '1003001': {
    id: '1003001',
    name: 'T03',
    description: 'Pandora Saga area T03 (town; terrain map_T03.glb).',
    type: ZoneType.SAFE,
    levelRange: [1, 60],
    groundColor: { r: 0.6147, g: 0.6265, b: 0.6882 },
    fogColor: { r: 0.8196, g: 0.8353, b: 0.9176 },
    fogDensity: 0.0008,
    size: 540,
    playerSpawn: { x: 37, y: 0, z: -142 },
    connections: ['2003002'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false,
    musicTrack: 'town'
  },
  '1004001': {
    id: '1004001',
    name: 'T04',
    description: 'Pandora Saga area T04 (town; terrain map_T04.glb).',
    type: ZoneType.SAFE,
    levelRange: [1, 60],
    groundColor: { r: 0.6971, g: 0.6706, b: 0.4824 },
    fogColor: { r: 0.9294, g: 0.8941, b: 0.6431 },
    fogDensity: 0.0008,
    size: 640,
    playerSpawn: { x: -85, y: 0, z: 0 },
    connections: ['99999999'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false,
    musicTrack: 'town'
  },
  '2002001': {
    id: '2002001',
    name: 'F02_01',
    description: 'Pandora Saga area F02_01 (field; terrain map_F02_01.glb).',
    type: ZoneType.PVE,
    levelRange: [10, 20],
    groundColor: { r: 0.3294, g: 0.3559, b: 0.3765 },
    fogColor: { r: 0.4392, g: 0.4745, b: 0.502 },
    fogDensity: 0.0008,
    size: 2460,
    playerSpawn: { x: -54, y: 0, z: -2 },
    connections: ['1001004', '2002002'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '2002002': {
    id: '2002002',
    name: 'F02_02',
    description: 'Pandora Saga area F02_02 (field; terrain map_F02_02.glb).',
    type: ZoneType.PVE,
    levelRange: [10, 20],
    groundColor: { r: 0.2559, g: 0.2412, b: 0.1706 },
    fogColor: { r: 0.3412, g: 0.3216, b: 0.2275 },
    fogDensity: 0.0008,
    size: 2240,
    playerSpawn: { x: 0, y: 0, z: 0 },
    connections: ['2002001', '2002003', '3001001'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '2002003': {
    id: '2002003',
    name: 'F02_03',
    description: 'Pandora Saga area F02_03 (field; terrain map_F02_03.glb).',
    type: ZoneType.PVE,
    levelRange: [10, 20],
    groundColor: { r: 0.3294, g: 0.3559, b: 0.3765 },
    fogColor: { r: 0.4392, g: 0.4745, b: 0.502 },
    fogDensity: 0.0008,
    size: 2240,
    playerSpawn: { x: 72, y: 0, z: 86 },
    connections: ['2002002', '2003001'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '2003001': {
    id: '2003001',
    name: 'F03_01',
    description: 'Pandora Saga area F03_01 (field; terrain map_F03_01.glb).',
    type: ZoneType.PVE,
    levelRange: [20, 30],
    groundColor: { r: 0.5529, g: 0.6441, b: 0.6353 },
    fogColor: { r: 0.7373, g: 0.8588, b: 0.8471 },
    fogDensity: 0.0008,
    size: 2100,
    playerSpawn: { x: 0, y: 0, z: 16 },
    connections: ['2002003', '2003002'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '2003002': {
    id: '2003002',
    name: 'F03_02',
    description: 'Pandora Saga area F03_02 (field; terrain map_F03_02.glb).',
    type: ZoneType.PVE,
    levelRange: [20, 30],
    groundColor: { r: 0.65, g: 0.6853, b: 0.4441 },
    fogColor: { r: 0.8667, g: 0.9137, b: 0.5922 },
    fogDensity: 0.0008,
    size: 2240,
    playerSpawn: { x: 2, y: 0, z: 54 },
    connections: ['1003001', '2003001', '2003003'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '2003003': {
    id: '2003003',
    name: 'F03_03',
    description: 'Pandora Saga area F03_03 (field; terrain map_F03_03.glb).',
    type: ZoneType.PVE,
    levelRange: [20, 30],
    groundColor: { r: 0.5529, g: 0.6441, b: 0.6353 },
    fogColor: { r: 0.7373, g: 0.8588, b: 0.8471 },
    fogDensity: 0.0008,
    size: 1940,
    playerSpawn: { x: -28, y: 0, z: 30 },
    connections: ['2003002', '2004001'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '2004001': {
    id: '2004001',
    name: 'F04_01',
    description: 'Pandora Saga area F04_01 (field; terrain map_F04_01.glb).',
    type: ZoneType.PVE,
    levelRange: [30, 40],
    groundColor: { r: 0.6971, g: 0.6029, b: 0.3029 },
    fogColor: { r: 0.9294, g: 0.8039, b: 0.4039 },
    fogDensity: 0.0008,
    size: 2740,
    playerSpawn: { x: 54, y: 0, z: 54 },
    connections: ['2003003', '2004002'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '2004002': {
    id: '2004002',
    name: 'F04_02',
    description: 'Pandora Saga area F04_02 (field; terrain map_F04_02.glb).',
    type: ZoneType.PVE,
    levelRange: [30, 40],
    groundColor: { r: 0.75, g: 0.5971, b: 0.3206 },
    fogColor: { r: 1.0, g: 0.7961, b: 0.4275 },
    fogDensity: 0.0008,
    size: 2860,
    playerSpawn: { x: -18, y: 0, z: 2 },
    connections: ['2004001', '2004003'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '2004003': {
    id: '2004003',
    name: 'F04_03',
    description: 'Pandora Saga area F04_03 (field; terrain map_F04_03.glb).',
    type: ZoneType.PVE,
    levelRange: [30, 40],
    groundColor: { r: 0.6971, g: 0.6029, b: 0.3029 },
    fogColor: { r: 0.9294, g: 0.8039, b: 0.4039 },
    fogDensity: 0.0008,
    size: 2180,
    playerSpawn: { x: 18, y: 0, z: -18 },
    connections: ['2004002', '2005000'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '2005000': {
    id: '2005000',
    name: 'F05',
    description: 'Pandora Saga area F05 (field; terrain map_F05.glb).',
    type: ZoneType.PVE,
    levelRange: [40, 50],
    groundColor: { r: 0.525, g: 0.6, b: 0.675 },
    fogColor: { r: 0.7, g: 0.8, b: 0.9 },
    fogDensity: 0.0008,
    size: 2120,
    playerSpawn: { x: 0, y: 0, z: 6 },
    connections: ['2004003', '2006001'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '2006001': {
    id: '2006001',
    name: 'F06_01',
    description: 'Pandora Saga area F06_01 (field; terrain map_F06_01.glb).',
    type: ZoneType.PVE,
    levelRange: [45, 55],
    groundColor: { r: 0.7382, g: 0.5353, b: 0.2765 },
    fogColor: { r: 0.9843, g: 0.7137, b: 0.3686 },
    fogDensity: 0.0008,
    size: 3260,
    playerSpawn: { x: 0, y: 0, z: 54 },
    connections: ['2005000', '2007001'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '2007001': {
    id: '2007001',
    name: 'F07_01',
    description: 'Pandora Saga area F07_01 (field; terrain map_F07_01.glb).',
    type: ZoneType.PVE,
    levelRange: [50, 60],
    groundColor: { r: 0.6794, g: 0.75, b: 0.6265 },
    fogColor: { r: 0.9059, g: 1.0, b: 0.8353 },
    fogDensity: 0.0008,
    size: 2280,
    playerSpawn: { x: 36, y: 0, z: 36 },
    connections: ['1002001', '2006001'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '3001001': {
    id: '3001001',
    name: 'D01_01',
    description: 'Pandora Saga area D01_01 (dungeon; terrain map_D01_01.glb).',
    type: ZoneType.DUNGEON,
    levelRange: [25, 45],
    groundColor: { r: 0.2941, g: 0.4118, b: 0.3824 },
    fogColor: { r: 0.3922, g: 0.549, b: 0.5098 },
    fogDensity: 0.0008,
    size: 1020,
    playerSpawn: { x: -12, y: 0, z: 0 },
    connections: ['2002002', '3001002'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '3001002': {
    id: '3001002',
    name: 'D01_02',
    description: 'Pandora Saga area D01_02 (dungeon; terrain map_D01_02.glb).',
    type: ZoneType.DUNGEON,
    levelRange: [25, 45],
    groundColor: { r: 0.2941, g: 0.4118, b: 0.3824 },
    fogColor: { r: 0.3922, g: 0.549, b: 0.5098 },
    fogDensity: 0.0008,
    size: 680,
    playerSpawn: { x: 36, y: 0, z: 36 },
    connections: ['3001001', '3001003'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '3001003': {
    id: '3001003',
    name: 'D01_03',
    description: 'Pandora Saga area D01_03 (dungeon; terrain map_D01_03.glb).',
    type: ZoneType.DUNGEON,
    levelRange: [25, 45],
    groundColor: { r: 0.2941, g: 0.4118, b: 0.3824 },
    fogColor: { r: 0.3922, g: 0.549, b: 0.5098 },
    fogDensity: 0.0008,
    size: 980,
    playerSpawn: { x: 0, y: 0, z: 0 },
    connections: ['3001002', '3001004'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '3001004': {
    id: '3001004',
    name: 'D01_04',
    description: 'Pandora Saga area D01_04 (dungeon; terrain map_D01_04.glb).',
    type: ZoneType.DUNGEON,
    levelRange: [25, 45],
    groundColor: { r: 0.2941, g: 0.4118, b: 0.3824 },
    fogColor: { r: 0.3922, g: 0.549, b: 0.5098 },
    fogDensity: 0.0008,
    size: 980,
    playerSpawn: { x: 0, y: 0, z: -36 },
    connections: ['3001003', '3001005'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '3001005': {
    id: '3001005',
    name: 'D01_05',
    description: 'Pandora Saga area D01_05 (dungeon; terrain map_D01_05.glb).',
    type: ZoneType.DUNGEON,
    levelRange: [25, 45],
    groundColor: { r: 0.2941, g: 0.4118, b: 0.3824 },
    fogColor: { r: 0.3922, g: 0.549, b: 0.5098 },
    fogDensity: 0.0008,
    size: 1060,
    playerSpawn: { x: -12, y: 0, z: 36 },
    connections: ['3001004', '3001006'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '3001006': {
    id: '3001006',
    name: 'D01_06',
    description: 'Pandora Saga area D01_06 (dungeon; terrain map_D01_06.glb).',
    type: ZoneType.DUNGEON,
    levelRange: [25, 45],
    groundColor: { r: 0.2941, g: 0.4118, b: 0.3824 },
    fogColor: { r: 0.3922, g: 0.549, b: 0.5098 },
    fogDensity: 0.0008,
    size: 780,
    playerSpawn: { x: -36, y: 0, z: -36 },
    connections: ['3001005'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '9001001': {
    id: '9001001',
    name: 'E01_01',
    description: 'Pandora Saga area E01_01 (dungeon; terrain map_E01_01.glb).',
    type: ZoneType.DUNGEON,
    levelRange: [20, 40],
    groundColor: { r: 0.75, g: 0.6765, b: 0.4529 },
    fogColor: { r: 1.0, g: 0.902, b: 0.6039 },
    fogDensity: 0.0008,
    size: 860,
    playerSpawn: { x: -144, y: 0, z: 36 },
    connections: ['1001001'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },
  '99999999': {
    id: '99999999',
    name: 'F01',
    description: 'Pandora Saga area F01 (field; terrain map_F01.glb).',
    type: ZoneType.PVE,
    levelRange: [1, 10],
    groundColor: { r: 0.6618, g: 0.5618, b: 0.4441 },
    fogColor: { r: 0.8824, g: 0.749, b: 0.5922 },
    fogDensity: 0.0008,
    size: 1960,
    playerSpawn: { x: 0, y: 0, z: 18 },
    connections: ['1001001', '1004001', 'astir_central'],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  },

  'performance_test': {
    id: 'performance_test',
    name: 'Performance Test Arena',
    description: 'A flat dev arena for stress-testing the renderer with a crowd of fully skinned, attacking test players. Use "warp performance_test" to get here.',
    type: ZoneType.SAFE,
    levelRange: [1, 99],
    groundColor: { r: 0.28, g: 0.29, b: 0.32 },
    fogColor: { r: 0.55, g: 0.58, b: 0.65 },
    fogDensity: 0.0008,
    size: 120,
    playerSpawn: { x: 0, y: 0, z: -20 },
    connections: ['astir_central'],
    spawns: [],
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
