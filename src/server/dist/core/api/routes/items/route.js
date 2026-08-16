"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createItemsRouter = createItemsRouter;
const express_1 = require("express");
/**
 * PUBLIC read-only item catalog. Mounted at `/api/items` (NOT under
 * `/api/admin`, so `requireAdmin` does not apply).
 *
 * The game client fetches this on boot and merges it over its bundled
 * `ITEM_DATABASE`, so items created via the admin API appear in-game without a
 * client rebuild. Item definitions are not secret (names/stats are surfaced in
 * tooltips anyway), so this needs no auth.
 *
 * Mirrors the admin items router shape (`{ count, items }`) for symmetry.
 */
function createItemsRouter(services) {
    const router = (0, express_1.Router)();
    const itemSys = services.itemSys;
    router.get('/', (_req, res) => {
        const items = itemSys.getAllItemDefinitions();
        res.json({ count: items.length, items });
    });
    router.get('/:id', (req, res) => {
        const def = itemSys.getItemDefinition(req.params.id);
        if (!def) {
            res.status(404).json({ error: 'Item not found' });
            return;
        }
        res.json(def);
    });
    return router;
}
