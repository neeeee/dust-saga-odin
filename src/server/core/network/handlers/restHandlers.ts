import { Socket } from 'socket.io';
import { Packet, PacketType } from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.PLAYER_REST, handleRest);
}

function handleRest(ctx: NetworkContext, socket: Socket, _data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  if (session.isDead) return;
  if (session.currentNpcId) return;
  if (session.activeCast) return;

  if (session.isResting) {
    ctx.cancelRest(session);
  } else {
    session.isResting = true;
    session.restStartedAt = Date.now();
    session.lastRegenTick = Date.now();

    ctx.broadcastInZone(session.zoneId, {
      type: PacketType.PLAYER_REST,
      timestamp: Date.now(),
      data: { characterId, isResting: true }
    });
  }
}
