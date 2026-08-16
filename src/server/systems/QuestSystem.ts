import { PlayerSession, QuestDefinition, QuestStatus, QuestType, QuestRepeatInterval, QUEST_COOLDOWN_MS } from '@dust-saga/shared';
import { QUEST_DATABASE } from '@dust-saga/shared';
import {
  getZoneDefinition, parseCellLabel, cellCenter, isValidCellLabel,
} from '@dust-saga/shared';
import { DatabaseManager } from '../core/database/DatabaseManager';

export interface QuestTurnInResult {
  experience: number;
  gold: number;
  items: Array<{ itemId: string; quantity: number }>;
  consumeItems: Array<{ itemId: string; quantity: number }>;
}

export interface QuestProgressResult {
  progressed: string[];
  completed: string[];
}

export class QuestSystem {
  private db: DatabaseManager | null = null;
  private questCache: Map<string, QuestDefinition> = new Map();
  private dbAvailable = false;

  async initialize(db: DatabaseManager): Promise<void> {
    this.db = db;
    this.dbAvailable = db.isPostgresConnected();
    await this.loadFromDb();
    // First boot: if the DB is connected but has no quests yet, seed it once
    // from the static definitions so the starting content exists.
    if (this.dbAvailable && this.questCache.size === 0) {
      await this.seedIfEmpty().catch(err => console.error('[QuestSystem] Seed failed:', err));
      await this.loadFromDb();
    }
  }

  async loadFromDb(): Promise<void> {
    const next = new Map<string, QuestDefinition>();

    if (this.db && this.dbAvailable) {
      try {
        const result = await this.db.postgres!.query(
          'SELECT id, title, description, type, required_level, required_quest, npc_id, objectives, rewards, dialog, repeatable, max_completions FROM quests'
        );
        for (const row of result.rows) {
          const def = this.rowToDefinition(row);
          if (def) next.set(def.id, def);
        }
        console.log(`[QuestSystem] Loaded ${next.size} quest(s) from database`);
      } catch (error) {
        console.error('[QuestSystem] Failed to load quests from database, falling back to static data:', error);
        for (const def of Object.values(QUEST_DATABASE)) next.set(def.id, def);
      }
    } else {
      // Dev mode (no DB): use the bundled static quest data.
      for (const def of Object.values(QUEST_DATABASE)) next.set(def.id, def);
    }

    this.questCache = next;
  }

  async reload(): Promise<void> {
    await this.loadFromDb();
  }

  getQuestDefinition(id: string): QuestDefinition | undefined {
    return this.questCache.get(id);
  }

  getAllQuestDefinitions(): QuestDefinition[] {
    return [...this.questCache.values()];
  }

  getAvailableQuests(session: PlayerSession): string[] {
    return this.getAllQuestDefinitions()
      .filter(q => {
        if (q.requiredLevel > session.stats.level) return false;
        if (q.requiredQuest) {
          const prereqMet = session.quests.some(
            sq => sq.questId === q.requiredQuest &&
              (sq.status === QuestStatus.TURNED_IN || sq.status === QuestStatus.COMPLETED)
          );
          if (!prereqMet) return false;
        }
        const existing = session.quests.find(sq => sq.questId === q.id);
        if (!existing) return true;
        // Quest record exists — only re-available if repeatable + off cooldown
        return this.canRepeat(q, existing);
      })
      .map(q => q.id);
  }

  /** Returns true if a turned-in quest can be accepted again. */
  canRepeat(def: QuestDefinition, record: PlayerSession['quests'][0]): boolean {
    if (record.status !== QuestStatus.TURNED_IN) return false;
    if (!def.repeatable) return false;
    if (def.maxCompletions && (record.completionCount || 0) >= def.maxCompletions) return false;
    if (!record.lastTurnedInAt) return true;
    const cooldown = QUEST_COOLDOWN_MS[def.repeatable] ?? 0;
    if (cooldown === 0) return true;
    return Date.now() >= record.lastTurnedInAt + cooldown;
  }

  /** Returns the timestamp when a repeatable quest becomes available again, or null if currently available. */
  repeatAvailableAt(def: QuestDefinition, record: PlayerSession['quests'][0]): number | null {
    if (!def.repeatable || record.status !== QuestStatus.TURNED_IN) return null;
    if (!record.lastTurnedInAt) return null;
    const cooldown = QUEST_COOLDOWN_MS[def.repeatable] ?? 0;
    if (cooldown === 0) return null;
    const ready = record.lastTurnedInAt + cooldown;
    return Date.now() >= ready ? null : ready;
  }

