import {
  Packet, PacketType, PlayerSession, StatusEffectType, StatusEffect,
  BuffData, SkillDefinition, resolveStatTieredValue, SpatialEntry,
} from '@dust-saga/shared';
import { SkillSystem } from '../ecs/systems/SkillSystem';
import { PlayerSystem } from '../ecs/systems/PlayerSystem';

export interface SongProximityManagerDeps {
  getPlayers(): Map<string, PlayerSession>;
  getSkillSystem(): SkillSystem;
  getPlayerSys(): PlayerSystem;
  isPartyMember(characterId: string, targetId: string): boolean;
  queryPlayersNear(x: number, z: number, radius: number, zoneId: string): SpatialEntry<PlayerSession>[];
  broadcastInZone(zoneId: string, packet: Packet): void;
  sendToPlayer(characterId: string, packet: Packet): void;
  broadcastEntityEffects(session: PlayerSession): void;
  onRedSongPulse(caster: PlayerSession, skill: SkillDefinition, songRadius: number): void;
}

const SONG_PULSE_INTERVAL = 4000;
const SONG_BUFF_DURATION = 5000;

const SONG_TYPES = [
  StatusEffectType.SONG_GREEN,
  StatusEffectType.SONG_BLUE,
  StatusEffectType.SONG_YELLOW,
  StatusEffectType.SONG_RED,
];

export class SongProximityManager {
  constructor(private deps: SongProximityManagerDeps) {}

  applySongPulseImmediate(caster: PlayerSession): void {
    const songEffect = caster.statusEffects?.find(e => SONG_TYPES.includes(e.type) && !e.songProximityBuff);
    if (!songEffect) return;

    const skill = this.deps.getSkillSystem().findSkillDefinition(songEffect.skillName || '');
    if (!skill) return;

    songEffect.lastPulseAt = Date.now();

    const songRadius = skill.aoeRadius || 3;

    if (songEffect.type === StatusEffectType.SONG_RED && skill.basePower) {
      this.deps.onRedSongPulse(caster, skill, songRadius);
      return;
    }

    if (!skill.buffEffectTable) return;
    const pulseTargets: PlayerSession[] = [caster];

    for (const [targetId, target] of this.deps.getPlayers()) {
      if (targetId === caster.characterId) continue;
      if (target.isDead) continue;
      if (target.zoneId !== caster.zoneId) continue;
      if (!target.position || !caster.position) continue;
      if (!this.deps.isPartyMember(caster.characterId, targetId)) continue;

      const dx = caster.position.x - target.position.x;
      const dz = caster.position.z - target.position.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      if (dist <= songRadius) {
        pulseTargets.push(target);
      }
    }

    const now = Date.now();
    for (const target of pulseTargets) {
      const isCaster = target.characterId === caster.characterId;
      this.applySongPulse(target, caster, skill, now, SONG_BUFF_DURATION, isCaster);
    }
  }

