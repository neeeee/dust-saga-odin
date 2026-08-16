import { Socket } from 'socket.io';
import { PacketType } from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.CUTSCENE_COMPLETE, handleCutsceneComplete);
}

/** Client signals the cutscene is done — restore positions and unlock input. */
function handleCutsceneComplete(ctx: NetworkContext, socket: Socket, _data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;
  const session = ctx.state.players.get(characterId);
  if (!session || !session.inCutscene) return;
  ctx.completeCutscene(session);
}
