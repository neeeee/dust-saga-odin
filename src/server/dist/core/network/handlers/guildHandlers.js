"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerHandlers = registerHandlers;
const shared_1 = require("@dust-saga/shared");
function registerHandlers(registry) {
    registry.set(shared_1.PacketType.GUILD_CREATE, handleGuildCreate);
    registry.set(shared_1.PacketType.GUILD_INVITE, handleGuildInvite);
    registry.set(shared_1.PacketType.GUILD_JOIN_REQUEST, handleGuildJoin);
    registry.set(shared_1.PacketType.GUILD_LEAVE, handleGuildLeave);
    registry.set(shared_1.PacketType.GUILD_DISBAND, handleGuildDisband);
    registry.set(shared_1.PacketType.GUILD_KICK, handleGuildKick);
    registry.set(shared_1.PacketType.GUILD_RANK_SET, handleGuildRankSet);
    registry.set(shared_1.PacketType.GUILD_RANK_PERMS, handleGuildRankPerms);
    registry.set(shared_1.PacketType.GUILD_MOTD, handleGuildMotd);
    registry.set(shared_1.PacketType.GUILD_BANK_GOLD, handleGuildBankGold);
    registry.set(shared_1.PacketType.GUILD_BANK_ITEM, handleGuildBankItem);
}
function sessionOf(ctx, socket) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return null;
    const session = ctx.state.players.get(characterId);
    return session || null;
}
function handleGuildCreate(ctx, socket, data) {
    const session = sessionOf(ctx, socket);
    if (!session)
        return;
    void ctx.guildSys.createGuild(session, data.name, data.tag);
}
function handleGuildInvite(ctx, socket, data) {
    const session = sessionOf(ctx, socket);
    if (!session)
        return;
    void ctx.guildSys.invite(session, data.targetId);
}
function handleGuildJoin(ctx, socket, data) {
    const session = sessionOf(ctx, socket);
    if (!session || !data.guildId)
        return;
    void ctx.guildSys.joinInvite(session, data.guildId, data.accept !== false);
}
function handleGuildLeave(ctx, socket, _data) {
    const session = sessionOf(ctx, socket);
    if (!session)
        return;
    void ctx.guildSys.leave(session);
}
function handleGuildDisband(ctx, socket, _data) {
    const session = sessionOf(ctx, socket);
    if (!session)
        return;
    void ctx.guildSys.disbandGuild(session);
}
function handleGuildKick(ctx, socket, data) {
    const session = sessionOf(ctx, socket);
    if (!session)
        return;
    void ctx.guildSys.kick(session, data.characterId);
}
function handleGuildRankSet(ctx, socket, data) {
    const session = sessionOf(ctx, socket);
    if (!session)
        return;
    void ctx.guildSys.setRank(session, data.characterId, data.rank);
}
function handleGuildRankPerms(ctx, socket, data) {
    const session = sessionOf(ctx, socket);
    if (!session)
        return;
    void ctx.guildSys.setRankPerms(session, data.rank, data.perms || {});
}
function handleGuildMotd(ctx, socket, data) {
    const session = sessionOf(ctx, socket);
    if (!session)
        return;
    void ctx.guildSys.setMotd(session, data.motd);
}
function handleGuildBankGold(ctx, socket, data) {
    const session = sessionOf(ctx, socket);
    if (!session)
        return;
    const amount = typeof data.amount === 'number' ? data.amount : Number(data.amount) || 0;
    void ctx.guildSys.bankGold(session, amount);
}
function handleGuildBankItem(ctx, socket, data) {
    const session = sessionOf(ctx, socket);
    if (!session)
        return;
    const qty = typeof data.quantity === 'number' ? data.quantity : Number(data.quantity) || 0;
    void ctx.guildSys.bankItem(session, data.itemId, qty, (s, itemId, n) => ctx.playerSys.removeItemFromInventory(s, itemId, n), (s, itemId, n) => ctx.playerSys.addItemToInventory(s, itemId, n));
    // Inventory changed either way — sync.
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.INVENTORY_UPDATE,
        timestamp: Date.now(),
        data: { inventory: session.inventory, equipment: session.equipment },
    });
}
