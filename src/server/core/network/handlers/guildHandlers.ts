import { Socket } from 'socket.io';
import { PacketType } from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.GUILD_CREATE, handleGuildCreate);
  registry.set(PacketType.GUILD_INVITE, handleGuildInvite);
  registry.set(PacketType.GUILD_JOIN_REQUEST, handleGuildJoin);
  registry.set(PacketType.GUILD_LEAVE, handleGuildLeave);
  registry.set(PacketType.GUILD_DISBAND, handleGuildDisband);
  registry.set(PacketType.GUILD_KICK, handleGuildKick);
  registry.set(PacketType.GUILD_RANK_SET, handleGuildRankSet);
  registry.set(PacketType.GUILD_RANK_PERMS, handleGuildRankPerms);
  registry.set(PacketType.GUILD_MOTD, handleGuildMotd);
  registry.set(PacketType.GUILD_BANK_GOLD, handleGuildBankGold);
  registry.set(PacketType.GUILD_BANK_ITEM, handleGuildBankItem);
}

function sessionOf(ctx: NetworkContext, socket: Socket) {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return null;
  const session = ctx.state.players.get(characterId);
  return session || null;
}

function handleGuildCreate(ctx: NetworkContext, socket: Socket, data: any): void {
  const session = sessionOf(ctx, socket);
  if (!session) return;
  void ctx.guildSys.createGuild(session, data.name, data.tag);
}

function handleGuildInvite(ctx: NetworkContext, socket: Socket, data: any): void {
  const session = sessionOf(ctx, socket);
  if (!session) return;
  void ctx.guildSys.invite(session, data.targetId);
}

function handleGuildJoin(ctx: NetworkContext, socket: Socket, data: any): void {
  const session = sessionOf(ctx, socket);
  if (!session || !data.guildId) return;
  void ctx.guildSys.joinInvite(session, data.guildId, data.accept !== false);
}

function handleGuildLeave(ctx: NetworkContext, socket: Socket, _data: any): void {
  const session = sessionOf(ctx, socket);
  if (!session) return;
  void ctx.guildSys.leave(session);
}

function handleGuildDisband(ctx: NetworkContext, socket: Socket, _data: any): void {
  const session = sessionOf(ctx, socket);
  if (!session) return;
  void ctx.guildSys.disbandGuild(session);
}

function handleGuildKick(ctx: NetworkContext, socket: Socket, data: any): void {
  const session = sessionOf(ctx, socket);
  if (!session) return;
  void ctx.guildSys.kick(session, data.characterId);
}

function handleGuildRankSet(ctx: NetworkContext, socket: Socket, data: any): void {
  const session = sessionOf(ctx, socket);
  if (!session) return;
  void ctx.guildSys.setRank(session, data.characterId, data.rank);
}

function handleGuildRankPerms(ctx: NetworkContext, socket: Socket, data: any): void {
  const session = sessionOf(ctx, socket);
  if (!session) return;
  void ctx.guildSys.setRankPerms(session, data.rank, data.perms || {});
}

function handleGuildMotd(ctx: NetworkContext, socket: Socket, data: any): void {
  const session = sessionOf(ctx, socket);
  if (!session) return;
  void ctx.guildSys.setMotd(session, data.motd);
}

function handleGuildBankGold(ctx: NetworkContext, socket: Socket, data: any): void {
  const session = sessionOf(ctx, socket);
  if (!session) return;
  const amount = typeof data.amount === 'number' ? data.amount : Number(data.amount) || 0;
  void ctx.guildSys.bankGold(session, amount);
}

function handleGuildBankItem(ctx: NetworkContext, socket: Socket, data: any): void {
  const session = sessionOf(ctx, socket);
  if (!session) return;
  const qty = typeof data.quantity === 'number' ? data.quantity : Number(data.quantity) || 0;
  void ctx.guildSys.bankItem(
    session,
    data.itemId,
    qty,
    (s: any, itemId: any, n: any) => ctx.playerSys.removeItemFromInventory(s, itemId, n),
    (s: any, itemId: any, n: any) => ctx.playerSys.addItemToInventory(s, itemId, n),
  );
  // Inventory changed either way — sync.
  ctx.sendToPlayer(session.characterId, {
    type: PacketType.INVENTORY_UPDATE,
    timestamp: Date.now(),
    data: { inventory: session.inventory, equipment: session.equipment },
  });
}