  acceptQuest(session: PlayerSession, questId: string): boolean {
    const questDef = this.getQuestDefinition(questId);
    if (!questDef) return false;
    if (questDef.requiredLevel > session.stats.level) return false;
    if (questDef.requiredQuest) {
      const prereqMet = session.quests.some(
        sq => sq.questId === questDef.requiredQuest &&
          (sq.status === QuestStatus.TURNED_IN || sq.status === QuestStatus.COMPLETED)
      );
      if (!prereqMet) return false;
    }

    const existing = session.quests.find(q => q.questId === questId);
    if (existing) {
      // Re-accepting a repeatable quest: reset objectives + status
      if (!this.canRepeat(questDef, existing)) return false;
      existing.objectives = this.buildRuntimeObjectives(questDef, session);
      existing.status = QuestStatus.IN_PROGRESS;
      existing.startedAt = Date.now();
      return true;
    }

    const npcZoneId = this.resolveQuestZoneId(questDef);

    session.quests.push({
      questId,
      status: QuestStatus.IN_PROGRESS,
      title: questDef.title,
      description: questDef.description,
      objectives: this.buildRuntimeObjectives(questDef, session),
      startedAt: Date.now(),
      completionCount: 0,
    });

    return true;
  }

  /** Build the runtime objective array (with currentCount=0, waypoints, etc.) from a definition. */
  private buildRuntimeObjectives(
    questDef: QuestDefinition,
    session: PlayerSession
  ): PlayerSession['quests'][0]['objectives'] {
    const npcZoneId = this.resolveQuestZoneId(questDef);
    return questDef.objectives.map(obj => {
      const runtimeObj: PlayerSession['quests'][0]['objectives'][0] = {
        id: obj.id,
        type: obj.type,
        targetId: obj.targetId,
        targetName: obj.targetName,
        requiredCount: obj.requiredCount,
        currentCount: 0,
      };
      if (obj.cell) {
        runtimeObj.cell = obj.cell;
        runtimeObj.zoneId = obj.zoneId || npcZoneId;
        const cell = parseCellLabel(obj.cell);
        const zoneIdForGrid = runtimeObj.zoneId || session.zoneId;
        const zoneDef = getZoneDefinition(zoneIdForGrid);
        if (cell && zoneDef) {
          const center = cellCenter(cell, zoneDef.size);
          runtimeObj.waypoint = { x: center.x, z: center.z };
        }
      } else if (obj.zoneId) {
        runtimeObj.zoneId = obj.zoneId;
      }
      return runtimeObj;
    });
  }

  private resolveQuestZoneId(questDef: QuestDefinition): string | undefined {
    for (const obj of questDef.objectives) {
      if (obj.zoneId) return obj.zoneId;
    }
    return undefined;
  }

  onEnemyKill(session: PlayerSession, enemyType: string): QuestProgressResult {
    return this.progressObjectives(session, QuestType.KILL, enemyType);
  }

  onItemCollect(session: PlayerSession, itemId: string): QuestProgressResult {
    const result: QuestProgressResult = { progressed: [], completed: [] };

    session.quests
      .filter(q => q.status === QuestStatus.IN_PROGRESS)
      .forEach(quest => {
        let changed = false;
        quest.objectives
          .filter(obj => obj.type === QuestType.COLLECT && obj.targetId === itemId)
          .forEach(obj => {
            const count = session.inventory.filter(inv => inv.itemId === itemId)
              .reduce((sum, inv) => sum + inv.quantity, 0);
            const before = obj.currentCount;
            obj.currentCount = Math.min(count, obj.requiredCount);
            if (obj.currentCount !== before) changed = true;
          });

        if (changed && !result.progressed.includes(quest.questId)) result.progressed.push(quest.questId);

        if (changed && this.isQuestComplete(quest)) {
          quest.status = QuestStatus.COMPLETED;
          result.completed.push(quest.questId);
        }
      });

    return result;
  }

  onTalk(session: PlayerSession, npcId: string): QuestProgressResult {
    return this.progressObjectives(session, QuestType.TALK, npcId);
  }

