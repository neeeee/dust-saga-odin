import { NPCDefinition, NPCType, NPCAppearance } from '../types/npc';
import { CraftProfession } from '../types/recipes';

// ── appearance cheat sheet ─────────────────────────────────────────────────
// Races: human (m/f), elf (m/f), dwarf, myrine, enkidu, lapin. Gear ids are
// item.csv entries with shipped visuals (per-race armor meshes; rigid held
// weapons/shields). Verified visual sets:
//   helmets  11001 Leather Cap · 11002 Illyrian · 11007 Obsidian Night · 11011 Kettle
//   torsos   12001 Tunic · 12002 Hermit Tunic · 12011 Gambeson · 12021 Leather
//            12101 Gothic Plate · 12102 Valiant Plate
//   legs     13001 Pants · 13011 Cuisses · 13012 Silk Pants · 13021 Tassets · 13031 Chausses
//   gloves   14001 Quilted · 14003 Silk
//   boots    15001 Quilted · 15003 Norma
//   shields  16001 Small Shield · 17001 Adarga
//   weapons  1 Gladius · 401 Claymore · 601 Hand Axe · 1001 Bludgeon ·
//            1201 Quarterstaff · 1401 Spear · 2201 Shortbow · 2601 Twisted Wand ·
//            2801 Spirit Wand
// Enemy models: paths under assets, e.g. 'monster/monster_11108_Grey Wolf.glb'.

const SMITH_OUTFIT: NPCAppearance['equipment'] = {
  armor: '12021', legs: '13021', gloves: '14001', boots: '15001', weapon: '1001',
};
const ALCHEMIST_OUTFIT: NPCAppearance['equipment'] = {
  armor: '12001', legs: '13012', gloves: '14003', weapon: '2601',
};
const ENCHANTER_OUTFIT: NPCAppearance['equipment'] = {
  armor: '12002', legs: '13012', boots: '15001', weapon: '2801',
};

