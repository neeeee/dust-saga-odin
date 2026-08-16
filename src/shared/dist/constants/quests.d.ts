import { QuestDefinition } from '../types/quests';
export declare const QUEST_DATABASE: Record<string, QuestDefinition>;
export declare function getQuest(id: string): QuestDefinition | undefined;
