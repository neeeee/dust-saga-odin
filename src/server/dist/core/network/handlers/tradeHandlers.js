"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerHandlers = registerHandlers;
const shared_1 = require("@dust-saga/shared");
function registerHandlers(registry) {
    registry.set(shared_1.PacketType.TRADE_REQUEST, handleTradeRequest);
    registry.set(shared_1.PacketType.TRADE_RESPONSE, handleTradeResponse);
    registry.set(shared_1.PacketType.TRADE_ADD_ITEM, handleTradeAddItem);
    registry.set(shared_1.PacketType.TRADE_REMOVE_ITEM, handleTradeRemoveItem);
    registry.set(shared_1.PacketType.TRADE_SET_GOLD, handleTradeSetGold);
    registry.set(shared_1.PacketType.TRADE_ACCEPT, handleTradeAccept);
    registry.set(shared_1.PacketType.TRADE_CANCEL, handleTradeCancel);
}
function handleTradeRequest(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    const targetId = data.targetId;
    if (!targetId || targetId === characterId)
        return;
    const targetSession = ctx.state.players.get(targetId);
    if (!targetSession)
        return;
    ctx.tradeSys.requestTrade(characterId, session, targetId, targetSession);
}
function handleTradeResponse(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    ctx.tradeSys.respondToInvite(characterId, !!data.accepted);
}
function handleTradeAddItem(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    ctx.tradeSys.addItem(characterId, data.slot, data.quantity || 1);
}
function handleTradeRemoveItem(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    ctx.tradeSys.removeItem(characterId, data.offerIndex);
}
function handleTradeSetGold(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    ctx.tradeSys.setGold(characterId, data.gold || 0);
}
function handleTradeAccept(ctx, socket, _data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    ctx.tradeSys.acceptOffer(characterId);
}
function handleTradeCancel(ctx, socket, _data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    ctx.tradeSys.cancelTrade(characterId);
}
