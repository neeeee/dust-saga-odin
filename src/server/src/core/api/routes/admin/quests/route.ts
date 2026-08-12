import { Router } from 'express';
import type { QuestSystem } from '../../../../../systems/QuestSystem';
import type { ApiServices } from '../../../index';

/**
 * Human-readable shape of a QuestDefinition, surfaced at `GET /schema` for the
 * admin UI. Kept as a plain object so it serializes straight to JSON.
 */
export const QUEST_SCHEMA = {
  id: 'string (required, unique)',
  title: 'string (required)',
  description: 'string',
  type: 'kill | collect | talk | explore | escort',
  requiredLevel: 'number (>= 1, default 1)',
  requiredQuest: 'string | null (quest id prerequisite)',
  npcId: 'string (required, must match an NPC id)',
  objectives: [{
    id: 'string (required)',
    type: 'kill | collect | talk | explore | escort',
    targetId: 'string (required — enemy type / item id / npc id / cell label)',
    targetName: 'string (required — display name)',
    requiredCount: 'number (>= 1)',
    cell: 'string? (e.g. "K10" — turns an EXPLORE objective into a grid-cell waypoint)',
    zoneId: 'string? (zone for cell objectives; defaults to the NPC\'s zone)',
  }],
  rewards: {
    experience: 'number',
    gold: 'number',
    items: [{ itemId: 'string', quantity: 'number' }],
  },
  offerDialog: '[{ speaker?, text, emote? }] — pages shown when offering the quest',
  inProgressDialog: '[{ speaker?, text, emote? }] — pages shown while quest is active',
  turnInDialog: '[{ speaker?, text, emote? }] — pages shown at turn-in',
};

export function createQuestsRouter(services: ApiServices): Router {
  const router = Router();
  const questSys: QuestSystem = services.questSys;

  router.get('/schema', (_req, res) => {
    res.json(QUEST_SCHEMA);
  });

  router.get('/', (req, res) => {
    let quests = questSys.getAllQuestDefinitions();
    const npcFilter = req.query.npc as string | undefined;
    const typeFilter = req.query.type as string | undefined;
    const minLevel = req.query.minLevel ? parseInt(req.query.minLevel as string, 10) : undefined;
    const maxLevel = req.query.maxLevel ? parseInt(req.query.maxLevel as string, 10) : undefined;
    if (npcFilter) quests = quests.filter(q => q.npcId === npcFilter);
    if (typeFilter) quests = quests.filter(q => q.type === typeFilter);
    if (typeof minLevel === 'number' && !Number.isNaN(minLevel)) quests = quests.filter(q => q.requiredLevel >= minLevel);
    if (typeof maxLevel === 'number' && !Number.isNaN(maxLevel)) quests = quests.filter(q => q.requiredLevel <= maxLevel);
    res.json({ count: quests.length, quests });
  });

  router.get('/:id', (req, res) => {
    const def = questSys.getQuestDefinition(req.params.id);
    if (!def) {
      res.status(404).json({ error: 'Quest not found' });
      return;
    }
    res.json(def);
  });

  router.post('/', async (req, res) => {
    const result = await questSys.createQuest(req.body);
    if (!result.success) {
      res.status(400).json({ error: result.error });
      return;
    }
    res.status(201).json({ success: true, id: req.body.id });
  });

  router.put('/:id', async (req, res) => {
    const body = { ...req.body, id: req.params.id };
    const result = await questSys.createQuest(body);
    if (!result.success) {
      res.status(400).json({ error: result.error });
      return;
    }
    res.json({ success: true, id: body.id });
  });

  router.delete('/:id', async (req, res) => {
    const result = await questSys.deleteQuest(req.params.id);
    if (!result.success) {
      res.status(404).json({ error: result.error });
      return;
    }
    res.json({ success: true });
  });

  router.post('/reload', async (_req, res) => {
    await questSys.reload();
    res.json({ success: true, count: questSys.getAllQuestDefinitions().length });
  });

  return router;
}
