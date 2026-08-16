import { Socket } from 'socket.io';
import {
  Packet, PacketType, ZoneType, JOB_DEFINITIONS, getZoneDefinition, StatusEffectType,
} from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.ENTER_ZONE, handleEnterZone);
}

async function handleEnterZone(ctx: NetworkContext, socket: Socket, data: any): Promise<void> {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  const targetZone = getZoneDefinition(data.zoneId);
  if (!targetZone) return;

  // Zone access check: zones default to unlocked unless explicitly locked
  if (targetZone.unlockedByDefault === false) {
    const unlocked = session.unlockedZones || [];
    if (!unlocked.includes(data.zoneId)) {
      ctx.sendToPlayer(characterId, {
        type: PacketType.NOTIFICATION,
        timestamp: Date.now(),
        data: { message: 'This area is locked. Complete the main scenario to gain access.', type: 'error' }
      });
      return;
    }
  }

  const oldZoneId = session.zoneId;

  // ── Cross-shard handoff check ────────────────────────────────────────────
  // When ZONE_OWNERSHIP is configured and the target zone belongs to another
  // shard, serialize the live session to Redis, tear down locally, and send a
  // ZONE_HANDOFF redirect. The client reconnects to the new shard, which picks
  // up the session from Redis on character-select. In single-process mode
  // (no ZONE_OWNERSHIP) getOwner always returns the local shard — this branch
  // is never taken.
  const targetShard = await ctx.zoneOwnership.getOwner(data.zoneId);
  if (targetShard !== ctx.zoneOwnership.getShardId()) {
    const ok = await ctx.initiateZoneHandoff(session);
    if (ok) {
      ctx.completeZoneHandoffDeparture(session);
      ctx.sendToPlayer(characterId, {
        type: PacketType.ZONE_HANDOFF,
        timestamp: Date.now(),
        data: {
          targetShard,
          shardUrl: ctx.zoneOwnership.getShardUrl(),
          characterId,
        },
      });
      return;
    }
    // Handoff failed (Redis unavailable) — fall through to local zone transition
  }

  // ── Same-shard zone transition with leak fixes ───────────────────────────
  // Clean up zone-local resources (summons, AOE, song, dummies) BEFORE
  // mutating zoneId. This fixes the long-standing leak where these resources
  // persisted in the old zone after the player left.
  ctx.cleanupPlayerZoneResources(session);

  ctx.broadcastInZone(oldZoneId, {
    type: PacketType.ENTITY_DESPAWN,
    timestamp: Date.now(),
    data: { entityId: characterId }
  });

  session.zoneId = data.zoneId;
  session.currentNpcId = null;
  if (targetZone.type === ZoneType.SAFE || targetZone.type === ZoneType.NATION) {
    session.lastSafeZoneId = data.zoneId;
  }
  session.position = { ...targetZone.playerSpawn };
  session.invulnerableUntil = Date.now() + 3000;

  ctx.movePlayerToZone(characterId, data.zoneId);

  ctx.broadcastInZone(data.zoneId, {
    type: PacketType.ENTITY_SPAWN,
    timestamp: Date.now(),
    data: {
      id: characterId,
      type: 'player',
      position: session.position,
      rotation: session.rotation,
      data: { name: session.characterName, class: session.jobId, race: session.race, jobId: session.jobId, level: session.stats.level, health: session.stats.health, maxHealth: session.stats.maxHealth, modelFile: JOB_DEFINITIONS[session.jobId]?.modelFile, invisible: session.statusEffects?.some((e: any) => e.type === StatusEffectType.INVISIBLE) || false, isResting: session.isResting }
    }
  });

  ctx.sendZoneState(socket, data.zoneId, characterId);

  session.lastQuestCell = null;
  ctx.checkQuestCellEntry(session);

  const exploreProgress = ctx.questSys.onExplore(session, data.zoneId);
  if (exploreProgress.progressed.length > 0) {
    const msgs = exploreProgress.completed.map(qid => {
      const def = ctx.questSys.getQuestDefinition(qid);
      return `Quest "${def?.title || qid}" completed! Return to the NPC.`;
    });
    ctx.sendToPlayer(characterId, {
      type: PacketType.QUEST_PROGRESS,
      timestamp: Date.now(),
      data: { quests: session.quests, message: msgs.join('\n') }
    });
  }

  ctx.sendToPlayer(characterId, {
    type: PacketType.ENTER_ZONE,
    timestamp: Date.now(),
    data: { zoneId: data.zoneId, position: session.position }
  });
}
