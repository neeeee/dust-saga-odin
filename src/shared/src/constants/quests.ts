import { QuestDefinition, QuestType } from '../types/quests';

export const QUEST_DATABASE: Record<string, QuestDefinition> = {
  'slime_cleanup': {
    id: 'slime_cleanup',
    title: 'Slime Cleanup',
    description: 'Elder Miriam needs help clearing out the slime infestation in the meadow.',
    type: QuestType.KILL,
    objectives: [
      {
        id: 'kill_slimes',
        type: QuestType.KILL,
        targetId: 'green_slime',
        targetName: 'Green Slime',
        requiredCount: 5
      }
    ],
    rewards: {
      experience: 50,
      gold: 20,
      items: [{ itemId: 'health_potion', quantity: 3 }]
    },
    requiredLevel: 1,
    npcId: 'elder_miriam',
    offerDialog: [
      { text: 'Welcome, young adventurer. The meadow east of here has been overrun by slimes.' },
      { text: 'I would go myself, but my old bones cannot wield a blade any longer. Will you help us?' }
    ],
    inProgressDialog: [
      { text: 'The slimes still multiply. Return to me when you have thinned their numbers.' }
    ],
    turnInDialog: [
      { text: 'The meadow feels safer already. Thank you for your help.' },
      { text: 'Please, take these potions. You may need them where you are going.' }
    ]
  },
  'scout_meadow': {
    id: 'scout_meadow',
    title: 'Scout the Meadow',
    description: 'Elder Miriam wants a report on the slime cluster in the eastern meadow.',
    type: QuestType.EXPLORE,
    objectives: [
      {
        id: 'find_slime_cluster',
        type: QuestType.EXPLORE,
        targetId: 'l12',
        targetName: 'Slime Cluster',
        requiredCount: 1,
        cell: 'L12',
        zoneId: 'starter_zone'
      }
    ],
    rewards: {
      experience: 30,
      gold: 15,
      items: []
    },
    requiredLevel: 1,
    npcId: 'elder_miriam',
    offerDialog: [
      { text: 'Before you take up arms, I need to know how bad the infestation has grown.' },
      { text: 'Head east to the slime cluster — open your map and look for the L12 marker. Get close enough to confirm what we are dealing with.' }
    ],
    inProgressDialog: [
      { text: 'The cluster is east of here. Follow the marker on your map.' }
    ],
    turnInDialog: [
      { text: 'You have seen them. Then you know what we are up against. Thank you for the report.' }
    ]
  },
  'wolf_threat': {
    id: 'wolf_threat',
    title: 'Wolf Threat',
    description: 'Dire wolves have been attacking travelers. Elder Miriam asks you to thin their numbers.',
    type: QuestType.KILL,
    objectives: [
      {
        id: 'kill_wolves',
        type: QuestType.KILL,
        targetId: 'dire_wolf',
        targetName: 'Dire Wolf',
        requiredCount: 3
      },
      {
        id: 'collect_pelts',
        type: QuestType.COLLECT,
        targetId: 'wolf_pelt',
        targetName: 'Wolf Pelt',
        requiredCount: 3
      }
    ],
    rewards: {
      experience: 100,
      gold: 40,
      items: [{ itemId: 'leather_armor', quantity: 1 }]
    },
    requiredLevel: 2,
    requiredQuest: 'slime_cleanup',
    npcId: 'elder_miriam'
  },
  'goblin_menace': {
    id: 'goblin_menace',
    title: 'Goblin Menace',
    description: 'Goblin scouts have been spotted in the Whispering Woods. Ranger Finn wants them eliminated.',
    type: QuestType.KILL,
    objectives: [
      {
        id: 'kill_goblins',
        type: QuestType.KILL,
        targetId: 'goblin_scout',
        targetName: 'Goblin Scout',
        requiredCount: 5
      },
      {
        id: 'collect_ears',
        type: QuestType.COLLECT,
        targetId: 'goblin_ear',
        targetName: 'Goblin Ear',
        requiredCount: 5
      }
    ],
    rewards: {
      experience: 200,
      gold: 75,
      items: [{ itemId: 'iron_sword', quantity: 1 }]
    },
    requiredLevel: 4,
    npcId: 'ranger_finn'
  },
  'troll_hunt': {
    id: 'troll_hunt',
    title: 'Troll Hunt',
    description: 'Forest trolls have become a menace in the deep woods. Prove your strength by defeating them.',
    type: QuestType.KILL,
    objectives: [
      {
        id: 'kill_trolls',
        type: QuestType.KILL,
        targetId: 'forest_troll',
        targetName: 'Forest Troll',
        requiredCount: 3
      }
    ],
    rewards: {
      experience: 350,
      gold: 120,
      items: [{ itemId: 'chainmail', quantity: 1 }]
    },
    requiredLevel: 7,
    requiredQuest: 'goblin_menace',
    npcId: 'ranger_finn'
  },
  'crypt_purge': {
    id: 'crypt_purge',
    title: 'Crypt Purge',
    description: 'Shadow wraiths have infested the Crypt of Shadows. Clear them out to make the dungeon safe.',
    type: QuestType.KILL,
    objectives: [
      {
        id: 'kill_wraiths',
        type: QuestType.KILL,
        targetId: 'shadow_wraith',
        targetName: 'Shadow Wraith',
        requiredCount: 5
      }
    ],
    rewards: {
      experience: 600,
      gold: 200,
      items: [{ itemId: 'plate_armor', quantity: 1 }]
    },
    requiredLevel: 10,
    npcId: 'ranger_finn'
  }
};

export function getQuest(id: string): QuestDefinition | undefined {
  return QUEST_DATABASE[id];
}
