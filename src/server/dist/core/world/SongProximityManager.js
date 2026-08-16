"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SongProximityManager = void 0;
const shared_1 = require("@dust-saga/shared");
const SONG_PULSE_INTERVAL = 4000;
const SONG_BUFF_DURATION = 5000;
const SONG_TYPES = [
    shared_1.StatusEffectType.SONG_GREEN,
    shared_1.StatusEffectType.SONG_BLUE,
    shared_1.StatusEffectType.SONG_YELLOW,
    shared_1.StatusEffectType.SONG_RED,
];
class SongProximityManager {
    constructor(deps) {
        this.deps = deps;
    }
    applySongPulseImmediate(caster) {
        const songEffect = caster.statusEffects?.find(e => SONG_TYPES.includes(e.type) && !e.songProximityBuff);
        if (!songEffect)
            return;
        const skill = this.deps.getSkillSystem().findSkillDefinition(songEffect.skillName || '');
        if (!skill)
            return;
        songEffect.lastPulseAt = Date.now();
        const songRadius = skill.aoeRadius || 3;
        if (songEffect.type === shared_1.StatusEffectType.SONG_RED && skill.basePower) {
            this.deps.onRedSongPulse(caster, skill, songRadius);
            return;
        }
        if (!skill.buffEffectTable)
            return;
        const pulseTargets = [caster];
        for (const [targetId, target] of this.deps.getPlayers()) {
            if (targetId === caster.characterId)
                continue;
            if (target.isDead)
                continue;
            if (target.zoneId !== caster.zoneId)
                continue;
            if (!target.position || !caster.position)
                continue;
            if (!this.deps.isPartyMember(caster.characterId, targetId))
                continue;
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
    removeSongProximityBuffs(caster) {
        for (const [targetId, target] of this.deps.getPlayers()) {
            if (target.zoneId !== caster.zoneId)
                continue;
            if (!target.statusEffects?.length)
                continue;
            const toRemove = target.statusEffects.filter(e => e.songProximityBuff && e.sourceId === caster.characterId);
            if (toRemove.length === 0)
                continue;
            for (const e of toRemove) {
                e.lastInRangeAt = Date.now();
                e.appliedAt = Date.now();
                e.duration = SONG_BUFF_DURATION;
            }
            target.effectiveStats = null;
            if (targetId !== caster.characterId) {
                this.deps.sendToPlayer(targetId, {
                    type: shared_1.PacketType.STATUS_EFFECT_UPDATE,
                    timestamp: Date.now(),
                    data: { effects: target.statusEffects }
                });
                this.deps.sendToPlayer(targetId, {
                    type: shared_1.PacketType.STATS_UPDATE,
                    timestamp: Date.now(),
                    data: { characterId: targetId, stats: target.stats, statBreakdown: target.statBreakdown, skillProficiencies: target.skillProficiencies, skillAdeptness: target.skillAdeptness }
                });
                this.deps.broadcastEntityEffects(target);
            }
        }
    }
    tick(now) {
        for (const [charId, caster] of this.deps.getPlayers()) {
            if (caster.isDead)
                continue;
            if (!caster.statusEffects?.length)
                continue;
            const songEffect = caster.statusEffects.find(e => SONG_TYPES.includes(e.type) && !e.songProximityBuff);
            if (!songEffect)
                continue;
            const lastPulse = songEffect.lastPulseAt || songEffect.appliedAt || 0;
            if (now - lastPulse < SONG_PULSE_INTERVAL)
                continue;
            songEffect.lastPulseAt = now;
            const skill = this.deps.getSkillSystem().findSkillDefinition(songEffect.skillName || '');
            const mpDrain = Math.ceil((skill?.mpCost || 30) * 0.3);
            caster.stats.mana = Math.max(0, caster.stats.mana - mpDrain);
            if (caster.stats.mana <= 0) {
                caster.statusEffects = caster.statusEffects.filter(e => {
                    if (SONG_TYPES.includes(e.type) && !e.songProximityBuff)
                        return false;
                    return true;
                });
                this.removeSongProximityBuffs(caster);
                this.deps.getPlayerSys().recalcStats(caster);
                this.deps.sendToPlayer(charId, {
                    type: shared_1.PacketType.STATUS_EFFECT_UPDATE,
                    timestamp: Date.now(),
                    data: { effects: caster.statusEffects }
                });
                this.deps.sendToPlayer(charId, {
                    type: shared_1.PacketType.STATS_UPDATE,
                    timestamp: Date.now(),
                    data: { characterId: charId, stats: caster.stats, statBreakdown: caster.statBreakdown, skillProficiencies: caster.skillProficiencies, skillAdeptness: caster.skillAdeptness }
                });
                this.deps.sendToPlayer(charId, {
                    type: shared_1.PacketType.CHAT_MESSAGE,
                    timestamp: Date.now(),
                    data: { sender: 'System', message: 'Song ended - insufficient MP.', channel: 'system' }
                });
                this.deps.broadcastEntityEffects(caster);
                continue;
            }
            this.deps.sendToPlayer(charId, {
                type: shared_1.PacketType.STATS_UPDATE,
                timestamp: Date.now(),
                data: { characterId: charId, stats: caster.stats }
            });
            if (!skill)
                continue;
            if (!skill.buffEffectTable && songEffect.type !== shared_1.StatusEffectType.SONG_RED)
                continue;
            const songRadius = skill.aoeRadius || 3;
            const pulseTargets = [caster];
            if (caster.position) {
                const nearby = this.deps.queryPlayersNear(caster.position.x, caster.position.z, songRadius, caster.zoneId);
                for (const entry of nearby) {
                    if (entry.id === charId)
                        continue;
                    if (!this.deps.isPartyMember(charId, entry.id))
                        continue;
                    pulseTargets.push(entry.data);
                }
            }
            for (const target of pulseTargets) {
                const isCaster = target.characterId === charId;
                this.applySongPulse(target, caster, skill, now, SONG_BUFF_DURATION, isCaster);
            }
            if (songEffect.type === shared_1.StatusEffectType.SONG_RED && skill.basePower) {
                this.deps.onRedSongPulse(caster, skill, songRadius);
            }
        }
    }
    applySongPulse(target, caster, skill, now, buffDuration, isCaster) {
        const bt = skill.buffEffectTable;
        if (!bt)
            return;
        const sourceId = caster.characterId;
        const targetId = target.characterId;
        const existing = target.statusEffects.filter(e => e.songProximityBuff && e.sourceId === sourceId && e.skillName === skill.name);
        if (existing.length > 0) {
            for (const e of existing) {
                e.appliedAt = now;
                e.duration = buffDuration;
                e.lastInRangeAt = now;
            }
            target.effectiveStats = null;
            this.deps.sendToPlayer(targetId, {
                type: shared_1.PacketType.STATUS_EFFECT_UPDATE,
                timestamp: Date.now(),
                data: { effects: target.statusEffects }
            });
            return;
        }
        const effects = [];
        const pushSongBuff = (type, potency, buffData) => {
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
            pushSongBuff(shared_1.StatusEffectType.BUFF_CAST_SPEED, bt.songCooldownReduction);
        }
        if (bt.magicalDamageBonus) {
            pushSongBuff(shared_1.StatusEffectType.BUFF_GENERIC, 0, { magicalDamageBonusPercent: bt.magicalDamageBonus });
        }
        if (bt.auraDamageIncrease) {
            pushSongBuff(shared_1.StatusEffectType.BUFF_GENERIC, 0, { auraDamageIncreasePercent: bt.auraDamageIncrease });
        }
        if (bt.statTieredValues) {
            const cfg = bt.statTieredValues;
            const statKey = cfg.stat;
            const totalStat = (caster.baseStats?.[statKey] || 0) + (caster.statPoints?.[statKey] || 0);
            const prof = cfg.proficiencyStat
                ? (caster.skillAdeptness?.[cfg.proficiencyStat] || 0)
                : 0;
            const skillName = skill.name.toLowerCase();
            if (skillName === 'green song' || skillName === 'speedy gale') {
                const dodgeResult = (0, shared_1.resolveStatTieredValue)(cfg, totalStat, prof, 'dodgeChance');
                if (dodgeResult != null) {
                    pushSongBuff(shared_1.StatusEffectType.BUFF_DODGE, dodgeResult);
                }
                if (skillName === 'green song') {
                    const accuracyResult = (0, shared_1.resolveStatTieredValue)(cfg, totalStat, prof, 'accuracy');
                    if (accuracyResult != null) {
                        pushSongBuff(shared_1.StatusEffectType.BUFF_ACCURACY, accuracyResult);
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
            pushSongBuff(shared_1.StatusEffectType.BUFF_DAMAGE_NEGATION, 0, { damageNegationThreshold: threshold });
        }
        if (effects.length === 0)
            return;
        target.statusEffects.push(...effects);
        this.deps.getPlayerSys().recalcStats(target);
        this.deps.sendToPlayer(targetId, {
            type: shared_1.PacketType.STATUS_EFFECT_UPDATE,
            timestamp: Date.now(),
            data: { effects: target.statusEffects }
        });
        this.deps.sendToPlayer(targetId, {
            type: shared_1.PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: targetId, stats: target.stats, statBreakdown: target.statBreakdown, skillProficiencies: target.skillProficiencies, skillAdeptness: target.skillAdeptness }
        });
        this.deps.broadcastEntityEffects(target);
        const songType = bt.songType;
        if (songType) {
            this.deps.broadcastInZone(target.zoneId, {
                type: shared_1.PacketType.SONG_PULSE,
                timestamp: Date.now(),
                data: { entityId: targetId, songType }
            });
        }
    }
}
exports.SongProximityManager = SongProximityManager;
