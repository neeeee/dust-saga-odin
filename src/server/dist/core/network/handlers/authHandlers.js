"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerHandlers = registerHandlers;
const shared_1 = require("@dust-saga/shared");
function registerHandlers(registry) {
    registry.set(shared_1.PacketType.LOGIN, handleLogin);
    registry.set(shared_1.PacketType.REGISTER, handleRegister);
}
async function handleLogin(ctx, socket, data) {
    const result = await ctx.auth.login(data.username, data.password);
    if (result.success) {
        ctx.state.socketToPlayer.set(socket.id, result.playerId);
        ctx.sendToSocket(socket.id, {
            type: shared_1.PacketType.AUTH_SUCCESS,
            timestamp: Date.now(),
            data: { playerId: result.playerId, username: result.username, token: result.token, level: result.level, role: result.role }
        });
    }
    else {
        ctx.sendToSocket(socket.id, {
            type: shared_1.PacketType.AUTH_FAILURE,
            timestamp: Date.now(),
            data: { message: result.error }
        });
    }
}
async function handleRegister(ctx, socket, data) {
    const result = await ctx.auth.register(data.username, data.email, data.password);
    if (result.success) {
        ctx.state.socketToPlayer.set(socket.id, result.playerId);
        ctx.sendToSocket(socket.id, {
            type: shared_1.PacketType.AUTH_SUCCESS,
            timestamp: Date.now(),
            data: { playerId: result.playerId, token: result.token }
        });
    }
    else {
        ctx.sendToSocket(socket.id, {
            type: shared_1.PacketType.AUTH_FAILURE,
            timestamp: Date.now(),
            data: { message: result.error }
        });
    }
}
