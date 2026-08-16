"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.QuestSystem = void 0;
const shared_1 = require("@dust-saga/shared");
const shared_2 = require("@dust-saga/shared");
const shared_3 = require("@dust-saga/shared");
class QuestSystem {
    constructor() {
        this.db = null;
        this.questCache = new Map();
        this.dbAvailable = false;
    }
    async initialize(db) {
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
    async loadFromDb() {
        const next = new Map();
        if (this.db && this.dbAvailable) {
            try {
                const result = await this.db.postgres.query('SELECT id, title, description, type, required_level, required_quest, npc_id, objectives, rewards, dialog, repeatable, max_completions FROM quests');
                for (const row of result.rows) {
                    const def = this.rowToDefinition(row);
                    if (def)
                        next.set(def.id, def);
                }
                console.log(`[QuestSystem] Loaded ${next.size} quest(s) from database`);
            }
            catch (error) {
                console.error('[QuestSystem] Failed to load quests from database, falling back to static data:', error);
                for (const def of Object.values(shared_2.QUEST_DATABASE))
                    next.set(def.id, def);
            }
        }
        else {
            // Dev mode (no DB): use the bundled static quest data.
            for (const def of Object.values(shared_2.QUEST_DATABASE))
                next.set(def.id, def);
        }
        this.questCache = next;
    }
    async reload() {
        await this.loadFromDb();
    }
    getQuestDefinition(id) {
        return this.questCache.get(id);
    }
    getAllQuestDefinitions() {
        return [...this.questCache.values()];
    }
    getAvailableQuests(session) {
        return this.getAllQuestDefinitions()
            .filter(q => {
            if (q.requiredLevel > session.stats.level)
                return false;
            if (q.requiredQuest) {
                const prereqMet = session.quests.some(sq => sq.questId === q.requiredQuest &&
                    (sq.status === shared_1.QuestStatus.TURNED_IN || sq.status === shared_1.QuestStatus.COMPLETED));
                if (!prereqMet)
                    return false;
            }
            const existing = session.quests.find(sq => sq.questId === q.id);
            if (!existing)
                return true;
            // Quest record exists — only re-available if repeatable + off cooldown
            return this.canRepeat(q, existing);
        })
            .map(q => q.id);
    }
    /** Returns true if a turned-in quest can be accepted again. */
    canRepeat(def, record) {
        if (record.status !== shared_1.QuestStatus.TURNED_IN)
            return false;
        if (!def.repeatable)
            return false;
        if (def.maxCompletions && (record.completionCount || 0) >= def.maxCompletions)
            return false;
        if (!record.lastTurnedInAt)
            return true;
        const cooldown = shared_1.QUEST_COOLDOWN_MS[def.repeatable] ?? 0;
        if (cooldown === 0)
            return true;
        return Date.now() >= record.lastTurnedInAt + cooldown;
    }
    /** Returns the timestamp when a repeatable quest becomes available again, or null if currently available. */
    repeatAvailableAt(def, record) {
        if (!def.repeatable || record.status !== shared_1.QuestStatus.TURNED_IN)
            return null;
        if (!record.lastTurnedInAt)
            return null;
        const cooldown = shared_1.QUEST_COOLDOWN_MS[def.repeatable] ?? 0;
        if (cooldown === 0)
            return null;
        const ready = record.lastTurnedInAt + cooldown;
        return Date.now() >= ready ? null : ready;
    }
    acceptQuest(session, questId) {
        const questDef = this.getQuestDefinition(questId);
        if (!questDef)
            return false;
        if (questDef.requiredLevel > session.stats.level)
            return false;
        if (questDef.requiredQuest) {
            const prereqMet = session.quests.some(sq => sq.questId === questDef.requiredQuest &&
                (sq.status === shared_1.QuestStatus.TURNED_IN || sq.status === shared_1.QuestStatus.COMPLETED));
            if (!prereqMet)
                return false;
        }
        const existing = session.quests.find(q => q.questId === questId);
        if (existing) {
            // Re-accepting a repeatable quest: reset objectives + status
            if (!this.canRepeat(questDef, existing))
                return false;
            existing.objectives = this.buildRuntimeObjectives(questDef, session);
            existing.status = shared_1.QuestStatus.IN_PROGRESS;
            existing.startedAt = Date.now();
            return true;
        }
        const npcZoneId = this.resolveQuestZoneId(questDef);
        session.quests.push({
            questId,
            status: shared_1.QuestStatus.IN_PROGRESS,
            title: questDef.title,
            description: questDef.description,
            objectives: this.buildRuntimeObjectives(questDef, session),
            startedAt: Date.now(),
            completionCount: 0,
        });
        return true;
    }
    /** Build the runtime objective array (with currentCount=0, waypoints, etc.) from a definition. */
    buildRuntimeObjectives(questDef, session) {
        const npcZoneId = this.resolveQuestZoneId(questDef);
        return questDef.objectives.map(obj => {
            const runtimeObj = {
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
                const cell = (0, shared_3.parseCellLabel)(obj.cell);
                const zoneIdForGrid = runtimeObj.zoneId || session.zoneId;
                const zoneDef = (0, shared_3.getZoneDefinition)(zoneIdForGrid);
                if (cell && zoneDef) {
                    const center = (0, shared_3.cellCenter)(cell, zoneDef.size);
                    runtimeObj.waypoint = { x: center.x, z: center.z };
                }
            }
            else if (obj.zoneId) {
                runtimeObj.zoneId = obj.zoneId;
            }
            return runtimeObj;
        });
    }
    resolveQuestZoneId(questDef) {
        for (const obj of questDef.objectives) {
            if (obj.zoneId)
                return obj.zoneId;
        }
        return undefined;
    }
    onEnemyKill(session, enemyType) {
        return this.progressObjectives(session, shared_1.QuestType.KILL, enemyType);
    }
    onItemCollect(session, itemId) {
        const result = { progressed: [], completed: [] };
        session.quests
            .filter(q => q.status === shared_1.QuestStatus.IN_PROGRESS)
            .forEach(quest => {
            let changed = false;
            quest.objectives
                .filter(obj => obj.type === shared_1.QuestType.COLLECT && obj.targetId === itemId)
                .forEach(obj => {
                const count = session.inventory.filter(inv => inv.itemId === itemId)
                    .reduce((sum, inv) => sum + inv.quantity, 0);
                const before = obj.currentCount;
                obj.currentCount = Math.min(count, obj.requiredCount);
                if (obj.currentCount !== before)
                    changed = true;
            });
            if (changed && !result.progressed.includes(quest.questId))
                result.progressed.push(quest.questId);
            if (changed && this.isQuestComplete(quest)) {
                quest.status = shared_1.QuestStatus.COMPLETED;
                result.completed.push(quest.questId);
            }
        });
        return result;
    }
    onTalk(session, npcId) {
        return this.progressObjectives(session, shared_1.QuestType.TALK, npcId);
    }
    onExplore(session, zoneOrLocationId) {
        return this.progressObjectives(session, shared_1.QuestType.EXPLORE, zoneOrLocationId);
    }
    onCellEnter(session, cellLabel, zoneId) {
        const result = { progressed: [], completed: [] };
        const upper = cellLabel.toUpperCase();
        session.quests
            .filter(q => q.status === shared_1.QuestStatus.IN_PROGRESS)
            .forEach(quest => {
            let changed = false;
            quest.objectives
                .filter(obj => (obj.type === shared_1.QuestType.EXPLORE || obj.type === shared_1.QuestType.ESCORT) && obj.cell && obj.currentCount < obj.requiredCount)
                .forEach(obj => {
                const matchesZone = !obj.zoneId || obj.zoneId === zoneId;
                if (!matchesZone)
                    return;
                if (obj.cell?.toUpperCase() !== upper)
                    return;
                obj.currentCount++;
                changed = true;
            });
            if (changed && !result.progressed.includes(quest.questId))
                result.progressed.push(quest.questId);
            if (changed && this.isQuestComplete(quest)) {
                quest.status = shared_1.QuestStatus.COMPLETED;
                result.completed.push(quest.questId);
            }
        });
        return result;
    }
    onEscort(session, escortNpcId) {
        return this.progressObjectives(session, shared_1.QuestType.ESCORT, escortNpcId);
    }
    progressObjectives(session, type, targetId) {
        const result = { progressed: [], completed: [] };
        session.quests
            .filter(q => q.status === shared_1.QuestStatus.IN_PROGRESS)
            .forEach(quest => {
            let changed = false;
            quest.objectives
                .filter(obj => obj.type === type && obj.targetId === targetId && obj.currentCount < obj.requiredCount)
                .forEach(obj => {
                obj.currentCount++;
                changed = true;
            });
            if (changed && !result.progressed.includes(quest.questId))
                result.progressed.push(quest.questId);
            if (changed && this.isQuestComplete(quest)) {
                quest.status = shared_1.QuestStatus.COMPLETED;
                result.completed.push(quest.questId);
            }
        });
        return result;
    }
    completeQuest(session, questId) {
        const quest = session.quests.find(q => q.questId === questId);
        if (!quest || quest.status !== shared_1.QuestStatus.COMPLETED)
            return null;
        const questDef = this.getQuestDefinition(questId);
        if (!questDef)
            return null;
        const collectObjectives = questDef.objectives.filter(o => o.type === shared_1.QuestType.COLLECT);
        for (const obj of collectObjectives) {
            const have = session.inventory.filter(inv => inv.itemId === obj.targetId)
                .reduce((sum, inv) => sum + inv.quantity, 0);
            if (have < obj.requiredCount)
                return null;
        }
        quest.status = shared_1.QuestStatus.TURNED_IN;
        quest.lastTurnedInAt = Date.now();
        quest.completionCount = (quest.completionCount || 0) + 1;
        return {
            experience: questDef.rewards.experience,
            gold: questDef.rewards.gold,
            items: questDef.rewards.items,
            consumeItems: collectObjectives.map(o => ({ itemId: o.targetId, quantity: o.requiredCount })),
        };
    }
    abandonQuest(session, questId) {
        const index = session.quests.findIndex(q => q.questId === questId);
        if (index === -1)
            return false;
        session.quests.splice(index, 1);
        return true;
    }
    isQuestComplete(quest) {
        return quest.objectives.every(obj => obj.currentCount >= obj.requiredCount);
    }
    async createQuest(def) {
        const validation = this.validateDefinition(def);
        if (!validation.valid)
            return { success: false, error: validation.error };
        if (this.db && this.dbAvailable) {
            try {
                await this.db.postgres.query(`INSERT INTO quests (id, title, description, type, required_level, required_quest, npc_id, objectives, rewards, dialog, repeatable, max_completions)
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
             max_completions = EXCLUDED.max_completions`, [
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
                ]);
            }
            catch (error) {
                console.error('[QuestSystem] createQuest DB write failed:', error);
                return { success: false, error: 'Database write failed' };
            }
        }
        this.questCache.set(def.id, def);
        return { success: true };
    }
    async deleteQuest(questId) {
        if (!this.questCache.has(questId))
            return { success: false, error: 'Quest not found' };
        if (this.db && this.dbAvailable) {
            try {
                await this.db.postgres.query('DELETE FROM quests WHERE id = $1', [questId]);
            }
            catch (error) {
                console.error('[QuestSystem] deleteQuest DB write failed:', error);
                return { success: false, error: 'Database delete failed' };
            }
        }
        this.questCache.delete(questId);
        return { success: true };
    }
    validateDefinition(def) {
        if (!def.id || typeof def.id !== 'string')
            return { valid: false, error: 'Invalid or missing id' };
        if (!def.title || typeof def.title !== 'string')
            return { valid: false, error: 'Invalid or missing title' };
        if (!def.npcId || typeof def.npcId !== 'string')
            return { valid: false, error: 'Invalid or missing npcId' };
        if (!Object.values(shared_1.QuestType).includes(def.type))
            return { valid: false, error: `Invalid type (must be one of: ${Object.values(shared_1.QuestType).join(', ')})` };
        if (!Array.isArray(def.objectives) || def.objectives.length === 0)
            return { valid: false, error: 'Quest must have at least one objective' };
        for (const obj of def.objectives) {
            if (!obj.id || !obj.targetId || !obj.targetName)
                return { valid: false, error: 'Each objective needs id, targetId, targetName' };
            if (!Object.values(shared_1.QuestType).includes(obj.type))
                return { valid: false, error: `Invalid objective type: ${obj.type}` };
            if (typeof obj.requiredCount !== 'number' || obj.requiredCount < 1)
                return { valid: false, error: 'objective.requiredCount must be >= 1' };
            if (obj.cell !== undefined) {
                if (typeof obj.cell !== 'string' || !(0, shared_3.isValidCellLabel)(obj.cell)) {
                    return { valid: false, error: `objective.cell "${obj.cell}" is not a valid label (format: A1, B12, K10, ...)` };
                }
            }
            if (obj.zoneId !== undefined && typeof obj.zoneId !== 'string') {
                return { valid: false, error: 'objective.zoneId must be a string' };
            }
        }
        if (!def.rewards || typeof def.rewards !== 'object')
            return { valid: false, error: 'Missing rewards' };
        if (typeof def.rewards.experience !== 'number' || def.rewards.experience < 0)
            return { valid: false, error: 'rewards.experience must be a non-negative number' };
        if (typeof def.rewards.gold !== 'number' || def.rewards.gold < 0)
            return { valid: false, error: 'rewards.gold must be a non-negative number' };
        if (!Array.isArray(def.rewards.items))
            return { valid: false, error: 'rewards.items must be an array' };
        for (const it of def.rewards.items) {
            if (!it || typeof it.itemId !== 'string' || !it.itemId) {
                return { valid: false, error: `rewards.items[] entries must have a non-empty itemId string (got: ${JSON.stringify(it)})` };
            }
            if (typeof it.quantity !== 'number' || it.quantity < 1) {
                return { valid: false, error: `rewards.items[] entry "${it.itemId}" must have quantity >= 1 (got: ${it.quantity})` };
            }
        }
        if (def.offerDialog !== undefined) {
            if (!Array.isArray(def.offerDialog))
                return { valid: false, error: 'offerDialog must be an array' };
            for (const p of def.offerDialog) {
                if (!p || typeof p.text !== 'string' || !p.text)
                    return { valid: false, error: 'offerDialog[] entries must have a non-empty text string' };
            }
        }
        if (def.inProgressDialog !== undefined) {
            if (!Array.isArray(def.inProgressDialog))
                return { valid: false, error: 'inProgressDialog must be an array' };
            for (const p of def.inProgressDialog) {
                if (!p || typeof p.text !== 'string' || !p.text)
                    return { valid: false, error: 'inProgressDialog[] entries must have a non-empty text string' };
            }
        }
        if (def.turnInDialog !== undefined) {
            if (!Array.isArray(def.turnInDialog))
                return { valid: false, error: 'turnInDialog must be an array' };
            for (const p of def.turnInDialog) {
                if (!p || typeof p.text !== 'string' || !p.text)
                    return { valid: false, error: 'turnInDialog[] entries must have a non-empty text string' };
            }
        }
        if (typeof def.requiredLevel !== 'number' || def.requiredLevel < 1)
            return { valid: false, error: 'requiredLevel must be >= 1' };
        if (def.repeatable !== undefined) {
            if (!Object.values(shared_1.QuestRepeatInterval).includes(def.repeatable)) {
                return { valid: false, error: `Invalid repeatable value (must be one of: ${Object.values(shared_1.QuestRepeatInterval).join(', ')})` };
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
    rowToDefinition(row) {
        try {
            const objectives = typeof row.objectives === 'string' ? JSON.parse(row.objectives) : row.objectives;
            const rewards = typeof row.rewards === 'string' ? JSON.parse(row.rewards) : row.rewards;
            const rawDialog = row.dialog ? (typeof row.dialog === 'string' ? JSON.parse(row.dialog) : row.dialog) : {};
            const def = {
                id: row.id,
                title: row.title,
                description: row.description || '',
                type: row.type,
                objectives,
                rewards,
                requiredLevel: row.required_level ?? 1,
                requiredQuest: row.required_quest || undefined,
                npcId: row.npc_id,
            };
            if (Array.isArray(rawDialog.offer) && rawDialog.offer.length > 0)
                def.offerDialog = rawDialog.offer;
            if (Array.isArray(rawDialog.inProgress) && rawDialog.inProgress.length > 0)
                def.inProgressDialog = rawDialog.inProgress;
            if (Array.isArray(rawDialog.turnIn) && rawDialog.turnIn.length > 0)
                def.turnInDialog = rawDialog.turnIn;
            if (row.repeatable && Object.values(shared_1.QuestRepeatInterval).includes(row.repeatable)) {
                def.repeatable = row.repeatable;
            }
            if (row.max_completions != null && typeof row.max_completions === 'number') {
                def.maxCompletions = row.max_completions;
            }
            return def;
        }
        catch {
            return null;
        }
    }
    async seedIfEmpty() {
        if (!this.db || !this.dbAvailable)
            return;
        for (const def of Object.values(shared_2.QUEST_DATABASE)) {
            await this.db.postgres.query(`INSERT INTO quests (id, title, description, type, required_level, required_quest, npc_id, objectives, rewards, dialog, repeatable, max_completions)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
         ON CONFLICT (id) DO NOTHING`, [
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
            ]);
        }
        console.log(`[QuestSystem] Seeded ${Object.keys(shared_2.QUEST_DATABASE).length} quest(s) into database`);
    }
}
exports.QuestSystem = QuestSystem;
