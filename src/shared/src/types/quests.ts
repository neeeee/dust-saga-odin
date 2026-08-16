export enum QuestType {
  KILL = 'kill',
  COLLECT = 'collect',
  TALK = 'talk',
  EXPLORE = 'explore',
  ESCORT = 'escort'
}

export enum QuestStatus {
  AVAILABLE = 'available',
  IN_PROGRESS = 'in_progress',
  COMPLETED = 'completed',
  TURNED_IN = 'turned_in'
}

export enum QuestRepeatInterval {
  UNLIMITED = 'unlimited',
  DAILY = 'daily',
  WEEKLY = 'weekly',
}

export const QUEST_COOLDOWN_MS: Record<QuestRepeatInterval, number> = {
  [QuestRepeatInterval.UNLIMITED]: 0,
  [QuestRepeatInterval.DAILY]: 24 * 60 * 60 * 1000,
  [QuestRepeatInterval.WEEKLY]: 7 * 24 * 60 * 60 * 1000,
};

export interface DialogPage {
  speaker?: string;
  text: string;
  emote?: string;
}

export interface QuestObjective {
  id: string;
  type: QuestType;
  description?: string;
  targetId: string;
  targetName: string;
  requiredCount: number;
  currentCount: number;
  cell?: string;
  zoneId?: string;
  waypoint?: { x: number; z: number };
}

export interface QuestReward {
  experience: number;
  gold: number;
  items: Array<{ itemId: string; quantity: number }>;
}

export interface QuestObjectiveDefinition {
  id: string;
  type: QuestType;
  targetId: string;
  targetName: string;
  requiredCount: number;
  cell?: string;
  zoneId?: string;
}

export interface QuestDefinition {
  id: string;
  title: string;
  description: string;
  type: QuestType;
  objectives: QuestObjectiveDefinition[];
  rewards: QuestReward;
  requiredLevel: number;
  requiredQuest?: string;
  npcId: string;
  repeatable?: QuestRepeatInterval;
  /** Hard cap on total completions. Once reached, the quest is permanently done. */
  maxCompletions?: number;
  /** Zones to unlock for the character on first turn-in. */
  unlocksZones?: string[];
  /** Cutscene to play when this quest is accepted. */
  acceptCutsceneId?: string;
  /** Cutscene to play when this quest is turned in. */
  turnInCutsceneId?: string;
  /** Job to advance to (used by the class trainer NPC dialog, not auto-applied). */
  advancesToJob?: string;
  offerDialog?: DialogPage[];
  inProgressDialog?: DialogPage[];
  turnInDialog?: DialogPage[];
}

export interface ActiveQuest {
  questId: string;
  status: QuestStatus;
  objectives: QuestObjective[];
  startedAt: number;
  title?: string;
  description?: string;
  lastTurnedInAt?: number;
  completionCount?: number;
}
