import { Socket } from 'socket.io';
import {
  Packet, PacketType, PlayerSession,
  SKILL_TARGET_RULES, SkillTargetType, SkillType,
  GROUND_TARGETED_AOE_SKILLS, DEFAULT_AOE_RADIUS,
  StatusEffectType, StatusEffect,
  getSkillTargetType,
  BANISH_RADIUS,
  AOETargetMode,
  isZonePvpEnabled,
  isBeneficialSkillType,
  RANGED_WEAPON_TYPES,
} from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';
import { hasLineOfSight } from '../../world/LineOfSight';
import { getObeliskBuffForWeapon } from '../../combat/obeliskBuff';

function checkDevotionMana(ctx: NetworkContext, session: PlayerSession, mpCost: number): boolean {
  if (session.stats.mana >= mpCost) return true;
  const devotionFx = session.statusEffects?.find(e => e.buffData?.devotionLink);
  if (!devotionFx) return false;
  const partnerId = devotionFx.buffData!.devotionLink!.partnerId;
  const partner = ctx.state.players.get(partnerId);
  const combined = session.stats.mana + (partner?.stats.mana || 0);
  return combined >= mpCost;
}

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.SKILL_USE, handleSkillUse);
  registry.set(PacketType.SKILL_CANCEL, handleSkillCancel);
}

function handleSkillCancel(ctx: NetworkContext, socket: Socket, _data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session || !session.activeCast) return;

  const skillName = session.activeCast.skillName;
  session.activeCast = null;
  ctx.sendToPlayer(characterId, {
    type: PacketType.COOLDOWN_UPDATE,
    timestamp: Date.now(),
    data: { skillName, type: 'cast_cancel' }
  });
}

