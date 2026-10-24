import { Socket } from 'socket.io';
import {
  Packet, PacketType, PlayerSession, isZonePvpEnabled, GAME_CONFIG,
  StatusEffectType,
} from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.ATTACK, handleAttack);
  registry.set(PacketType.MANUAL_ATTACK, handleManualAttack);
  registry.set(PacketType.STANCE_UPDATE, handleStanceUpdate);
  registry.set(PacketType.ANIM_DEBUG, handleAnimDebug);
}

// Sheath/drawn stance report: store it and rebroadcast to the zone so other
// clients render the stance immediately. Only transitions are sent by the
// client; the server additionally rate-limits and drops no-op restates so
// keybind mashing can't spam the zone.
function handleStanceUpdate(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  const drawn = !!data?.drawn;
  const now = Date.now();
  // A spell about to cast pins the stance — sheathe requests are refused.
  if (!drawn && session.activeCast) return;
  if (session.weaponDrawn === drawn) return;
  if (session.lastStanceAt && now - session.lastStanceAt < 150) return;
  session.weaponDrawn = drawn;
  session.lastStanceAt = now;

  // Sheathing drops the block stance (stationary or Defensive March alike) —
  // same rule as moving. The effect change rides back before the stance
  // broadcast so the blocker's own client sees the gait release immediately.
  if (!drawn) {
    const blockFx = session.statusEffects?.find(e => e.type === StatusEffectType.BUFF_BLOCKING_STANCE);
    if (blockFx) {
      session.statusEffects = session.statusEffects.filter(e => e !== blockFx);
      ctx.removeBlockingProtectedBuffs(characterId);
      ctx.sendToPlayer(characterId, {
        type: PacketType.STATUS_EFFECT_UPDATE,
        timestamp: Date.now(),
        data: { effects: session.statusEffects }
      });
      ctx.broadcastEntityEffects(session);
    }
  }

  ctx.broadcastInZone(session.zoneId, {
    type: PacketType.ENTITY_STANCE,
    timestamp: now,
    data: { entityId: characterId, drawn }
  }, characterId);
}

// Animation-playback debug relay: the client reports every clip it plays.
function handleAnimDebug(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id) || '?';
  console.log(`[anim-debug] ${characterId}: ${data?.msg ?? ''}`);
}

// Auto-attack cadence for animation timing: the client scales the swing clip
// so it fills this interval (same formula as the client's own cooldown gate).
function attackIntervalMs(session: PlayerSession): number {
  const speed = session.stats?.castSpeed || 0;
  if (speed > 0) {
    return Math.max(GAME_CONFIG.AUTO_ATTACK_MIN_COOLDOWN, GAME_CONFIG.AUTO_ATTACK_BASE_COOLDOWN / speed);
  }
  return GAME_CONFIG.AUTO_ATTACK_BASE_COOLDOWN;
}

function handleAttack(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  if (session.currentNpcId) return;
  // No auto-attacks while a skill is channeling.
  if (session.activeCast) return;
  // No auto-attacks while blocking (stationary or Defensive March) — the
  // stance holds and this packet is silently dropped. Manual swings land via
  // MANUAL_ATTACK, which drops the stance instead.
  if (session.statusEffects?.some(e => e.type === StatusEffectType.BUFF_BLOCKING_STANCE)) return;

  ctx.cancelRest(session);

  if (data.targetId && ctx.state.players.has(data.targetId) && ctx.isPartyMember(characterId, data.targetId)) return;

  if (data.targetId && data.targetId !== characterId && ctx.state.players.has(data.targetId) && !isZonePvpEnabled(session.zoneId)) {
    return;
  }

  const damageInfos = ctx.combat.processPlayerAttack(
    session,
    data.targetId,
    ctx.spawnMgr.getEnemiesInZone(session.zoneId) || new Map(),
    ctx.state.players
  );

  if (damageInfos.length > 0) {
    session.lastAttackTime = Date.now();
  }

  ctx.broadcastInZone(session.zoneId, {
    type: PacketType.ENTITY_ANIMATION,
    timestamp: Date.now(),
    data: { entityId: characterId, animation: 'Attack', intervalMs: attackIntervalMs(session) }
  }, characterId);

  for (const damageInfo of damageInfos) {

    const enemy = ctx.spawnMgr.getEnemy(data.targetId);
    const player = ctx.state.players.get(data.targetId);

    if (player && data.targetId !== characterId) {
      const totalAutoDmg = damageInfo.damage + (damageInfo.elementalDamage?.reduce((s: number, e: any) => s + e.damage, 0) || 0);
      const autoDmgResult = ctx.applyPlayerDamage(player, totalAutoDmg, characterId, damageInfo.damageType || 'physical', damageInfo.isCritical || false, session.zoneId, session.position);
      if (!damageInfo.missed && damageInfo.damage > 0) {
        ctx.processGloomRecoil(session);
      }
      ctx.broadcastInZone(session.zoneId, {
        type: PacketType.DAMAGE,
        timestamp: Date.now(),
        data: { ...damageInfo, damage: autoDmgResult.redirected ? 0 : autoDmgResult.damageTaken, missed: autoDmgResult.redirected ? true : damageInfo.missed }
      });
      if (!autoDmgResult.redirected) {
        ctx.sendToPlayer(data.targetId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: data.targetId, stats: player.stats, statBreakdown: player.statBreakdown, skillProficiencies: player.skillProficiencies, skillAdeptness: player.skillAdeptness }
        });
        if (!damageInfo.missed && damageInfo.damage > 0) {
          ctx.processOnHitProcs(session, data.targetId, damageInfo.damage, (damageInfo.damageType || 'physical') === 'physical');
        }
        if (player.stats.health <= 0) {
          ctx.handlePlayerDeath(player);
        }
      }
    } else {
      if (!damageInfo.missed && damageInfo.damage > 0) {
        ctx.processGloomRecoil(session);
      }
      ctx.broadcastInZone(session.zoneId, {
        type: PacketType.DAMAGE,
        timestamp: Date.now(),
        data: { ...damageInfo }
      });
    }

    if (enemy) {
      if (damageInfo.elementalDamage) {
        for (const el of damageInfo.elementalDamage) {
          ctx.damageEnemy(enemy, el.damage, characterId);
        }
      }
      if (!damageInfo.missed && damageInfo.damage > 0) {
        ctx.enmity.addDamageEnmity(enemy, characterId, damageInfo.damage);
        if (enemy.health > 0) {
          ctx.processOnHitProcs(session, data.targetId, damageInfo.damage, true);
        }
      } else if (damageInfo.missed) {
        ctx.enmity.addEnmity(enemy, characterId, 50, 0);
      }
      ctx.broadcastInZone(session.zoneId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { entityId: data.targetId, health: enemy.health, maxHealth: enemy.maxHealth }
      });
    }
  }
}