  onExplore(session: PlayerSession, zoneOrLocationId: string): QuestProgressResult {
    return this.progressObjectives(session, QuestType.EXPLORE, zoneOrLocationId);
  }

  onCellEnter(session: PlayerSession, cellLabel: string, zoneId: string): QuestProgressResult {
    const result: QuestProgressResult = { progressed: [], completed: [] };
    const upper = cellLabel.toUpperCase();

    session.quests
      .filter(q => q.status === QuestStatus.IN_PROGRESS)
      .forEach(quest => {
        let changed = false;
        quest.objectives
          .filter(obj => (obj.type === QuestType.EXPLORE || obj.type === QuestType.ESCORT) && obj.cell && obj.currentCount < obj.requiredCount)
          .forEach(obj => {
            const matchesZone = !obj.zoneId || obj.zoneId === zoneId;
            if (!matchesZone) return;
            if (obj.cell?.toUpperCase() !== upper) return;
            obj.currentCount++;
            changed = true;
          });

        if (changed && !result.progressed.includes(quest.questId)) result.progressed.push(quest.questId);

        if (changed && this.isQuestComplete(quest)) {
          quest.status = QuestStatus.COMPLETED;
          result.completed.push(quest.questId);
        }
      });

    return result;
  }

  onEscort(session: PlayerSession, escortNpcId: string): QuestProgressResult {
    return this.progressObjectives(session, QuestType.ESCORT, escortNpcId);
  }

  private progressObjectives(session: PlayerSession, type: QuestType, targetId: string): QuestProgressResult {
    const result: QuestProgressResult = { progressed: [], completed: [] };

    session.quests
      .filter(q => q.status === QuestStatus.IN_PROGRESS)
      .forEach(quest => {
        let changed = false;
        quest.objectives
          .filter(obj => obj.type === type && obj.targetId === targetId && obj.currentCount < obj.requiredCount)
          .forEach(obj => {
            obj.currentCount++;
            changed = true;
          });

        if (changed && !result.progressed.includes(quest.questId)) result.progressed.push(quest.questId);

        if (changed && this.isQuestComplete(quest)) {
          quest.status = QuestStatus.COMPLETED;
          result.completed.push(quest.questId);
        }
      });

    return result;
  }

  completeQuest(session: PlayerSession, questId: string): QuestTurnInResult | null {
    const quest = session.quests.find(q => q.questId === questId);
    if (!quest || quest.status !== QuestStatus.COMPLETED) return null;

    const questDef = this.getQuestDefinition(questId);
    if (!questDef) return null;

    const collectObjectives = questDef.objectives.filter(o => o.type === QuestType.COLLECT);
    for (const obj of collectObjectives) {
      const have = session.inventory.filter(inv => inv.itemId === obj.targetId)
        .reduce((sum, inv) => sum + inv.quantity, 0);
      if (have < obj.requiredCount) return null;
    }

    quest.status = QuestStatus.TURNED_IN;
    quest.lastTurnedInAt = Date.now();
    quest.completionCount = (quest.completionCount || 0) + 1;

    return {
      experience: questDef.rewards.experience,
      gold: questDef.rewards.gold,
      items: questDef.rewards.items,
      consumeItems: collectObjectives.map(o => ({ itemId: o.targetId, quantity: o.requiredCount })),
    };
  }

  abandonQuest(session: PlayerSession, questId: string): boolean {
    const index = session.quests.findIndex(q => q.questId === questId);
    if (index === -1) return false;

    session.quests.splice(index, 1);
    return true;
  }

  private isQuestComplete(quest: PlayerSession['quests'][0]): boolean {
    return quest.objectives.every(obj => obj.currentCount >= obj.requiredCount);
  }

