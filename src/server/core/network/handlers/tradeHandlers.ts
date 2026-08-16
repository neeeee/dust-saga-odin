import { Socket } from 'socket.io';
import { PacketType } from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.TRADE_REQUEST, handleTradeRequest);
  registry.set(PacketType.TRADE_RESPONSE, handleTradeResponse);
  registry.set(PacketType.TRADE_ADD_ITEM, handleTradeAddItem);
  registry.set(PacketType.TRADE_REMOVE_ITEM, handleTradeRemoveItem);
  registry.set(PacketType.TRADE_SET_GOLD, handleTradeSetGold);
  registry.set(PacketType.TRADE_ACCEPT, handleTradeAccept);
  registry.set(PacketType.TRADE_CANCEL, handleTradeCancel);
}

function handleTradeRequest(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  const targetId = data.targetId;
  if (!targetId || targetId === characterId) return;

  const targetSession = ctx.state.players.get(targetId);
  if (!targetSession) return;

  ctx.tradeSys.requestTrade(characterId, session, targetId, targetSession);
}

function handleTradeResponse(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  ctx.tradeSys.respondToInvite(characterId, !!data.accepted);
}

function handleTradeAddItem(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  ctx.tradeSys.addItem(characterId, data.slot, data.quantity || 1);
}

function handleTradeRemoveItem(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  ctx.tradeSys.removeItem(characterId, data.offerIndex);
}

function handleTradeSetGold(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  ctx.tradeSys.setGold(characterId, data.gold || 0);
}

function handleTradeAccept(ctx: NetworkContext, socket: Socket, _data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  ctx.tradeSys.acceptOffer(characterId);
}

function handleTradeCancel(ctx: NetworkContext, socket: Socket, _data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  ctx.tradeSys.cancelTrade(characterId);
}
