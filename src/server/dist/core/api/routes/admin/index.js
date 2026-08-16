"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createAdminRouter = createAdminRouter;
const express_1 = require("express");
const adminAuth_1 = require("../../middleware/adminAuth");
const route_1 = require("./quests/route");
const route_2 = require("./cutscenes/route");
const route_3 = require("./items/route");
/**
 * Builds the `/api/admin` sub-tree. `requireAdmin` is applied once here so
 * every mounted admin router inherits the token check — individual route files
 * don't need to repeat it.
 */
function createAdminRouter(services) {
    const admin = (0, express_1.Router)();
    admin.use(adminAuth_1.requireAdmin);
    admin.use('/quests', (0, route_1.createQuestsRouter)(services));
    admin.use('/cutscenes', (0, route_2.createCutscenesRouter)(services));
    admin.use('/items', (0, route_3.createItemsRouter)(services));
    return admin;
}