  async createQuest(def: QuestDefinition): Promise<{ success: boolean; error?: string }> {
    const validation = this.validateDefinition(def);
    if (!validation.valid) return { success: false, error: validation.error };

    if (this.db && this.dbAvailable) {
      try {
        await this.db.postgres!.query(
          `INSERT INTO quests (id, title, description, type, required_level, required_quest, npc_id, objectives, rewards, dialog, repeatable, max_completions)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
           ON CONFLICT (id) DO UPDATE SET
             title = EXCLUDED.title,
             description = EXCLUDED.description,
             type = EXCLUDED.type,
             required_level = EXCLUDED.required_level,
             required_quest = EXCLUDED.required_quest,
             npc_id = EXCLUDED.npc_id,
             objectives = EXCLUDED.objectives,
             rewards = EXCLUDED.rewards,
             dialog = EXCLUDED.dialog,
             repeatable = EXCLUDED.repeatable,
             max_completions = EXCLUDED.max_completions`,
          [
            def.id, def.title, def.description || '', def.type,
            def.requiredLevel, def.requiredQuest || null, def.npcId,
            JSON.stringify(def.objectives), JSON.stringify(def.rewards),
            JSON.stringify({
              offer: def.offerDialog || [],
              inProgress: def.inProgressDialog || [],
              turnIn: def.turnInDialog || [],
            }),
            def.repeatable || null,
            def.maxCompletions ?? null,
          ]
        );
      } catch (error) {
        console.error('[QuestSystem] createQuest DB write failed:', error);
        return { success: false, error: 'Database write failed' };
      }
    }

    this.questCache.set(def.id, def);
    return { success: true };
  }

  async deleteQuest(questId: string): Promise<{ success: boolean; error?: string }> {
    if (!this.questCache.has(questId)) return { success: false, error: 'Quest not found' };

    if (this.db && this.dbAvailable) {
      try {
        await this.db.postgres!.query('DELETE FROM quests WHERE id = $1', [questId]);
      } catch (error) {
        console.error('[QuestSystem] deleteQuest DB write failed:', error);
        return { success: false, error: 'Database delete failed' };
      }
    }

    this.questCache.delete(questId);
    return { success: true };
  }

  private validateDefinition(def: QuestDefinition): { valid: boolean; error?: string } {
    if (!def.id || typeof def.id !== 'string') return { valid: false, error: 'Invalid or missing id' };
    if (!def.title || typeof def.title !== 'string') return { valid: false, error: 'Invalid or missing title' };
    if (!def.npcId || typeof def.npcId !== 'string') return { valid: false, error: 'Invalid or missing npcId' };
    if (!Object.values(QuestType).includes(def.type)) return { valid: false, error: `Invalid type (must be one of: ${Object.values(QuestType).join(', ')})` };
    if (!Array.isArray(def.objectives) || def.objectives.length === 0) return { valid: false, error: 'Quest must have at least one objective' };
    for (const obj of def.objectives) {
      if (!obj.id || !obj.targetId || !obj.targetName) return { valid: false, error: 'Each objective needs id, targetId, targetName' };
      if (!Object.values(QuestType).includes(obj.type)) return { valid: false, error: `Invalid objective type: ${obj.type}` };
      if (typeof obj.requiredCount !== 'number' || obj.requiredCount < 1) return { valid: false, error: 'objective.requiredCount must be >= 1' };
      if (obj.cell !== undefined) {
        if (typeof obj.cell !== 'string' || !isValidCellLabel(obj.cell)) {
          return { valid: false, error: `objective.cell "${obj.cell}" is not a valid label (format: A1, B12, K10, ...)` };
        }
      }
      if (obj.zoneId !== undefined && typeof obj.zoneId !== 'string') {
        return { valid: false, error: 'objective.zoneId must be a string' };
      }
    }
    if (!def.rewards || typeof def.rewards !== 'object') return { valid: false, error: 'Missing rewards' };
    if (typeof def.rewards.experience !== 'number' || def.rewards.experience < 0) return { valid: false, error: 'rewards.experience must be a non-negative number' };
    if (typeof def.rewards.gold !== 'number' || def.rewards.gold < 0) return { valid: false, error: 'rewards.gold must be a non-negative number' };
    if (!Array.isArray(def.rewards.items)) return { valid: false, error: 'rewards.items must be an array' };
    for (const it of def.rewards.items) {
      if (!it || typeof it.itemId !== 'string' || !it.itemId) {
        return { valid: false, error: `rewards.items[] entries must have a non-empty itemId string (got: ${JSON.stringify(it)})` };
      }
      if (typeof it.quantity !== 'number' || it.quantity < 1) {
        return { valid: false, error: `rewards.items[] entry "${it.itemId}" must have quantity >= 1 (got: ${it.quantity})` };
      }
    }
    if (def.offerDialog !== undefined) {
      if (!Array.isArray(def.offerDialog)) return { valid: false, error: 'offerDialog must be an array' };
      for (const p of def.offerDialog) {
        if (!p || typeof p.text !== 'string' || !p.text) return { valid: false, error: 'offerDialog[] entries must have a non-empty text string' };
      }
    }
    if (def.inProgressDialog !== undefined) {
      if (!Array.isArray(def.inProgressDialog)) return { valid: false, error: 'inProgressDialog must be an array' };
      for (const p of def.inProgressDialog) {
        if (!p || typeof p.text !== 'string' || !p.text) return { valid: false, error: 'inProgressDialog[] entries must have a non-empty text string' };
      }
    }
    if (def.turnInDialog !== undefined) {
      if (!Array.isArray(def.turnInDialog)) return { valid: false, error: 'turnInDialog must be an array' };
      for (const p of def.turnInDialog) {
        if (!p || typeof p.text !== 'string' || !p.text) return { valid: false, error: 'turnInDialog[] entries must have a non-empty text string' };
      }
    }
    if (typeof def.requiredLevel !== 'number' || def.requiredLevel < 1) return { valid: false, error: 'requiredLevel must be >= 1' };
    if (def.repeatable !== undefined) {
      if (!Object.values(QuestRepeatInterval).includes(def.repeatable)) {
        return { valid: false, error: `Invalid repeatable value (must be one of: ${Object.values(QuestRepeatInterval).join(', ')})` };
      }
    }
    if (def.maxCompletions !== undefined) {
      if (typeof def.maxCompletions !== 'number' || def.maxCompletions < 1) {
        return { valid: false, error: 'maxCompletions must be a positive integer' };
      }
      if (!def.repeatable) {
        return { valid: false, error: 'maxCompletions requires repeatable to be set' };
      }
    }
    return { valid: true };
  }

