"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createApiRouter = createApiRouter;
const express_1 = require("express");
const admin_1 = require("./routes/admin");
const route_1 = require("./routes/items/route");
/**
 * Builds the entire `/api` router tree. Mount the result once:
 *
 *   app.use('/api', createApiRouter({ questSys, cutsceneSys, itemSys }))
 *
 * Public read routes (e.g. `/api/items`) are mounted directly; admin write
 * routes live under `/api/admin/*` behind `requireAdmin`.
 */
function createApiRouter(services) {
    const api = (0, express_1.Router)();
    api.use('/items', (0, route_1.createItemsRouter)(services));
    api.use('/admin', (0, admin_1.createAdminRouter)(services));
    return api;
}