function handleSkillUse(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  const { skillName, targetId, aoePosition } = data;
  if (!skillName) return;

  ctx.cancelRest(session);

  if (aoePosition && GROUND_TARGETED_AOE_SKILLS.has(skillName)) {
    handleGroundAOESkillUse(ctx, session, skillName, aoePosition);
    return;
  }

  const earlySkillDef = ctx.skillSys.findSkillDefinition(skillName);

  if (earlySkillDef?.aoeTargetMode === AOETargetMode.CONE) {
    handleConeSkillUse(ctx, session, skillName, targetId);
    return;
  }

  if (targetId && targetId !== characterId && ctx.state.players.has(targetId) && !isZonePvpEnabled(session.zoneId)) {
    const skillType = ctx.skillSys.getSkillType(skillName);
    if (skillType !== undefined && !isBeneficialSkillType(skillType)) {
      ctx.sendToPlayer(characterId, {
        type: PacketType.SKILL_USE,
        timestamp: Date.now(),
        data: { skillName, error: 'pvp_disabled' }
      });
      return;
    }
  }

  // Obelisk buff is mutually exclusive with Guardian: an Obelisk weapon
  // wielder cannot be protected by Guardian, so refuse to cast Guardian on
  // them (and give the caster immediate feedback).
  if (earlySkillDef?.buffEffectTable?.damageRedirect && targetId && targetId !== characterId) {
    const targetSession = ctx.state.players.get(targetId);
    if (targetSession && getObeliskBuffForWeapon(ctx.itemSys, targetSession.equipment?.weapon)) {
      ctx.sendToPlayer(characterId, {
        type: PacketType.SKILL_USE,
        timestamp: Date.now(),
        data: { skillName, error: 'target_obelisk' }
      });
      return;
    }
  }
  const check = ctx.skillSys.canUseSkill(session, skillName, targetId || null);
  if (!check.canUse) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.SKILL_USE,
      timestamp: Date.now(),
      data: { skillName, error: check.error }
    });
    return;
  }

  // Range check: ensure the target is within attack range.
  // - Beneficial skills (heal/buff) targeting an enemy → skip (they self-cast).
  // - Beneficial skills targeting a friendly → use the skill's range or 25.
  // - Magical skills → 20 (regardless of weapon).
  // - Physical skills: ranged weapon → 20, melee → 4.
  if (targetId && targetId !== characterId && !aoePosition) {
    const ts = ctx.state.players.get(targetId);
    const te = ctx.spawnMgr.getEnemy(targetId);
    const tp = ts?.position || te?.position;
    const isTargetEnemy = !!te && !ts;
    const skillType = (earlySkillDef as any).skillType;
    const isBeneficial = isBeneficialSkillType(skillType) ||
      skillType === SkillType.HEAL || skillType === SkillType.PARTY_HEAL ||
      skillType === SkillType.BUFF || skillType === SkillType.HP_BUFF ||
      skillType === SkillType.MP_RESTORE || skillType === SkillType.REVIVE;

    // Beneficial skill targeting an enemy → will self-cast, skip range check.
    if (!(isBeneficial && isTargetEnemy) && tp && earlySkillDef) {
      const dx = tp.x - session.position.x;
      const dz = tp.z - session.position.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      let maxRange = (earlySkillDef as any).range || 0;
      if (maxRange === 0) {
        const weapon = session.equipment?.weapon as any;
        const wdef = weapon ? ctx.itemSys.getItemDefinition(weapon.itemId) : null;
        const isRangedWeapon = wdef?.weaponType && RANGED_WEAPON_TYPES.has(wdef.weaponType);
        const isMagical = (earlySkillDef as any).damageType === 'magical' ||
                          skillType === SkillType.DAMAGE_MAGICAL;
        maxRange = (isRangedWeapon || isMagical) ? 20 : (isBeneficial ? 25 : 4);
      }
      if (dist > maxRange) {
        ctx.sendToPlayer(characterId, {
          type: PacketType.SKILL_USE, timestamp: Date.now(),
          data: { skillName, error: 'out_of_range' }
        });
        return;
      }
    }
  }

  const mpCost = earlySkillDef?.mpCost || 0;
  if (mpCost > 0 && !checkDevotionMana(ctx, session, mpCost)) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.SKILL_USE,
      timestamp: Date.now(),
      data: { skillName, error: 'no_mana' }
    });
    return;
  }

  if (earlySkillDef?.lineOfSightRequired && targetId) {
    const targetSession = ctx.state.players.get(targetId);
    const targetEnemy = ctx.spawnMgr.getEnemy(targetId);
    if (targetSession || targetEnemy) {
      const targetPos = targetSession?.position || targetEnemy?.position;
      if (targetPos && !hasLineOfSight(session.zoneId, { x: session.position.x, z: session.position.z }, { x: targetPos.x, z: targetPos.z })) {
        ctx.sendToPlayer(characterId, {
          type: PacketType.SKILL_USE,
          timestamp: Date.now(),
          data: { skillName, error: 'no_los' }
        });
        return;
      }
    }
  }

  const skillTargetRule = SKILL_TARGET_RULES[skillName];
  const effectiveTargetType = earlySkillDef ? getSkillTargetType(earlySkillDef) : undefined;
  const resolvedTargetType = effectiveTargetType || skillTargetRule;
  const isHarmfulSkill = !resolvedTargetType || resolvedTargetType === SkillTargetType.OTHER_ONLY;
  const isBuffSkill = earlySkillDef?.isBuff || !!earlySkillDef?.buffEffectTable || earlySkillDef?.isRevive || earlySkillDef?.skillType === SkillType.REVIVE || earlySkillDef?.skillType === SkillType.HEAL || earlySkillDef?.skillType === SkillType.PARTY_HEAL || !!earlySkillDef?.healing;
  if (isHarmfulSkill && !isBuffSkill && targetId && ctx.state.players.has(targetId) && ctx.isPartyMember(characterId, targetId)) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.SKILL_USE,
      timestamp: Date.now(),
      data: { skillName, error: 'party_member' }
    });
    return;
  }

  if (skillName === 'Guardian' && targetId) {
    const party = ctx.partySys.getPartyForMember(characterId);
    if (!party || !party.members.some(m => m.characterId === targetId)) {
      ctx.sendToPlayer(characterId, {
        type: PacketType.SKILL_USE,
        timestamp: Date.now(),
        data: { skillName, error: 'not_in_party' }
      });
      return;
    }
  }

  const skillDef = ctx.skillSys.findSkillDefinition(skillName);
  if (skillDef?.consumableItem) {
    const needed = skillDef.consumableItemQuantity || 1;
    const count = session.inventory.filter(i => i.itemId === skillDef.consumableItem).reduce((s, i) => s + i.quantity, 0);
    if (count < needed) {
      ctx.sendToPlayer(characterId, {
        type: PacketType.SKILL_USE,
        timestamp: Date.now(),
        data: { skillName, error: 'no_materials' }
      });
      return;
    }
    let remaining = needed;
    for (let i = session.inventory.length - 1; i >= 0 && remaining > 0; i--) {
      if (session.inventory[i].itemId === skillDef.consumableItem) {
        const take = Math.min(session.inventory[i].quantity, remaining);
        session.inventory[i].quantity -= take;
        remaining -= take;
        if (session.inventory[i].quantity <= 0) session.inventory.splice(i, 1);
      }
    }
    ctx.sendToPlayer(characterId, {
      type: PacketType.INVENTORY_UPDATE,
      timestamp: Date.now(),
      data: { inventory: session.inventory }
    });
  }

  const { started, castTime } = ctx.skillSys.beginCast(session, skillName, targetId || null);
  if (!started) return;

  const invIdx = session.statusEffects?.findIndex(e => e.type === StatusEffectType.INVISIBLE);
  if (invIdx !== undefined && invIdx !== -1) {
    const skill = ctx.skillSys.findSkillDefinition(skillName);
    if (skill && (skill.basePower || skill.damageType || skill.debuffEffectTable || skill.summonObject || skill.banishObject)) {
      session.statusEffects.splice(invIdx, 1);
      ctx.sendToPlayer(characterId, {
        type: PacketType.STATUS_EFFECT_UPDATE,
        timestamp: Date.now(),
        data: { effects: session.statusEffects }
      });
      ctx.broadcastEntityEffects(session);
    }
  }

  if (castTime > 0) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.COOLDOWN_UPDATE,
      timestamp: Date.now(),
      data: { skillName, castTime, type: 'cast_start' }
    });
    return;
  }

  const skill = ctx.skillSys.findSkillDefinition(skillName);
  const aoeRadius = skill?.aoeRadius || DEFAULT_AOE_RADIUS;
  let firstTargetId: string | null = targetId || null;

  // Beneficial skills (heal, buff) that target an enemy or non-party-member →
  // redirect to self. Buffs/heals should never apply to enemies; the caster
  // heals/buffs themselves instead.
  if (firstTargetId && firstTargetId !== characterId) {
    const st = (earlySkillDef as any).skillType;
    const isBeneficial = isBeneficialSkillType(st) ||
      st === SkillType.HEAL || st === SkillType.PARTY_HEAL ||
      st === SkillType.BUFF || st === SkillType.HP_BUFF ||
      st === SkillType.MP_RESTORE || st === SkillType.REVIVE;
    if (isBeneficial) {
      const targetIsPlayer = ctx.state.players.has(firstTargetId);
      const isPartyMember = targetIsPlayer && ctx.isPartyMember(characterId, firstTargetId);
      if (!isPartyMember) {
        firstTargetId = characterId;
      }
    }
  }

  if (skill?.isAOE && aoePosition) {
    const firstTarget = ctx.findClosestEntityToPosition(
      session, aoePosition, aoeRadius
    );
    firstTargetId = firstTarget?.id || targetId || null;
  }

  const result = ctx.skillSys.executeSkill(session, skillName, firstTargetId, (id) => ctx.getTargetStatsForEntity(id));
  ctx.sendDamageDebug(session, result);
  ctx.playerSys.recalcStats(session);

  if (skill?.isSong && !result.songToggledOff) {
    ctx.applySongPulseImmediate(session);
  }

  if (result.songToggledOff) {
    ctx.removeSongProximityBuffs(session);
    ctx.sendToPlayer(characterId, {
      type: PacketType.STATUS_EFFECT_UPDATE,
      timestamp: Date.now(),
      data: { effects: session.statusEffects }
    });
    ctx.sendToPlayer(characterId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { characterId, stats: session.stats, statBreakdown: session.statBreakdown, skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness }
    });
    ctx.sendToPlayer(characterId, {
      type: PacketType.COOLDOWN_UPDATE,
      timestamp: Date.now(),
      data: { skillName, type: 'used', mpCost: skill?.mpCost || 0, cooldownRemaining: 0 }
    });
    ctx.broadcastEntityEffects(session);
    return;
  }

  ctx.sendToPlayer(characterId, {
    type: PacketType.STATS_UPDATE,
    timestamp: Date.now(),
    data: { characterId, stats: session.stats, statBreakdown: session.statBreakdown, skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness }
  });

  if (ctx.skillSys.lastProficiencyGain) {
    const pg = ctx.skillSys.lastProficiencyGain;
    ctx.sendToPlayer(characterId, {
      type: PacketType.CHAT_MESSAGE,
      timestamp: Date.now(),
      data: { sender: 'Proficiency', message: `${pg.subCategory} +${pg.amount} (${Math.floor(pg.newAdeptness)}/${pg.cap})`, channel: 'system' }
    });
    ctx.skillSys.lastProficiencyGain = undefined;
  }

  ctx.sendToPlayer(characterId, {
    type: PacketType.COOLDOWN_UPDATE,
    timestamp: Date.now(),
    data: {
      skillName,
      type: 'used',
      mpCost: skill?.mpCost || 0,
      cooldownRemaining: session.skillCooldowns.find(c => c.skillName === skillName)?.readyAt
        ? Math.max(0, (session.skillCooldowns.find(c => c.skillName === skillName)!.readyAt - Date.now()))
        : 0
    }
  });

  ctx.broadcastInZone(session.zoneId, {
    type: PacketType.ENTITY_ANIMATION,
    timestamp: Date.now(),
    data: { entityId: characterId, animation: 'Attack' }
  }, characterId);

  if (result.createdItems && result.createdItems.length > 0) {
    for (const ci of result.createdItems) {
      if (ci.consumeItems) {
        let canCraft = true;
        for (const mat of ci.consumeItems) {
          const count = session.inventory.filter(i => i.itemId === mat.itemId).reduce((s, i) => s + i.quantity, 0);
          if (count < mat.quantity) { canCraft = false; break; }
        }
        if (!canCraft) continue;
        for (const mat of ci.consumeItems) {
          let remaining = mat.quantity;
          for (let i = session.inventory.length - 1; i >= 0 && remaining > 0; i--) {
            if (session.inventory[i].itemId === mat.itemId) {
              const take = Math.min(session.inventory[i].quantity, remaining);
              session.inventory[i].quantity -= take;
              remaining -= take;
              if (session.inventory[i].quantity <= 0) session.inventory.splice(i, 1);
            }
          }
        }
      }
      ctx.playerSys.addItemToInventory(session, ci.itemId, ci.quantity);
      ctx.sendToPlayer(characterId, {
        type: PacketType.NOTIFICATION,
        timestamp: Date.now(),
        data: { message: `Created: ${ci.itemId} x${ci.quantity}` }
      });
    }
    ctx.sendToPlayer(characterId, {
      type: PacketType.INVENTORY_UPDATE,
      timestamp: Date.now(),
      data: { inventory: session.inventory }
    });
  }

  if (result.sacrificeHeal && result.targetId) {
    const target = ctx.state.players.get(result.targetId);
    if (target) {
      session.stats.health = 0;
      session.isDead = true;
      target.stats.health = target.stats.maxHealth;
    }
  }

  if (result.mpDamage && result.mpDamage > 0 && firstTargetId) {
    const mpTarget = ctx.spawnMgr.getEnemy(firstTargetId);
    if (mpTarget) {
      ctx.broadcastInZone(session.zoneId, {
        type: PacketType.DAMAGE,
        timestamp: Date.now(),
        data: { attackerId: characterId, targetId: firstTargetId, damage: result.mpDamage, damageType: 'mp', skillName }
      });
    } else {
      const playerTarget = ctx.state.players.get(firstTargetId);
      if (playerTarget) {
        playerTarget.stats.mana = Math.max(0, playerTarget.stats.mana - result.mpDamage);
      }
    }
    ctx.broadcastInZone(session.zoneId, {
      type: PacketType.DAMAGE,
      timestamp: Date.now(),
      data: { attackerId: characterId, targetId: firstTargetId, damage: result.mpDamage, damageType: 'mp', skillName }
    });
  }

  if (result.fear && aoePosition) {
    const fearTargets = ctx.findAllEntitiesInRadius(session, aoePosition, aoeRadius);
    for (const ft of fearTargets) {
      const enemy = ctx.spawnMgr.getEnemy(ft.id);
      if (enemy && enemy.state !== 'dead') {
        const angle = Math.random() * Math.PI * 2;
        enemy.position.x += Math.cos(angle) * 10;
        enemy.position.z += Math.sin(angle) * 10;
      }
    }
  }

  if (result.dispelBuff && firstTargetId) {
    const playerTarget = ctx.state.players.get(firstTargetId);
    if (playerTarget) {
      playerTarget.statusEffects = playerTarget.statusEffects.filter(e => !e.buffData);
      playerTarget.effectiveStats = null;
    }
  }

  if (result.dispelDebuff && firstTargetId) {
    const playerTarget = ctx.state.players.get(firstTargetId);
    if (playerTarget) {
      playerTarget.statusEffects = playerTarget.statusEffects.filter(e => !e.debuffCategory);
      playerTarget.effectiveStats = null;
    }
  }

  if (result.summonObject) {
    const summonPos = aoePosition || session.position;
    const summon = ctx.summonMgr.spawnSummon(
      characterId,
      session.characterName,
      session.zoneId,
      result.summonObject,
      summonPos,
      session.rotation?.y || 0,
      result.element,
    );
    if (summon) {
      ctx.broadcastInZone(session.zoneId, {
        type: PacketType.ENTITY_SPAWN,
        timestamp: Date.now(),
        data: {
          id: summon.id,
          type: 'summon',
          position: summon.position,
          rotation: { x: 0, y: summon.rotation, z: 0, w: 1 },
          data: {
            summonType: summon.summonType,
            ownerId: summon.ownerId,
            ownerName: summon.ownerName,
            health: summon.health,
            maxHealth: summon.maxHealth,
            defense: summon.defense,
            element: summon.element,
            duration: summon.duration,
          },
        },
      });
    }
  }

  if (result.banishObject) {
    const center = aoePosition || session.position;
    const banishRadius = result.banishRadius || BANISH_RADIUS;
    const targets = ctx.summonMgr.getSummonsInRadius(session.zoneId, { x: center.x, z: center.z }, banishRadius);
    for (const s of targets) {
      ctx.summonMgr.despawnSummon(s.id);
      ctx.broadcastInZone(s.zoneId, {
        type: PacketType.ENTITY_DESPAWN,
        timestamp: Date.now(),
        data: { entityId: s.id },
      });
    }
  }

  if (result.provoked && result.targetId) {
    const provokeTarget = ctx.spawnMgr.getEnemy(result.targetId);
    if (provokeTarget && provokeTarget.state !== 'dead') {
      ctx.enmity.provokeEnmity(provokeTarget, characterId);
      provokeTarget.targetId = characterId;
      if (provokeTarget.state === 'idle') {
        provokeTarget.state = 'chase';
      } else if (provokeTarget.state === 'return') {
        provokeTarget.state = 'chase';
      }
    }
  }

  if (result.damage) {
    if (aoePosition) {
      ctx.applyAOEDamageToTargets(session, skillName, aoePosition, aoeRadius, result);
    } else if (firstTargetId) {
      ctx.applySingleTargetSkillDamage(session, skillName, firstTargetId, result);
    }
  }

  if (result.statusEffects && result.statusEffects.length > 0) {
    if (aoePosition) {
      const targets = ctx.findAllEntitiesInRadius(session, aoePosition, aoeRadius);
      for (const target of targets) {
        const enemy = ctx.spawnMgr.getEnemy(target.id);
        if (enemy && enemy.state !== 'dead') {
          let anyApplied = false;
          let maxPotency = 0;
          for (const effect of result.statusEffects) {
            if (!ctx.shouldApplyDebuff(effect, target.id, characterId)) continue;
            if (ctx.hasActiveDebuff(target.id, effect.type, effect.skillName)) continue;
            const cloned = { ...effect, targetId: target.id };
            enemy.statusEffects.push(cloned);
            anyApplied = true;
            if (effect.potency > maxPotency) maxPotency = effect.potency;
          }
          if (anyApplied) {
            ctx.enmity.addDebuffEnmity(enemy, characterId, maxPotency, true);
          } else {
            ctx.enmity.addDebuffEnmity(enemy, characterId, 0, false);
          }
          ctx.broadcastInZone(session.zoneId, {
            type: PacketType.ENTITY_STATUS_EFFECTS,
            timestamp: Date.now(),
            data: { entityId: target.id, effects: enemy.statusEffects }
          });
        }
        const playerTarget = ctx.state.players.get(target.id);
        if (playerTarget && target.id !== characterId) {
          for (const effect of result.statusEffects) {
            if (!ctx.shouldApplyDebuff(effect, target.id, characterId)) continue;
            if (ctx.hasActiveDebuff(target.id, effect.type, effect.skillName)) continue;
            const cloned = { ...effect, targetId: target.id };
            playerTarget.statusEffects.push(cloned);
          }
          ctx.playerSys.recalcStats(playerTarget);
          ctx.sendToPlayer(target.id, {
            type: PacketType.STATUS_EFFECT_UPDATE,
            timestamp: Date.now(),
            data: { effects: playerTarget.statusEffects }
          });
          ctx.sendToPlayer(target.id, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: target.id, stats: playerTarget.stats }
          });
        }
      }
    } else if (firstTargetId) {
      const enemy = ctx.spawnMgr.getEnemy(firstTargetId);
      if (enemy && enemy.state !== 'dead') {
        let anyApplied = false;
        let maxPotency = 0;
        for (const effect of result.statusEffects) {
          if (!ctx.shouldApplyDebuff(effect, firstTargetId, characterId)) continue;
          if (ctx.hasActiveDebuff(firstTargetId, effect.type, effect.skillName)) continue;
          const cloned = { ...effect, targetId: firstTargetId };
          enemy.statusEffects.push(cloned);
          anyApplied = true;
          if (effect.potency > maxPotency) maxPotency = effect.potency;
        }
        if (anyApplied) {
          ctx.enmity.addDebuffEnmity(enemy, characterId, maxPotency, true);
        } else {
          ctx.enmity.addDebuffEnmity(enemy, characterId, 0, false);
        }
        ctx.broadcastInZone(session.zoneId, {
          type: PacketType.ENTITY_STATUS_EFFECTS,
          timestamp: Date.now(),
          data: { entityId: firstTargetId, effects: enemy.statusEffects }
        });
      }
      const playerTarget = ctx.state.players.get(firstTargetId);
      if (playerTarget && firstTargetId !== characterId) {
        for (const effect of result.statusEffects) {
          if (!ctx.shouldApplyDebuff(effect, firstTargetId, characterId)) continue;
          if (ctx.hasActiveDebuff(firstTargetId, effect.type, effect.skillName)) continue;
          const cloned = { ...effect, targetId: firstTargetId };
          playerTarget.statusEffects.push(cloned);
        }
        ctx.playerSys.recalcStats(playerTarget);
        ctx.sendToPlayer(firstTargetId, {
          type: PacketType.STATUS_EFFECT_UPDATE,
          timestamp: Date.now(),
          data: { effects: playerTarget.statusEffects }
        });
        ctx.sendToPlayer(firstTargetId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: firstTargetId, stats: playerTarget.stats }
        });
        ctx.broadcastEntityEffects(playerTarget);
      }
    }
  }

  if (result.healing) {
    const healTargetId = firstTargetId && firstTargetId !== characterId ? firstTargetId : null;
    const healTarget = healTargetId ? ctx.state.players.get(healTargetId) : null;
    if (healTarget && !healTarget.isDead) {
      healTarget.stats.health = Math.min(healTarget.stats.maxHealth, healTarget.stats.health + result.healing);
      ctx.playerSys.recalcStats(healTarget);
      ctx.sendToPlayer(healTargetId!, {
        type: PacketType.HEAL,
        timestamp: Date.now(),
        data: { targetId: healTargetId, amount: result.healing }
      });
      ctx.sendToPlayer(healTargetId!, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: healTargetId, stats: healTarget.stats, statBreakdown: healTarget.statBreakdown }
      });
    } else if (!session.isDead) {
      session.stats.health = Math.min(session.stats.maxHealth, session.stats.health + result.healing);
      ctx.sendToPlayer(characterId, {
        type: PacketType.HEAL,
        timestamp: Date.now(),
        data: { targetId: characterId, amount: result.healing }
      });
    }
  }

  if (result.healing && result.healing > 0) {
    const party = ctx.partySys.getPartyForMember(characterId);
    const partyMemberIds = new Set<string>();
    partyMemberIds.add(characterId);
    if (party) {
      for (const m of party.members) {
        partyMemberIds.add(m.characterId);
      }
    }
    ctx.spawnMgr.forEnemiesInZone(session.zoneId, enemy => {
      if (enemy.state === 'dead' || !enemy.enmityTable) return;
      const dx = enemy.position.x - session.position.x;
      const dz = enemy.position.z - session.position.z;
      if (Math.sqrt(dx * dx + dz * dz) > 30) return;
      if (ctx.enmity.hasEnmityWithParty(enemy, partyMemberIds)) {
        ctx.enmity.addHealEnmity(enemy, characterId, result.healing!);
      }
    });
  }

  if (!result.damage && (!result.statusEffects || result.statusEffects.length === 0) && !result.provoked && !result.healing && firstTargetId) {
    const skillDef = ctx.skillSys.findSkillDefinition(skillName);
    if (skillDef) {
      const st = skillDef.skillType;
      if (st === SkillType.DEBUFF || st === SkillType.FEAR || st === SkillType.DISPEL) {
        const fallbackEnemy = ctx.spawnMgr.getEnemy(firstTargetId);
        if (fallbackEnemy && fallbackEnemy.state !== 'dead') {
          ctx.enmity.addDebuffEnmity(fallbackEnemy, characterId, 0, false);
        }
      }
    }
  }

  if (session.statusEffects.length > 0) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.STATUS_EFFECT_UPDATE,
      timestamp: Date.now(),
      data: { effects: session.statusEffects }
    });
  }
}

