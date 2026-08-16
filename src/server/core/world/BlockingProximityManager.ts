import { Packet, PacketType, PlayerSession, StatusEffectType, SpatialEntry } from '@dust-saga/shared';
import { PlayerSystem } from '../ecs/systems/PlayerSystem';

export interface BlockingProximityManagerDeps {
  getPlayers(): Map<string, PlayerSession>;
  getPlayerSys(): PlayerSystem;
  queryPlayersNear(x: number, z: number, radius: number, zoneId: string): SpatialEntry<PlayerSession>[];
  sendToPlayer(characterId: string, packet: Packet): void;
  broadcastEntityEffects(session: PlayerSession): void;
}

export class BlockingProximityManager {
  constructor(private deps: BlockingProximityManagerDeps) {}

  /** Remove all BUFF_BLOCKING_PROTECTED effects sourced from a blocker (on stance end / disconnect). */
  removeProtectedBuffs(blockerId: string): void {
    const blocker = this.deps.getPlayers().get(blockerId);
    const blockerZone = blocker?.zoneId;
    for (const [targetId, target] of this.deps.getPlayers()) {
      if (blockerZone && target.zoneId !== blockerZone) continue;
      const prot = target.statusEffects.find(
        e => e.type === StatusEffectType.BUFF_BLOCKING_PROTECTED && e.buffData?.blockingProtectedBy === blockerId
      );
      if (prot) {
        target.statusEffects = target.statusEffects.filter(e => e !== prot);
        this.deps.getPlayerSys().recalcStats(target);
        this.deps.sendToPlayer(targetId, {
          type: PacketType.STATUS_EFFECT_UPDATE,
          timestamp: Date.now(),
          data: { effects: target.statusEffects }
        });
        this.deps.broadcastEntityEffects(target);
      }
    }
  }

  /** Per-tick: grant/revoke BUFF_BLOCKING_PROTECTED to allies standing behind a blocker. */
  tick(now: number): void {
    for (const [blockerId, blocker] of this.deps.getPlayers()) {
      if (blocker.isDead) continue;
      const blockStance = blocker.statusEffects?.find(
        e => e.type === StatusEffectType.BUFF_BLOCKING_STANCE && e.buffData?.blockingStance
      );
      if (!blockStance || !blocker.position) continue;

      const blockRange = blockStance.buffData?.blockingRange || 6;
      const protRange = Math.max(2, blockRange * 0.4);

      let blockerFacing = 0;
      const rot = blocker.rotation as any;
      if (typeof rot === 'object' && rot.w !== undefined) {
        const sinY = 2 * (rot.w * rot.y - rot.z * rot.x);
        const cosY = 1 - 2 * (rot.y * rot.y + rot.z * rot.z);
        blockerFacing = Math.atan2(sinY, cosY);
      }

      const nearby = this.deps.queryPlayersNear(blocker.position.x, blocker.position.z, protRange, blocker.zoneId);
      const processedTargets = new Set<string>();

      for (const entry of nearby) {
        const targetId = entry.id;
        if (targetId === blockerId) continue;
        processedTargets.add(targetId);

        const dx = entry.x - blocker.position.x;
        const dz = entry.z - blocker.position.z;
        const dist = Math.sqrt(dx * dx + dz * dz);

        const existingProt = entry.data.statusEffects?.find(
          e => e.type === StatusEffectType.BUFF_BLOCKING_PROTECTED && e.buffData?.blockingProtectedBy === blockerId
        );

        let behindBlocker = false;
        if (dist <= protRange && dist > 0.01) {
          const angleToTarget = Math.atan2(dx, dz);
          let angleDiff = angleToTarget - blockerFacing;
          while (angleDiff > Math.PI) angleDiff -= 2 * Math.PI;
          while (angleDiff < -Math.PI) angleDiff += 2 * Math.PI;
          const behindAngle = Math.abs(angleDiff) - Math.PI;
          behindBlocker = Math.abs(behindAngle) < Math.PI / 4;
        }

        if (behindBlocker) {
          if (!existingProt) {
            entry.data.statusEffects.push({
              id: `block_prot_${blockerId}_${Date.now()}`,
              type: StatusEffectType.BUFF_BLOCKING_PROTECTED,
              sourceId: blockerId,
              targetId,
              potency: 0,
              appliedAt: now,
              duration: 999999999,
              tickInterval: 0,
              lastTickAt: now,
              stacks: 1,
              skillName: 'Blocking',
              buffData: { blockingProtectedBy: blockerId },
            });
            this.deps.getPlayerSys().recalcStats(entry.data);
            this.deps.sendToPlayer(targetId, {
              type: PacketType.STATUS_EFFECT_UPDATE,
              timestamp: Date.now(),
              data: { effects: entry.data.statusEffects }
            });
            this.deps.broadcastEntityEffects(entry.data);
          }
        } else {
          if (existingProt) {
            entry.data.statusEffects = entry.data.statusEffects.filter(e => e !== existingProt);
            this.deps.getPlayerSys().recalcStats(entry.data);
            this.deps.sendToPlayer(targetId, {
              type: PacketType.STATUS_EFFECT_UPDATE,
              timestamp: Date.now(),
              data: { effects: entry.data.statusEffects }
            });
            this.deps.broadcastEntityEffects(entry.data);
          }
        }
      }

      // Allies that moved out of range (no longer nearby): revoke their protection.
      for (const [targetId, target] of this.deps.getPlayers()) {
        if (targetId === blockerId) continue;
        if (target.isDead) continue;
        if (target.zoneId !== blocker.zoneId) continue;
        if (processedTargets.has(targetId)) continue;
        const existingProt = target.statusEffects.find(
          e => e.type === StatusEffectType.BUFF_BLOCKING_PROTECTED && e.buffData?.blockingProtectedBy === blockerId
        );
        if (existingProt) {
          target.statusEffects = target.statusEffects.filter(e => e !== existingProt);
          this.deps.getPlayerSys().recalcStats(target);
          this.deps.sendToPlayer(targetId, {
            type: PacketType.STATUS_EFFECT_UPDATE,
            timestamp: Date.now(),
            data: { effects: target.statusEffects }
          });
          this.deps.broadcastEntityEffects(target);
        }
      }
    }
  }
}
