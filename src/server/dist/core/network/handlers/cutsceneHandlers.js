"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerHandlers = registerHandlers;
const shared_1 = require("@dust-saga/shared");
function registerHandlers(registry) {
    registry.set(shared_1.PacketType.CUTSCENE_COMPLETE, handleCutsceneComplete);
}
/** Client signals the cutscene is done — restore positions and unlock input. */
function handleCutsceneComplete(ctx, socket, _data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session || !session.inCutscene)
        return;
    ctx.completeCutscene(session);
}
