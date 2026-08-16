/**
 * Cutscene script format. Scripts are stored in the `cutscenes` DB table,
 * loaded into an in-memory cache at boot, and triggered via quest events
 * or NPC dialog actions.
 *
 * The server sends the full script to the client via CUTSCENE_START. The
 * client plays it autonomously (text, moves, turns, emotes, waits), then
 * sends CUTSCENE_COMPLETE. The server restores positions and unlocks input.
 *
 * Actor references in steps:
 *   "player"  → the local player
 *   any other string → an NPC id (must exist in NPC_DATABASE for the zone)
 */

export type CutsceneStep =
  | { type: 'text'; speaker?: string; text: string; portrait?: string }
  | { type: 'move'; actor: string; to: { x: number; y: number; z: number }; speed?: number }
  | { type: 'turn'; actor: string; face: 'player' | string | { x: number; z: number } }
  | { type: 'emote'; actor: string; animation: string; duration?: number }
  | { type: 'wait'; duration: number };

export interface CutsceneScript {
  id: string;
  zoneId: string;
  steps: CutsceneStep[];
}
