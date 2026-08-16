import { Socket } from 'socket.io';
import {
  Packet, PacketType, StatType,
} from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.STAT_ALLOCATE, handleStatAllocate);
  registry.set(PacketType.SKILL_ALLOCATE, handleSkillAllocate);
  registry.set(PacketType.JOB_ADVANCE, handleJobAdvance);
}

function handleStatAllocate(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  if (data.allocations && typeof data.allocations === 'object') {
    const alloc = data.allocations as Record<string, number>;
    for (const [stat, count] of Object.entries(alloc)) {
      const st = stat as StatType;
      const n = Math.floor(count);
      for (let i = 0; i < n; i++) {
        ctx.playerSys.allocateStatPoint(session, st);
      }
    }
  } else {
    const stat = data.stat as StatType;
    if (!stat) return;
    ctx.playerSys.allocateStatPoint(session, stat);
  }

  ctx.sendToPlayer(characterId, {
    type: PacketType.STATS_UPDATE,
    timestamp: Date.now(),
    data: {
      characterId,
      stats: session.stats,
      statPoints: session.statPoints,
      unspentStatPoints: session.unspentStatPoints,
      unspentSkillPoints: session.unspentSkillPoints,
      statBreakdown: session.statBreakdown,
    }
  });
}

function handleSkillAllocate(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  let anySuccess = false;

  if (data.allocations && typeof data.allocations === 'object') {
    const alloc = data.allocations as Record<string, number>;
    for (const [subCat, count] of Object.entries(alloc)) {
      const n = Math.floor(count);
      if (ctx.playerSys.allocateSkillPoint(session, subCat, n)) {
        anySuccess = true;
      }
    }
  } else {
    const subCategoryName = data.subCategoryName as string;
    const count = typeof data.count === 'number' ? Math.floor(data.count) : 1;
    if (subCategoryName) {
      anySuccess = ctx.playerSys.allocateSkillPoint(session, subCategoryName, count);
    }
  }

  if (anySuccess) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: {
        characterId,
        stats: session.stats,
        statPoints: session.statPoints,
        unspentStatPoints: session.unspentStatPoints,
        unspentSkillPoints: session.unspentSkillPoints,
        skillProficiencies: session.skillProficiencies,
        skillAdeptness: session.skillAdeptness,
        statBreakdown: session.statBreakdown,
      }
    });
  }
}

function handleJobAdvance(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  if (ctx.playerSys.advanceJob(session, data.jobId)) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: {
        characterId,
        stats: session.stats,
        jobId: session.jobId,
        baseClass: session.baseClass
      }
    });
  }
}
