import { PlayerSession, CutsceneScript, getCutscene } from '@dust-saga/shared';
import { CUTSCENE_DATABASE } from '@dust-saga/shared';
import { DatabaseManager } from '../core/database/DatabaseManager';

/**
 * Loads cutscene scripts from the DB at boot and handles the server-side
 * lifecycle: snapshot player position, lock input, send script to client.
 * The client plays the scene autonomously and sends CUTSCENE_COMPLETE;
 * the server then restores positions and unlocks.
 */
export class CutsceneSystem {
  private db: DatabaseManager | null = null;
  private dbAvailable = false;

  async initialize(db: DatabaseManager): Promise<void> {
    this.db = db;
    this.dbAvailable = db.isPostgresConnected();
    await this.loadFromDb();
  }

  async loadFromDb(): Promise<void> {
    CUTSCENE_DATABASE;
    if (!this.db || !this.dbAvailable) return;
    try {
      const result = await this.db.postgres!.query(
        'SELECT id, zone_id, script FROM cutscenes'
      );
      for (const row of result.rows) {
        const script = typeof row.script === 'string' ? JSON.parse(row.script) : row.script;
        const cs: CutsceneScript = {
          id: row.id,
          zoneId: row.zone_id,
          steps: Array.isArray(script) ? script : (script?.steps || []),
        };
        CUTSCENE_DATABASE[cs.id] = cs;
      }
      console.log(`[CutsceneSystem] Loaded ${Object.keys(CUTSCENE_DATABASE).length} cutscene(s) from database`);
    } catch (error) {
      console.error('[CutsceneSystem] Failed to load cutscenes from database:', error);
    }
  }

  async reload(): Promise<void> {
    for (const key of Object.keys(CUTSCENE_DATABASE)) delete CUTSCENE_DATABASE[key];
    await this.loadFromDb();
  }

  getCutscene(id: string): CutsceneScript | undefined {
    return getCutscene(id);
  }

  getAllCutscenes(): CutsceneScript[] {
    return Object.values(CUTSCENE_DATABASE);
  }

  async createCutscene(def: CutsceneScript): Promise<{ success: boolean; error?: string }> {
    if (!def.id || typeof def.id !== 'string') return { success: false, error: 'Invalid or missing id' };
    if (!def.zoneId || typeof def.zoneId !== 'string') return { success: false, error: 'Invalid or missing zoneId' };
    if (!Array.isArray(def.steps) || def.steps.length === 0) return { success: false, error: 'Cutscene must have at least one step' };

    if (this.db && this.dbAvailable) {
      try {
        await this.db.postgres!.query(
          `INSERT INTO cutscenes (id, zone_id, script)
           VALUES ($1, $2, $3)
           ON CONFLICT (id) DO UPDATE SET
             zone_id = EXCLUDED.zone_id,
             script = EXCLUDED.script`,
          [def.id, def.zoneId, JSON.stringify(def.steps)]
        );
      } catch (error) {
        console.error('[CutsceneSystem] createCutscene DB write failed:', error);
        return { success: false, error: 'Database write failed' };
      }
    }

    CUTSCENE_DATABASE[def.id] = def;
    return { success: true };
  }

  async deleteCutscene(id: string): Promise<{ success: boolean; error?: string }> {
    if (!CUTSCENE_DATABASE[id]) return { success: false, error: 'Cutscene not found' };
    if (this.db && this.dbAvailable) {
      try {
        await this.db.postgres!.query('DELETE FROM cutscenes WHERE id = $1', [id]);
      } catch (error) {
        console.error('[CutsceneSystem] deleteCutscene DB write failed:', error);
        return { success: false, error: 'Database delete failed' };
      }
    }
    delete CUTSCENE_DATABASE[id];
    return { success: true };
  }
}