function handleManualAttack(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session || session.isDead) return;

  if (session.currentNpcId) return;
  // No manual attacks while a skill is channeling.
  if (session.activeCast) return;

  // A manual swing drops the block stance (stationary block or Defensive
  // March alike) — attack input doubles as the stance cancel, action-game
  // style. The effect change is broadcast before the swing resolves.
  const blockFx = session.statusEffects?.find(e => e.type === StatusEffectType.BUFF_BLOCKING_STANCE);
  if (blockFx) {
    session.statusEffects = session.statusEffects.filter(e => e !== blockFx);
    ctx.removeBlockingProtectedBuffs(characterId);
    ctx.sendToPlayer(characterId, {
      type: PacketType.STATUS_EFFECT_UPDATE,
      timestamp: Date.now(),
      data: { effects: session.statusEffects }
    });
    ctx.broadcastEntityEffects(session);
  }

  ctx.cancelRest(session);

  ctx.broadcastInZone(session.zoneId, {
    type: PacketType.ENTITY_ANIMATION,
    timestamp: Date.now(),
    data: { entityId: characterId, animation: 'Attack', intervalMs: attackIntervalMs(session) }
  }, characterId);

  const zoneEnemies = ctx.spawnMgr.getEnemiesInZone(session.zoneId) || new Map();
  const zonePlayerBuf = new Map<string, PlayerSession>();
  if (isZonePvpEnabled(session.zoneId)) {
    ctx.forEachPlayerInZone(session.zoneId, (id, p) => zonePlayerBuf.set(id, p));
  }

  const results = ctx.combat.processManualAttack(
    session,
    data.facingAngle,
    zoneEnemies,
    zonePlayerBuf,
    session.zoneId
  ).filter((r: any) => !ctx.state.players.has(r.targetId) || r.targetId === characterId || !ctx.isPartyMember(characterId, r.targetId));

  for (const info of results) {
    const enemy = ctx.spawnMgr.getEnemy(info.targetId);
    const pTarget = ctx.state.players.get(info.targetId);

    if (pTarget && info.targetId !== characterId) {
      const manualTotal = info.damage + (info.elementalDamage?.reduce((s: number, e: any) => s + e.damage, 0) || 0);
      const manualDmgResult = ctx.applyPlayerDamage(pTarget, manualTotal, characterId, info.damageType || 'physical', info.isCritical || false, session.zoneId, session.position);
      if (!info.missed && info.damage > 0) {
        ctx.processGloomRecoil(session);
      }
      ctx.broadcastInZone(session.zoneId, {
        type: PacketType.DAMAGE,
        timestamp: Date.now(),
        data: { ...info, damage: manualDmgResult.redirected ? 0 : manualDmgResult.damageTaken, missed: manualDmgResult.redirected ? true : info.missed }
      });
      if (!manualDmgResult.redirected) {
        ctx.sendToPlayer(info.targetId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: info.targetId, stats: pTarget.stats, statBreakdown: pTarget.statBreakdown, skillProficiencies: pTarget.skillProficiencies, skillAdeptness: pTarget.skillAdeptness }
        });
        if (!info.missed && info.damage > 0) {
          ctx.processOnHitProcs(session, info.targetId, info.damage, (info.damageType || 'physical') === 'physical');
        }
        if (pTarget.stats.health <= 0) {
          ctx.handlePlayerDeath(pTarget);
        }
      }
    } else {
      if (!info.missed && info.damage > 0) {
        ctx.processGloomRecoil(session);
      }
      ctx.broadcastInZone(session.zoneId, {
        type: PacketType.DAMAGE,
        timestamp: Date.now(),
        data: { ...info }
      });
    }

    if (enemy) {
      if (!info.missed && info.damage > 0) {
        const manualTotalDmg = info.damage + (info.elementalDamage?.reduce((s: number, e: any) => s + e.damage, 0) || 0);
        ctx.enmity.addDamageEnmity(enemy, characterId, manualTotalDmg);
        if (enemy.health > 0) {
          ctx.processOnHitProcs(session, info.targetId, info.damage, true);
        }
      } else if (info.missed) {
        ctx.enmity.addEnmity(enemy, characterId, 50, 0);
      }
      ctx.broadcastInZone(session.zoneId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { entityId: info.targetId, health: enemy.health, maxHealth: enemy.maxHealth }
      });
    }
  }
}
