import { Socket } from 'socket.io';
import { Packet, PacketType } from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.FRIEND_LIST_REQUEST, handleFriendListRequest);
  registry.set(PacketType.FRIEND_ADD, handleFriendAdd);
  registry.set(PacketType.FRIEND_REMOVE, handleFriendRemove);
  registry.set(PacketType.FRIEND_REQUEST_RESPONSE, handleFriendRequestResponse);
  registry.set(PacketType.WHISPER, handleWhisper);
}

function handleFriendListRequest(ctx: NetworkContext, socket: Socket, _data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;
  void ctx.friendSys.sendFriendList(characterId);
}

// /friend add — sends a consented request; the target's accept creates the
// mutual friendship (see FriendSystem.respondRequest).
function handleFriendAdd(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;
  const session = ctx.state.players.get(characterId);
  if (!session) return;
  void ctx.friendSys.requestFriend(session, typeof data.name === 'string' ? data.name : '');
}

function handleFriendRequestResponse(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;
  const session = ctx.state.players.get(characterId);
  if (!session || !data.characterId) return;
  void ctx.friendSys.respondRequest(session, data.characterId, data.accept !== false);
}

function handleFriendRemove(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;
  void ctx.friendSys.removeFriend(characterId, data.characterId);
}

/** /w <name> <message> — direct tell to any online character (any zone). */
function handleWhisper(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  const to = typeof data.to === 'string' ? data.to.trim() : '';
  const message = typeof data.message === 'string' ? data.message.substring(0, 200).trim() : '';
  if (!to || !message) return;

  if (to.toLowerCase() === session.characterName.toLowerCase()) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.CHAT_MESSAGE,
      timestamp: Date.now(),
      data: { sender: 'System', message: "You can't whisper yourself.", channel: 'system' },
    });
    return;
  }

  let target: { characterId: string; characterName: string } | null = null;
  for (const [, s] of ctx.state.players) {
    if (s.characterName.toLowerCase() === to.toLowerCase()) {
      target = { characterId: s.characterId, characterName: s.characterName };
      break;
    }
  }

  if (!target) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.CHAT_MESSAGE,
      timestamp: Date.now(),
      data: { sender: 'System', message: `${to} is not online.`, channel: 'system' },
    });
    return;
  }

  const deliver = (toId: string, fromName: string, toName: string): Packet => ({
    type: PacketType.WHISPER,
    timestamp: Date.now(),
    data: { from: characterId, fromName, to: toId, toName, message },
  });

  ctx.sendToPlayer(target.characterId, deliver(target.characterId, session.characterName, target.characterName));
  // Echo back so the sender sees their own whisper.
  ctx.sendToPlayer(characterId, deliver(characterId, session.characterName, target.characterName));
}
