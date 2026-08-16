import { NPCDefinition, NPCType } from '../types/npc';
import { CraftProfession } from '../types/recipes';

export const NPC_DATABASE: Record<string, NPCDefinition> = {
  'elder_miriam': {
    id: 'elder_miriam',
    name: 'Elder Miriam',
    type: NPCType.QUEST_GIVER,
    modelFile: 'Witch.glb',
    position: { x: 5, y: 0, z: 5 },
    rotation: 0,
    zoneId: 'starter_zone',
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
    modelFile: 'Worker.glb',
    position: { x: -8, y: 0, z: 3 },
    rotation: Math.PI / 4,
    zoneId: 'starter_zone',
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
    modelFile: 'Beach Character.glb',
    position: { x: -3, y: 0, z: 8 },
    rotation: -Math.PI / 6,
    zoneId: 'starter_zone',
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
  'ranger_finn': {
    id: 'ranger_finn',
    name: 'Ranger Finn',
    type: NPCType.QUEST_GIVER,
    modelFile: 'Farmer.glb',
    position: { x: 0, y: 0, z: -50 },
    rotation: Math.PI,
    zoneId: 'forest_zone',
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
    modelFile: 'Casual Character.glb',
    position: { x: 10, y: 0, z: -30 },
    rotation: -Math.PI / 3,
    zoneId: 'forest_zone',
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
  'guard_varik': {
    id: 'guard_varik',
    name: 'Varik Border Guard',
    type: NPCType.GENERIC,
    modelFile: 'Witch.glb',
    position: { x: 0, y: 0, z: -60 },
    rotation: 0,
    zoneId: 'mountains_of_jortio',
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
    modelFile: 'Witch.glb',
    position: { x: 0, y: 0, z: -60 },
    rotation: 0,
    zoneId: 'nelstadt_plains',
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
    modelFile: 'Witch.glb',
    position: { x: 0, y: 0, z: -60 },
    rotation: 0,
    zoneId: 'himurart_desert',
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
  'varik_blacksmith': craftNpc('varik_blacksmith', 'Borin Ironhand', 'varik_confederation', CraftProfession.BLACKSMITH, { x: -10, y: 0, z: 5 }),
  'varik_alchemist': craftNpc('varik_alchemist', 'Maven Frostbloom', 'varik_confederation', CraftProfession.ALCHEMIST, { x: 10, y: 0, z: 5 }),
  'varik_enchanter': craftNpc('varik_enchanter', 'Aldric rune-Hand', 'varik_confederation', CraftProfession.ENCHANTER, { x: 0, y: 0, z: 15 }),

  'pfelstein_blacksmith': craftNpc('pfelstein_blacksmith', 'Sir Roland the Smith', 'kingdom_pfelstein', CraftProfession.BLACKSMITH, { x: -10, y: 0, z: 5 }),
  'pfelstein_alchemist': craftNpc('pfelstein_alchemist', 'Sister Beatrix', 'kingdom_pfelstein', CraftProfession.ALCHEMIST, { x: 10, y: 0, z: 5 }),
  'pfelstein_enchanter': craftNpc('pfelstein_enchanter', 'Father Cassian', 'kingdom_pfelstein', CraftProfession.ENCHANTER, { x: 0, y: 0, z: 15 }),

  'latugan_blacksmith': craftNpc('latugan_blacksmith', 'Hassan Scorpionsbane', 'latugan_empire', CraftProfession.BLACKSMITH, { x: -10, y: 0, z: 5 }),
  'latugan_alchemist': craftNpc('latugan_alchemist', 'Zahra the Herbalist', 'latugan_empire', CraftProfession.ALCHEMIST, { x: 10, y: 0, z: 5 }),
  'latugan_enchanter': craftNpc('latugan_enchanter', 'Khalid gem-Etcher', 'latugan_empire', CraftProfession.ENCHANTER, { x: 0, y: 0, z: 15 }),
};

function craftNpc(
  id: string,
  name: string,
  zoneId: string,
  profession: CraftProfession,
  position: { x: number; y: number; z: number }
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
    modelFile: 'Casual Character.glb',
    position,
    rotation: 0,
    zoneId,
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
