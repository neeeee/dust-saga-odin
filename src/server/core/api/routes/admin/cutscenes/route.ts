import { Router } from 'express';
import type { CutsceneSystem } from '../../../../../systems/CutsceneSystem';
import type { ApiServices } from '../../../index';

export function createCutscenesRouter(services: ApiServices): Router {
  const router = Router();
  const cutsceneSys: CutsceneSystem = services.cutsceneSys;

  router.get('/', (_req, res) => {
    const cutscenes = cutsceneSys.getAllCutscenes();
    res.json({ count: cutscenes.length, cutscenes });
  });

  router.post('/', async (req, res) => {
    const result = await cutsceneSys.createCutscene(req.body);
    if (!result.success) {
      res.status(400).json({ error: result.error });
      return;
    }
    res.status(201).json({ success: true, id: req.body.id });
  });

  router.delete('/:id', async (req, res) => {
    const result = await cutsceneSys.deleteCutscene(req.params.id);
    if (!result.success) {
      res.status(404).json({ error: result.error });
      return;
    }
    res.json({ success: true });
  });

  router.post('/reload', async (_req, res) => {
    await cutsceneSys.reload();
    res.json({ success: true, count: cutsceneSys.getAllCutscenes().length });
  });

  return router;
}