function handleGroundAOESkillUse(
  ctx: NetworkContext,
  session: PlayerSession,
  skillName: string,
  aoePosition: { x: number; y: number; z: number }
): void {
  const characterId = session.characterId;

  // Ground-targeted AOE: the position IS the target. Pass a dummy non-null
  // targetId so canUseSkill's OTHER_ONLY check (DAMAGE_PHYSICAL → requires
  // target) doesn't reject with 'no_target'.
  const check = ctx.skillSys.canUseSkill(session, skillName, 'ground-aoe');
  if (!check.canUse) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.SKILL_USE,
      timestamp: Date.now(),
      data: { skillName, error: check.error }
    });
    return;
  }

  const groundSkillDef = ctx.skillSys.findSkillDefinition(skillName);
  const groundMpCost = groundSkillDef?.mpCost || 0;
  if (groundMpCost > 0 && !checkDevotionMana(ctx, session, groundMpCost)) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.SKILL_USE,
      timestamp: Date.now(),
      data: { skillName, error: 'no_mana' }
    });
    return;
  }

  if (groundSkillDef?.consumableItem) {
    const needed = groundSkillDef.consumableItemQuantity || 1;
    const count = session.inventory.filter(i => i.itemId === groundSkillDef.consumableItem).reduce((s, i) => s + i.quantity, 0);
    if (count < needed) {
      ctx.sendToPlayer(characterId, {
        type: PacketType.SKILL_USE,
        timestamp: Date.now(),
        data: { skillName, error: 'no_materials' }
      });
      return;
    }
    let remaining = needed;
    for (let i = session.inventory.length - 1; i >= 0 && remaining > 0; i--) {
      if (session.inventory[i].itemId === groundSkillDef.consumableItem) {
        const take = Math.min(session.inventory[i].quantity, remaining);
        session.inventory[i].quantity -= take;
        remaining -= take;
        if (session.inventory[i].quantity <= 0) session.inventory.splice(i, 1);
      }
    }
    ctx.sendToPlayer(characterId, {
      type: PacketType.INVENTORY_UPDATE,
      timestamp: Date.now(),
      data: { inventory: session.inventory }
    });
  }

  const { started, castTime } = ctx.skillSys.beginCast(session, skillName, null, aoePosition);
  if (!started) return;

  if (castTime > 0) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.COOLDOWN_UPDATE,
      timestamp: Date.now(),
      data: { skillName, castTime, type: 'cast_start', aoePosition }
    });
    return;
  }

  ctx.executeAOESkillInternal(session, skillName, aoePosition);
}

