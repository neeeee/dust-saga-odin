"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CUTSCENE_DATABASE = void 0;
exports.getCutscene = getCutscene;
/**
 * Master cutscene registry. Populated from the `cutscenes` DB table at boot
 * by CutsceneSystem.initialize(). Scripts here are the in-memory cache used
 * at runtime; the DB is the source of truth.
 */
exports.CUTSCENE_DATABASE = {};
function getCutscene(id) {
    return exports.CUTSCENE_DATABASE[id];
}
