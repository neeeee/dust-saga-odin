import { CutsceneScript } from '../types/cutscenes';
/**
 * Master cutscene registry. Populated from the `cutscenes` DB table at boot
 * by CutsceneSystem.initialize(). Scripts here are the in-memory cache used
 * at runtime; the DB is the source of truth.
 */
export declare const CUTSCENE_DATABASE: Record<string, CutsceneScript>;
export declare function getCutscene(id: string): CutsceneScript | undefined;