function handleConeSkillUse(
  ctx: NetworkContext,
  session: PlayerSession,
  skillName: string,
  targetId: string | null
): void {
  const characterId = session.characterId;

  const check = ctx.skillSys.canUseSkill(session, skillName, targetId);
  if (!check.canUse) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.SKILL_USE,
      timestamp: Date.now(),
      data: { skillName, error: check.error }
    });
    return;
  }

  const skillDef = ctx.skillSys.findSkillDefinition(skillName);
  const mpCost = skillDef?.mpCost || 0;
  if (mpCost > 0 && !checkDevotionMana(ctx, session, mpCost)) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.SKILL_USE,
      timestamp: Date.now(),
      data: { skillName, error: 'no_mana' }
    });
    return;
  }

  if (skillDef?.consumableItem) {
    const needed = skillDef.consumableItemQuantity || 1;
    const count = session.inventory.filter(i => i.itemId === skillDef.consumableItem).reduce((s, i) => s + i.quantity, 0);
    if (count < needed) {
      ctx.sendToPlayer(characterId, {
        type: PacketType.SKILL_USE,
        timestamp: Date.now(),
        data: { skillName, error: 'no_materials' }
      });
      return;
    }
    let remaining = needed;
    for (let i = session.inventory.length - 1; i >= 0 && remaining > 0; i--) {
      if (session.inventory[i].itemId === skillDef.consumableItem) {
        const take = Math.min(session.inventory[i].quantity, remaining);
        session.inventory[i].quantity -= take;
        remaining -= take;
        if (session.inventory[i].quantity <= 0) session.inventory.splice(i, 1);
      }
    }
    ctx.sendToPlayer(characterId, {
      type: PacketType.INVENTORY_UPDATE,
      timestamp: Date.now(),
      data: { inventory: session.inventory }
    });
  }

  const { started, castTime } = ctx.skillSys.beginCast(session, skillName, targetId);
  if (!started) return;

  const invIdx = session.statusEffects?.findIndex(e => e.type === StatusEffectType.INVISIBLE);
  if (invIdx !== undefined && invIdx !== -1) {
    if (skillDef && (skillDef.basePower || skillDef.damageType || skillDef.debuffEffectTable)) {
      session.statusEffects.splice(invIdx, 1);
      session.effectiveStats = null;
      ctx.sendToPlayer(characterId, {
        type: PacketType.STATUS_EFFECT_UPDATE,
        timestamp: Date.now(),
        data: { effects: session.statusEffects }
      });
      ctx.broadcastEntityEffects(session);
    }
  }

  if (castTime > 0) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.COOLDOWN_UPDATE,
      timestamp: Date.now(),
      data: { skillName, castTime, type: 'cast_start' }
    });
    return;
  }

  ctx.executeConeSkillInternal(session, skillName, targetId);
}
