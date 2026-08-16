"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