  removeSongProximityBuffs(caster: PlayerSession): void {
    for (const [targetId, target] of this.deps.getPlayers()) {
      if (target.zoneId !== caster.zoneId) continue;
      if (!target.statusEffects?.length) continue;

      const toRemove = target.statusEffects.filter(e =>
        e.songProximityBuff && e.sourceId === caster.characterId
      );
      if (toRemove.length === 0) continue;

      for (const e of toRemove) {
        e.lastInRangeAt = Date.now();
        e.appliedAt = Date.now();
        e.duration = SONG_BUFF_DURATION;
      }
      target.effectiveStats = null;

      if (targetId !== caster.characterId) {
        this.deps.sendToPlayer(targetId, {
          type: PacketType.STATUS_EFFECT_UPDATE,
          timestamp: Date.now(),
          data: { effects: target.statusEffects }
        });
        this.deps.sendToPlayer(targetId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: targetId, stats: target.stats, statBreakdown: target.statBreakdown, skillProficiencies: target.skillProficiencies, skillAdeptness: target.skillAdeptness }
        });
        this.deps.broadcastEntityEffects(target);
      }
    }
  }

  tick(now: number): void {
    for (const [charId, caster] of this.deps.getPlayers()) {
      if (caster.isDead) continue;
      if (!caster.statusEffects?.length) continue;

      const songEffect = caster.statusEffects.find(e => SONG_TYPES.includes(e.type) && !e.songProximityBuff);
      if (!songEffect) continue;

      const lastPulse = songEffect.lastPulseAt || songEffect.appliedAt || 0;
      if (now - lastPulse < SONG_PULSE_INTERVAL) continue;

      songEffect.lastPulseAt = now;

      const skill = this.deps.getSkillSystem().findSkillDefinition(songEffect.skillName || '');

      const mpDrain = Math.ceil((skill?.mpCost || 30) * 0.3);
      caster.stats.mana = Math.max(0, caster.stats.mana - mpDrain);
      if (caster.stats.mana <= 0) {
        caster.statusEffects = caster.statusEffects.filter(e => {
          if (SONG_TYPES.includes(e.type) && !e.songProximityBuff) return false;
          return true;
        });
        this.removeSongProximityBuffs(caster);
        this.deps.getPlayerSys().recalcStats(caster);
        this.deps.sendToPlayer(charId, {
          type: PacketType.STATUS_EFFECT_UPDATE,
          timestamp: Date.now(),
          data: { effects: caster.statusEffects }
        });
        this.deps.sendToPlayer(charId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: charId, stats: caster.stats, statBreakdown: caster.statBreakdown, skillProficiencies: caster.skillProficiencies, skillAdeptness: caster.skillAdeptness }
        });
        this.deps.sendToPlayer(charId, {
          type: PacketType.CHAT_MESSAGE,
          timestamp: Date.now(),
          data: { sender: 'System', message: 'Song ended - insufficient MP.', channel: 'system' }
        });
        this.deps.broadcastEntityEffects(caster);
        continue;
      }

      this.deps.sendToPlayer(charId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: charId, stats: caster.stats }
      });

      if (!skill) continue;

      if (!skill.buffEffectTable && songEffect.type !== StatusEffectType.SONG_RED) continue;
      const songRadius = skill.aoeRadius || 3;

      const pulseTargets: PlayerSession[] = [caster];

      if (caster.position) {
        const nearby = this.deps.queryPlayersNear(caster.position.x, caster.position.z, songRadius, caster.zoneId);
        for (const entry of nearby) {
          if (entry.id === charId) continue;
          if (!this.deps.isPartyMember(charId, entry.id)) continue;
          pulseTargets.push(entry.data);
        }
      }

      for (const target of pulseTargets) {
        const isCaster = target.characterId === charId;
        this.applySongPulse(target, caster, skill, now, SONG_BUFF_DURATION, isCaster);
      }

      if (songEffect.type === StatusEffectType.SONG_RED && skill.basePower) {
        this.deps.onRedSongPulse(caster, skill, songRadius);
      }
    }
  }

  private applySongPulse(
    target: PlayerSession,
    caster: PlayerSession,
    skill: SkillDefinition,
    now: number,
    buffDuration: number,
    isCaster: boolean
  ): void {
    const bt = skill.buffEffectTable;
    if (!bt) return;

    const sourceId = caster.characterId;
    const targetId = target.characterId;

    const existing = target.statusEffects.filter(e =>
      e.songProximityBuff && e.sourceId === sourceId && e.skillName === skill.name
    );
    if (existing.length > 0) {
      for (const e of existing) {
        e.appliedAt = now;
        e.duration = buffDuration;
        e.lastInRangeAt = now;
      }
      target.effectiveStats = null;
      this.deps.sendToPlayer(targetId, {
        type: PacketType.STATUS_EFFECT_UPDATE,
        timestamp: Date.now(),
        data: { effects: target.statusEffects }
      });
      return;
    }

    const effects: StatusEffect[] = [];
    const pushSongBuff = (type: StatusEffectType, potency: number, buffData?: BuffData) => {
      effects.push({
        id: `song_${now}_${Math.random().toString(36).slice(2, 6)}_${type}`,
        type,
        sourceId,
        targetId,
        potency,
        appliedAt: now,
        duration: buffDuration,
        tickInterval: 0,
        lastTickAt: now,
        stacks: 1,
        skillName: skill.name,
        songProximityBuff: true,
        lastInRangeAt: now,
        buffData,
      });
    };

    if (bt.songCooldownReduction) {
      pushSongBuff(StatusEffectType.BUFF_CAST_SPEED, bt.songCooldownReduction);
    }
    if (bt.magicalDamageBonus) {
      pushSongBuff(StatusEffectType.BUFF_GENERIC, 0, { magicalDamageBonusPercent: bt.magicalDamageBonus });
    }
    if (bt.auraDamageIncrease) {
      pushSongBuff(StatusEffectType.BUFF_GENERIC, 0, { auraDamageIncreasePercent: bt.auraDamageIncrease });
    }

    if (bt.statTieredValues) {
      const cfg = bt.statTieredValues;
      const statKey = cfg.stat as keyof typeof caster.baseStats;
      const totalStat = (caster.baseStats?.[statKey] || 0) + ((caster.statPoints as unknown as Record<string, number>)?.[statKey] || 0);
      const prof = cfg.proficiencyStat
        ? (caster.skillAdeptness?.[cfg.proficiencyStat] || 0)
        : 0;
      const skillName = skill.name.toLowerCase();
      if (skillName === 'green song' || skillName === 'speedy gale') {
        const dodgeResult = resolveStatTieredValue(cfg, totalStat, prof, 'dodgeChance');
        if (dodgeResult != null) {
          pushSongBuff(StatusEffectType.BUFF_DODGE, dodgeResult);
        }
        if (skillName === 'green song') {
          const accuracyResult = resolveStatTieredValue(cfg, totalStat, prof, 'accuracy');
          if (accuracyResult != null) {
            pushSongBuff(StatusEffectType.BUFF_ACCURACY, accuracyResult);
          }
        }
      }
    }

    if (bt.songDamageNegation) {
      const dn = bt.songDamageNegation;
      const totalSpi = (caster.baseStats?.SPI || 0) + (caster.statPoints?.SPI || 0);
      const hymnProf = caster.skillProficiencies?.['Hymn'] || 0;
      const profBonus = Math.min(hymnProf, dn.proficiencyCap);
      const threshold = Math.floor(dn.base + totalSpi * dn.spiScale + profBonus);
      pushSongBuff(StatusEffectType.BUFF_DAMAGE_NEGATION, 0, { damageNegationThreshold: threshold });
    }

    if (effects.length === 0) return;

    target.statusEffects.push(...effects);
    this.deps.getPlayerSys().recalcStats(target);
    this.deps.sendToPlayer(targetId, {
      type: PacketType.STATUS_EFFECT_UPDATE,
      timestamp: Date.now(),
      data: { effects: target.statusEffects }
    });
    this.deps.sendToPlayer(targetId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { characterId: targetId, stats: target.stats, statBreakdown: target.statBreakdown, skillProficiencies: target.skillProficiencies, skillAdeptness: target.skillAdeptness }
    });
    this.deps.broadcastEntityEffects(target);
    const songType = bt.songType;
    if (songType) {
      this.deps.broadcastInZone(target.zoneId, {
        type: PacketType.SONG_PULSE,
        timestamp: Date.now(),
        data: { entityId: targetId, songType }
      });
    }
  }
}