export const NPC_DATABASE: Record<string, NPCDefinition> = {
  'elder_miriam': {
    id: 'elder_miriam',
    name: 'Elder Miriam',
    type: NPCType.QUEST_GIVER,
    position: { x: 5, y: 0, z: 5 },
    rotation: 0,
    zoneId: 'starter_zone',
    appearance: {
      race: 'human', female: true,
      faceIndex: 1, hairIndex: 1, hairColor: 4,
      equipment: { armor: '12002', legs: '13012', weapon: '2801' },
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'Welcome, young adventurer! The meadow has been troubled by creatures lately. Will you help us?',
        options: [
          { text: 'I will help! What needs to be done?', nextDialogId: 'quest_offer' },
          { text: 'Maybe later.', action: 'close' }
        ]
      },
      {
        id: 'quest_offer',
        text: 'The slimes to the east have been multiplying. Clear some of them out and bring me 3 slime cores as proof.',
        options: [
          { text: 'I accept this quest!', action: 'accept_quest', actionData: { questId: 'slime_cleanup' } },
          { text: 'That sounds dangerous...', action: 'close' }
        ]
      },
      {
        id: 'quest_progress',
        text: 'How goes the slime hunting? I still need those cores.',
        options: [
          { text: 'I am still working on it.', action: 'close' }
        ]
      },
      {
        id: 'quest_complete',
        text: 'Excellent work! The meadow is safer thanks to you. Here is your reward.',
        options: [
          { text: 'Thank you!', action: 'complete_quest', actionData: { questId: 'slime_cleanup' } }
        ]
      }
    ],
    quests: ['slime_cleanup', 'wolf_threat']
  },
  'blacksmith_garn': {
    id: 'blacksmith_garn',
    name: 'Blacksmith Garn',
    type: NPCType.BLACKSMITH,
    position: { x: -8, y: 0, z: 3 },
    rotation: Math.PI / 4,
    zoneId: 'starter_zone',
    appearance: {
      race: 'dwarf',
      faceIndex: 1, hairIndex: 1,
      equipment: SMITH_OUTFIT,
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'Something need work?',
        options: [
          { text: 'Enhance weapon', action: 'open_enhancement' },
          { text: 'No thanks.', action: 'close' }
        ]
      }
    ],
    shopItems: ['wooden_sword', 'leather_armor', 'cloth_helmet', 'leather_boots', 'copper_ring', 'health_potion', 'mana_potion']
  },
  'healer_rosa': {
    id: 'healer_rosa',
    name: 'Healer Rosa',
    type: NPCType.HEALER,
    position: { x: -3, y: 0, z: 8 },
    rotation: -Math.PI / 6,
    zoneId: 'starter_zone',
    appearance: {
      race: 'elf', female: true,
      faceIndex: 0, hairIndex: 2, hairColor: 0,
      equipment: { armor: '12001', legs: '13012', gloves: '14003', weapon: '2601' },
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'You look weary, adventurer. Let me restore your health and mana.',
        options: [
          { text: 'Please heal me.', action: 'heal' },
          { text: 'I am fine, thank you.', action: 'close' }
        ]
      }
    ]
  },
  // A beast NPC: the elder's old wolfhound, rendered with a shipped monster
  // glb instead of a chara model.
  'elder_wolfhound_bram': {
    id: 'elder_wolfhound_bram',
    name: 'Bram the Wolfhound',
    type: NPCType.GENERIC,
    position: { x: 7, y: 0, z: 6.5 },
    rotation: -Math.PI / 4,
    zoneId: 'starter_zone',
    appearance: {
      monsterModel: 'monster/monster_11108_Grey Wolf.glb',
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'Bram tilts his head at you, then yawns mightily. His tail thumps the grass twice — you have been acknowledged.',
        options: [
          { text: 'Good dog.', action: 'close' }
        ]
      }
    ]
  },
  'ranger_finn': {
    id: 'ranger_finn',
    name: 'Ranger Finn',
    type: NPCType.QUEST_GIVER,
    position: { x: 0, y: 0, z: -50 },
    rotation: Math.PI,
    zoneId: 'forest_zone',
    appearance: {
      race: 'elf',
      faceIndex: 0, hairIndex: 0, hairColor: 2,
      equipment: { helmet: '11001', armor: '12021', legs: '13031', boots: '15001', weapon: '2201' },
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'The forest grows darker each day. Goblins have been spotted scouting near the path. Can you investigate?',
        options: [
          { text: 'I will deal with the goblins.', nextDialogId: 'quest_offer' },
          { text: 'I need to prepare first.', action: 'close' }
        ]
      },
      {
        id: 'quest_offer',
        text: 'Slay 5 goblin scouts and bring me their ears as proof. Be careful - they travel in packs.',
        options: [
          { text: 'Consider it done!', action: 'accept_quest', actionData: { questId: 'goblin_menace' } },
          { text: 'On second thought...', action: 'close' }
        ]
      },
      {
        id: 'quest_progress',
        text: 'The goblins still lurk in the shadows. Return when you have collected their ears.',
        options: [
          { text: 'I will keep hunting.', action: 'close' }
        ]
      },
      {
        id: 'quest_complete',
        text: 'You are braver than most! The forest paths are safer now. Take this reward, you have earned it.',
        options: [
          { text: 'Glad to help!', action: 'complete_quest', actionData: { questId: 'goblin_menace' } }
        ]
      }
    ],
    quests: ['goblin_menace']
  },
  'merchant_li': {
    id: 'merchant_li',
    name: 'Merchant Li',
    type: NPCType.MERCHANT,
    position: { x: 10, y: 0, z: -30 },
    rotation: -Math.PI / 3,
    zoneId: 'forest_zone',
    appearance: {
      race: 'human', female: true,
      faceIndex: 2, hairIndex: 0, hairColor: 2,
      equipment: { armor: '12001', legs: '13012', gloves: '14003' },
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'Welcome traveler! I have goods from distant lands. Everything has a price!',
        options: [
          { text: 'Let me see your wares.', action: 'open_shop', actionData: { shopId: 'li_shop' } },
          { text: 'Not right now.', action: 'close' }
        ]
      }
    ],
    shopItems: ['iron_sword', 'chainmail', 'iron_helmet', 'swift_boots', 'health_potion', 'mana_potion']
  },
  // Another beast NPC: a reformed kobold running a small trade of his own.
  'kobold_peddler_snib': {
    id: 'kobold_peddler_snib',
    name: 'Snib the Peddler',
    type: NPCType.MERCHANT,
    position: { x: 12.5, y: 0, z: -32.5 },
    rotation: Math.PI / 3,
    zoneId: 'forest_zone',
    appearance: {
      monsterModel: 'monster/monster_21201_Kobold.glb',
      modelScale: 0.9,
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'Snib not bite! Snib trade. Shiny potions, good rope, sharp stick — Snib have it all. You buy, yes?',
        options: [
          { text: 'Show me your wares.', action: 'open_shop', actionData: { shopId: 'snib_shop' } },
          { text: 'Maybe later, Snib.', action: 'close' }
        ]
      }
    ],
    shopItems: ['health_potion', 'mana_potion', 'wooden_sword', 'leather_boots', 'antidote']
  },
  // And a third: an ancient guardian beast watching over the grove path.
  'grove_guardian': {
    id: 'grove_guardian',
    name: 'Old Grove Guardian',
    type: NPCType.GENERIC,
    position: { x: 3, y: 0, z: -47 },
    rotation: Math.PI / 2,
    zoneId: 'forest_zone',
    appearance: {
      monsterModel: 'monster/monster_12104_Elder Beast.glb',
      modelScale: 1.1,
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'The great beast regards you with old, patient eyes. The forest hums around it — you feel it has judged you, and found you harmless.',
        options: [
          { text: 'Bow respectfully.', action: 'close' }
        ]
      }
    ]
  },
  'guard_varik': {
    id: 'guard_varik',
    name: 'Varik Border Guard',
    type: NPCType.GENERIC,
    position: { x: 0, y: 0, z: -60 },
    rotation: 0,
    zoneId: 'mountains_of_jortio',
    appearance: {
      race: 'human',
      faceIndex: 0, hairIndex: 0, hairColor: 1,
      equipment: { helmet: '11011', armor: '12011', legs: '13001', boots: '15003', weapon: '1', shield: '16001' },
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'You stand at the border of the Varik Confederation. Only those who pledge their allegiance may pass. Do you wish to join Varik?',
        options: [
          { text: 'I wish to join Varik.', action: 'join_nation', actionData: { nation: 'varik' } },
          { text: 'Not yet.', action: 'close' }
        ]
      }
    ]
  },
  'guard_pfelstein': {
    id: 'guard_pfelstein',
    name: 'Pfelstein Border Guard',
    type: NPCType.GENERIC,
    position: { x: 0, y: 0, z: -60 },
    rotation: 0,
    zoneId: 'nelstadt_plains',
    appearance: {
      race: 'elf',
      faceIndex: 1, hairIndex: 0, hairColor: 3,
      equipment: { helmet: '11002', armor: '12101', legs: '13011', boots: '15003', weapon: '401' },
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'You stand at the border of the Kingdom of St. Pfelstein. Only those who pledge their allegiance may pass. Do you wish to join Pfelstein?',
        options: [
          { text: 'I wish to join Pfelstein.', action: 'join_nation', actionData: { nation: 'pfelstein' } },
          { text: 'Not yet.', action: 'close' }
        ]
      }
    ]
  },
  'guard_latugan': {
    id: 'guard_latugan',
    name: 'Latugan Border Guard',
    type: NPCType.GENERIC,
    position: { x: 0, y: 0, z: -60 },
    rotation: 0,
    zoneId: 'himurart_desert',
    appearance: {
      race: 'enkidu',
      faceIndex: 0, hairIndex: 0,
      equipment: { helmet: '11007', armor: '12011', legs: '13031', boots: '15001', weapon: '1401', shield: '17001' },
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'You stand at the border of the Latugan Empire. Only those who pledge their allegiance may pass. Do you wish to join Latugan?',
        options: [
          { text: 'I wish to join Latugan.', action: 'join_nation', actionData: { nation: 'latugan' } },
          { text: 'Not yet.', action: 'close' }
        ]
      }
    ]
  },

  // ── Crafting NPCs (3 specialists per nation capital) ────────────────────
  // Each nation has a BLACKSMITH (weapons/armor), ALCHEMIST (potions), and
  // ENCHANTER (gems/accessories). Players must visit the nation's capital to
  // craft; recipes must match the NPC's craftProfession.
  'varik_blacksmith': craftNpc('varik_blacksmith', 'Borin Ironhand', 'varik_confederation', CraftProfession.BLACKSMITH, { x: -10, y: 0, z: 5 },
    { race: 'dwarf', faceIndex: 0, hairIndex: 0, equipment: SMITH_OUTFIT }),
  'varik_alchemist': craftNpc('varik_alchemist', 'Maven Frostbloom', 'varik_confederation', CraftProfession.ALCHEMIST, { x: 10, y: 0, z: 5 },
    { race: 'elf', female: true, faceIndex: 1, hairIndex: 0, hairColor: 3, equipment: ALCHEMIST_OUTFIT }),
  'varik_enchanter': craftNpc('varik_enchanter', 'Aldric rune-Hand', 'varik_confederation', CraftProfession.ENCHANTER, { x: 0, y: 0, z: 15 },
    { race: 'myrine', faceIndex: 0, hairIndex: 0, equipment: ENCHANTER_OUTFIT }),

  'pfelstein_blacksmith': craftNpc('pfelstein_blacksmith', 'Sir Roland the Smith', 'kingdom_pfelstein', CraftProfession.BLACKSMITH, { x: -10, y: 0, z: 5 },
    { race: 'dwarf', faceIndex: 2, hairIndex: 2, equipment: SMITH_OUTFIT }),
  'pfelstein_alchemist': craftNpc('pfelstein_alchemist', 'Sister Beatrix', 'kingdom_pfelstein', CraftProfession.ALCHEMIST, { x: 10, y: 0, z: 5 },
    { race: 'human', female: true, faceIndex: 0, hairIndex: 2, hairColor: 0, equipment: ALCHEMIST_OUTFIT }),
  'pfelstein_enchanter': craftNpc('pfelstein_enchanter', 'Father Cassian', 'kingdom_pfelstein', CraftProfession.ENCHANTER, { x: 0, y: 0, z: 15 },
    { race: 'lapin', faceIndex: 0, hairIndex: 0, equipment: ENCHANTER_OUTFIT }),

  'latugan_blacksmith': craftNpc('latugan_blacksmith', 'Hassan Scorpionsbane', 'latugan_empire', CraftProfession.BLACKSMITH, { x: -10, y: 0, z: 5 },
    { race: 'human', faceIndex: 1, hairIndex: 0, hairColor: 0, equipment: SMITH_OUTFIT }),
  'latugan_alchemist': craftNpc('latugan_alchemist', 'Zahra the Herbalist', 'latugan_empire', CraftProfession.ALCHEMIST, { x: 10, y: 0, z: 5 },
    { race: 'elf', female: true, faceIndex: 2, hairIndex: 1, hairColor: 1, equipment: ALCHEMIST_OUTFIT }),
  'latugan_enchanter': craftNpc('latugan_enchanter', 'Khalid gem-Etcher', 'latugan_empire', CraftProfession.ENCHANTER, { x: 0, y: 0, z: 15 },
    { race: 'enkidu', faceIndex: 1, hairIndex: 0, equipment: ENCHANTER_OUTFIT }),

  // ── Stable keepers ──────────────────────────────────────────────────────
  // Mount/dismount services. Options route through the "stable:" dialogId
  // prefix, intercepted server-side in npcHandlers (same pattern as
  // "cutscene:"/"adv:"/"perf:"). Riding from the stable needs no Horsemanship
  // — the Summon Horse skill (20 Horsemanship) is the field alternative.
  'stable_keep_odwin': {
    id: 'stable_keep_odwin',
    name: 'Odwin the Stable Keep',
    type: NPCType.GENERIC,
    position: { x: 12, y: 0, z: 2 },
    rotation: -Math.PI / 3,
    zoneId: 'starter_zone',
    appearance: {
      race: 'human',
      faceIndex: 0, hairIndex: 1, hairColor: 1,
      equipment: { armor: '12011', legs: '13001', boots: '15003', weapon: '1201' },
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'Morning, traveler! My horses are fed, brushed and ready to ride. Care to take one out?',
        options: [
          { text: 'I would like to ride.', nextDialogId: 'stable:mount' },
          { text: 'I would like to dismount.', nextDialogId: 'stable:dismount' },
          { text: 'Just looking.', action: 'close' }
        ]
      },
      {
        id: 'mounted',
        text: 'A fine steed, isn\'t she? Treat her well out there — and do come back before dark.',
        options: [
          { text: 'Dismount.', nextDialogId: 'stable:dismount' },
          { text: 'Off I go!', action: 'close' }
        ]
      },
      {
        id: 'dismounted',
        text: 'I\'ll put her in her stall. Come back whenever you need her again.',
        options: [
          { text: 'Thanks!', action: 'close' }
        ]
      }
    ]
  },
  'stable_keep_marla': {
    id: 'stable_keep_marla',
    name: 'Marla the Stable Keep',
    type: NPCType.GENERIC,
    position: { x: 14, y: 0, z: -28 },
    rotation: Math.PI / 4,
    zoneId: 'forest_zone',
    appearance: {
      race: 'human', female: true,
      faceIndex: 1, hairIndex: 2, hairColor: 3,
      equipment: { armor: '12002', legs: '13001', boots: '15001' },
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'Need a horse through the woods? Mine know these trails blindfolded.',
        options: [
          { text: 'I would like to ride.', nextDialogId: 'stable:mount' },
          { text: 'I would like to dismount.', nextDialogId: 'stable:dismount' },
          { text: 'Not today.', action: 'close' }
        ]
      },
      {
        id: 'mounted',
        text: 'She\'ll carry you well. Mind the wolves past the border guard!',
        options: [
          { text: 'Dismount.', nextDialogId: 'stable:dismount' },
          { text: 'Off I go!', action: 'close' }
        ]
      },
      {
        id: 'dismounted',
        text: 'Back safe! She\'ll rest in the stable until you need her.',
        options: [
          { text: 'Thanks!', action: 'close' }
        ]
      }
    ]
  },

  // ── Performance test arena ─────────────────────────────────────────────
  // Dialog options route through the "perf:" dialogId prefix, intercepted
  // server-side in npcHandlers (same pattern as "cutscene:"/"adv:").
  'perf_test_controller': {
    id: 'perf_test_controller',
    name: 'Arena Engineer',
    type: NPCType.GENERIC,
    position: { x: 4, y: 0, z: -18 },
    rotation: -2.03,
    zoneId: 'performance_test',
    appearance: {
      race: 'human',
      faceIndex: 0, hairIndex: 0, hairColor: 0,
      equipment: { armor: '12102', legs: '13011', boots: '15003', weapon: '1' },
    },
    dialogs: [
      {
        id: 'greeting',
        text: 'Welcome to the performance arena. I can summon a crowd of fully rendered test players — they will stand in the arena and cycle the three unarmed attack animations. What would you like?',
        options: [
          { text: 'Spawn 100 test players', nextDialogId: 'perf:spawn:100' },
          { text: 'Spawn 50 test players', nextDialogId: 'perf:spawn:50' },
          { text: 'Spawn 25 test players', nextDialogId: 'perf:spawn:25' },
          { text: 'Despawn all test players', nextDialogId: 'perf:clear' },
          { text: 'Nothing, just looking.', action: 'close' }
        ]
      }
    ]
  },
};

function craftNpc(
  id: string,
  name: string,
  zoneId: string,
  profession: CraftProfession,
  position: { x: number; y: number; z: number },
  appearance: NPCAppearance
): NPCDefinition {
  const professionLabel = profession === CraftProfession.BLACKSMITH
    ? 'weapons and armor'
    : profession === CraftProfession.ALCHEMIST
      ? 'potions and brews'
      : 'gems and enchantments';
  return {
    id,
    name,
    type: NPCType.CRAFTSMAN,
    position,
    rotation: 0,
    zoneId,
    appearance,
    craftProfession: profession,
    dialogs: [
      {
        id: 'greeting',
        text: `Welcome. I work ${professionLabel}. Show me what recipes you know and I'll craft for you — for the cost of the materials, of course.`,
        options: [
          { text: 'Let me see what I can craft.', action: 'craft' },
          { text: 'Maybe later.', action: 'close' }
        ]
      }
    ]
  };
}

export function getNPC(id: string): NPCDefinition | undefined {
  return NPC_DATABASE[id];
}

export function getNPCsInZone(zoneId: string): NPCDefinition[] {
  return Object.values(NPC_DATABASE).filter(npc => npc.zoneId === zoneId);
}
