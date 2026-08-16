import { NPCDefinition } from '../types/npc';
export declare const NPC_DATABASE: Record<string, NPCDefinition>;
export declare function getNPC(id: string): NPCDefinition | undefined;
export declare function getNPCsInZone(zoneId: string): NPCDefinition[];