  private rowToDefinition(row: any): QuestDefinition | null {
    try {
      const objectives = typeof row.objectives === 'string' ? JSON.parse(row.objectives) : row.objectives;
      const rewards = typeof row.rewards === 'string' ? JSON.parse(row.rewards) : row.rewards;
      const rawDialog = row.dialog ? (typeof row.dialog === 'string' ? JSON.parse(row.dialog) : row.dialog) : {};
      const def: QuestDefinition = {
        id: row.id,
        title: row.title,
        description: row.description || '',
        type: row.type as QuestType,
        objectives,
        rewards,
        requiredLevel: row.required_level ?? 1,
        requiredQuest: row.required_quest || undefined,
        npcId: row.npc_id,
      };
      if (Array.isArray(rawDialog.offer) && rawDialog.offer.length > 0) def.offerDialog = rawDialog.offer;
      if (Array.isArray(rawDialog.inProgress) && rawDialog.inProgress.length > 0) def.inProgressDialog = rawDialog.inProgress;
      if (Array.isArray(rawDialog.turnIn) && rawDialog.turnIn.length > 0) def.turnInDialog = rawDialog.turnIn;
      if (row.repeatable && Object.values(QuestRepeatInterval).includes(row.repeatable)) {
        def.repeatable = row.repeatable as QuestRepeatInterval;
      }
      if (row.max_completions != null && typeof row.max_completions === 'number') {
        def.maxCompletions = row.max_completions;
      }
      return def;
    } catch {
      return null;
    }
  }

  private async seedIfEmpty(): Promise<void> {
    if (!this.db || !this.dbAvailable) return;
    for (const def of Object.values(QUEST_DATABASE)) {
      await this.db.postgres!.query(
        `INSERT INTO quests (id, title, description, type, required_level, required_quest, npc_id, objectives, rewards, dialog, repeatable, max_completions)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
         ON CONFLICT (id) DO NOTHING`,
        [
          def.id, def.title, def.description || '', def.type,
          def.requiredLevel, def.requiredQuest || null, def.npcId,
          JSON.stringify(def.objectives), JSON.stringify(def.rewards),
          JSON.stringify({
            offer: def.offerDialog || [],
            inProgress: def.inProgressDialog || [],
            turnIn: def.turnInDialog || [],
          }),
          def.repeatable || null,
          def.maxCompletions ?? null,
        ]
      );
    }
    console.log(`[QuestSystem] Seeded ${Object.keys(QUEST_DATABASE).length} quest(s) into database`);
  }
}
