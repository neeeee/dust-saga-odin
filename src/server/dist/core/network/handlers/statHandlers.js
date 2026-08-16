"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerHandlers = registerHandlers;
const shared_1 = require("@dust-saga/shared");
function registerHandlers(registry) {
    registry.set(shared_1.PacketType.STAT_ALLOCATE, handleStatAllocate);
    registry.set(shared_1.PacketType.SKILL_ALLOCATE, handleSkillAllocate);
    registry.set(shared_1.PacketType.JOB_ADVANCE, handleJobAdvance);
}
function handleStatAllocate(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    if (data.allocations && typeof data.allocations === 'object') {
        const alloc = data.allocations;
        for (const [stat, count] of Object.entries(alloc)) {
            const st = stat;
            const n = Math.floor(count);
            for (let i = 0; i < n; i++) {
                ctx.playerSys.allocateStatPoint(session, st);
            }
        }
    }
    else {
        const stat = data.stat;
        if (!stat)
            return;
        ctx.playerSys.allocateStatPoint(session, stat);
    }
    ctx.sendToPlayer(characterId, {
        type: shared_1.PacketType.STATS_UPDATE,
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
function handleSkillAllocate(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    let anySuccess = false;
    if (data.allocations && typeof data.allocations === 'object') {
        const alloc = data.allocations;
        for (const [subCat, count] of Object.entries(alloc)) {
            const n = Math.floor(count);
            if (ctx.playerSys.allocateSkillPoint(session, subCat, n)) {
                anySuccess = true;
            }
        }
    }
    else {
        const subCategoryName = data.subCategoryName;
        const count = typeof data.count === 'number' ? Math.floor(data.count) : 1;
        if (subCategoryName) {
            anySuccess = ctx.playerSys.allocateSkillPoint(session, subCategoryName, count);
        }
    }
    if (anySuccess) {
        ctx.sendToPlayer(characterId, {
            type: shared_1.PacketType.STATS_UPDATE,
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
function handleJobAdvance(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    if (ctx.playerSys.advanceJob(session, data.jobId)) {
        ctx.sendToPlayer(characterId, {
            type: shared_1.PacketType.STATS_UPDATE,
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
