import { Socket } from 'socket.io';
import {
  Packet, PacketType, StatusEffectType, Validator,
} from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.PLAYER_MOVE, handlePlayerMove);
}

const MOVE_BROADCAST_INTERVAL = 50;

function handlePlayerMove(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  if (session.currentNpcId) return;

  if (!Validator.validatePosition(data.position)) return;

  const prevPos = session.position;
  const moved = prevPos && (
    Math.abs(data.position.x - prevPos.x) > 0.01 ||
    Math.abs(data.position.y - prevPos.y) > 0.01 ||
    Math.abs(data.position.z - prevPos.z) > 0.01
  );

  session.position = data.position;
  if (data.rotation) {
    session.rotation = data.rotation;
  }
  ctx.updatePlayerSpatialPosition(characterId, { x: data.position.x, z: data.position.z });

  ctx.checkQuestCellEntry(session);

  if (moved) {
    if (session.isResting) {
      ctx.cancelRest(session);
    }

    if (session.activeCast) {
      const castSkillName = session.activeCast.skillName;
      session.activeCast = null;
      ctx.sendToPlayer(session.characterId, {
        type: PacketType.COOLDOWN_UPDATE,
        timestamp: Date.now(),
        data: { skillName: castSkillName, type: 'cast_cancel' }
      });
    }

    const blockingEffect = session.statusEffects?.find(
      (e: any) => e.type === StatusEffectType.BUFF_BLOCKING_STANCE && e.buffData?.blockingStance && !e.buffData?.defensiveMarch
    );
    if (blockingEffect) {
      session.statusEffects = session.statusEffects.filter((e: any) => e !== blockingEffect);
      ctx.removeBlockingProtectedBuffs(session.characterId);
      ctx.playerSys.recalcStats(session);
      ctx.sendToPlayer(session.characterId, {
        type: PacketType.STATUS_EFFECT_UPDATE,
        timestamp: Date.now(),
        data: { effects: session.statusEffects }
      });
      ctx.sendToPlayer(session.characterId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown, skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness }
      });
      ctx.broadcastEntityEffects(session);
    }

    const invisIdx = session.statusEffects?.findIndex(
      (e: any) => e.type === StatusEffectType.INVISIBLE && e.buffData?.invisible?.stationaryOnly
    );
    if (invisIdx !== undefined && invisIdx !== -1) {
      session.statusEffects.splice(invisIdx, 1);
      ctx.sendToPlayer(session.characterId, {
        type: PacketType.STATUS_EFFECT_UPDATE,
        timestamp: Date.now(),
        data: { effects: session.statusEffects }
      });
      ctx.playerSys.recalcStats(session);
      ctx.sendToPlayer(session.characterId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown, skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness }
      });
      ctx.broadcastEntityEffects(session);
    }
  }

  const now = Date.now();
  const last = ctx.getLastMoveBroadcast(characterId);
  if (now - last >= MOVE_BROADCAST_INTERVAL) {
    ctx.setLastMoveBroadcast(characterId, now);
    const isInvis = session.statusEffects?.some((e: any) => e.type === StatusEffectType.INVISIBLE) || false;
    ctx.broadcastInZone(session.zoneId, {
      type: PacketType.PLAYER_POSITION_UPDATE,
      timestamp: Date.now(),
      data: {
        socketId: socket.id,
        characterId,
        position: data.position,
        rotation: data.rotation || session.rotation,
        invisible: isInvis,
        isMoving: !!moved
      }
    }, characterId);
  }
}
