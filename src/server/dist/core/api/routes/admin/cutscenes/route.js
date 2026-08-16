"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createCutscenesRouter = createCutscenesRouter;
const express_1 = require("express");
function createCutscenesRouter(services) {
    const router = (0, express_1.Router)();
    const cutsceneSys = services.cutsceneSys;
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
