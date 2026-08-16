"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerHandlers = registerHandlers;
const shared_1 = require("@dust-saga/shared");
function registerHandlers(registry) {
    registry.set(shared_1.PacketType.PLAYER_REST, handleRest);
}
function handleRest(ctx, socket, _data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    if (session.isDead)
        return;
    if (session.currentNpcId)
        return;
    if (session.activeCast)
        return;
    if (session.isResting) {
        ctx.cancelRest(session);
    }
    else {
        session.isResting = true;
        session.restStartedAt = Date.now();
        session.lastRegenTick = Date.now();
        ctx.broadcastInZone(session.zoneId, {
            type: shared_1.PacketType.PLAYER_REST,
            timestamp: Date.now(),
            data: { characterId, isResting: true }
        });
    }
}
