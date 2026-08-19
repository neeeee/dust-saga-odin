"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerHandlers = registerHandlers;
const shared_1 = require("@dust-saga/shared");
function registerHandlers(registry) {
    registry.set(shared_1.PacketType.QUEST_ACCEPT, handleQuestAccept);
    registry.set(shared_1.PacketType.QUEST_COMPLETE, handleQuestComplete);
    registry.set(shared_1.PacketType.QUEST_ABANDON, handleQuestAbandon);
}
function resolveQuestId(data) {
    if (!data || typeof data.questId !== 'string' || !data.questId.trim())
        return null;
    return data.questId;
}
function handleQuestAccept(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    const questId = resolveQuestId(data);
    if (!questId) {
        ctx.sendToPlayer(characterId, { type: shared_1.PacketType.ERROR, timestamp: Date.now(), data: { message: 'Invalid quest id.' } });
        return;
    }
    if (ctx.questSys.acceptQuest(session, questId)) {
        // Accepting ends the conversation — clear the busy flag so combat resumes
        // even if the client's NPC_DIALOG_CLOSE packet is lost.
        session.currentNpcId = null;
        session.lastQuestCell = null;
        ctx.checkQuestCellEntry(session);
        ctx.sendToPlayer(characterId, {
            type: shared_1.PacketType.QUEST_ACCEPT,
            timestamp: Date.now(),
            data: { questId, quest: session.quests.find(q => q.questId === questId), quests: session.quests }
        });
        // Accept cutscene
        const def = ctx.questSys.getQuestDefinition(questId);
        if (def?.acceptCutsceneId) {
            ctx.startCutscene(session, def.acceptCutsceneId);
        }
    }
    else {
        ctx.sendToPlayer(characterId, { type: shared_1.PacketType.ERROR, timestamp: Date.now(), data: { message: 'Cannot accept that quest.' } });
    }
}
function handleQuestComplete(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    const questId = resolveQuestId(data);
    if (!questId) {
        ctx.sendToPlayer(characterId, { type: shared_1.PacketType.ERROR, timestamp: Date.now(), data: { message: 'Invalid quest id.' } });
        return;
    }
    const result = ctx.questSys.completeQuest(session, questId);
    if (!result) {
        ctx.sendToPlayer(characterId, { type: shared_1.PacketType.ERROR, timestamp: Date.now(), data: { message: 'Cannot turn in that quest (not ready or missing required items).' } });
        return;
    }
    // Turning in ends the conversation — clear the busy flag.
    session.currentNpcId = null;
    for (const item of result.consumeItems) {
        ctx.playerSys.removeItemFromInventory(session, item.itemId, item.quantity);
    }
    ctx.playerSys.grantExperience(session, result.experience);
    if (result.gold) {
        session.gold += result.gold;
    }
    result.items.forEach(item => {
        ctx.playerSys.addItemToInventory(session, item.itemId, item.quantity);
    });
    ctx.sendToPlayer(characterId, {
        type: shared_1.PacketType.QUEST_COMPLETE,
        timestamp: Date.now(),
        data: { questId, rewards: { experience: result.experience, gold: result.gold, items: result.items } }
    });
    ctx.sendToPlayer(characterId, {
        type: shared_1.PacketType.INVENTORY_UPDATE,
        timestamp: Date.now(),
        data: { inventory: session.inventory, equipment: session.equipment, gold: session.gold }
    });
    ctx.sendToPlayer(characterId, {
        type: shared_1.PacketType.QUEST_PROGRESS,
        timestamp: Date.now(),
        data: { questId, status: 'turned_in', quests: session.quests }
    });
    ctx.sendToPlayer(characterId, {
        type: shared_1.PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId, stats: session.stats }
    });
    // Zone unlocks from the quest definition
    const questDef = ctx.questSys.getQuestDefinition(questId);
    if (questDef?.unlocksZones) {
        if (!session.unlockedZones)
            session.unlockedZones = [];
        for (const z of questDef.unlocksZones) {
            if (!session.unlockedZones.includes(z)) {
                session.unlockedZones.push(z);
                ctx.sendToPlayer(characterId, {
                    type: shared_1.PacketType.NOTIFICATION,
                    timestamp: Date.now(),
                    data: { message: `New area unlocked: ${(0, shared_1.getZoneDefinition)(z)?.name || z}!`, type: 'success' }
                });
            }
        }
    }
    // Turn-in cutscene
    if (questDef?.turnInCutsceneId) {
        ctx.startCutscene(session, questDef.turnInCutsceneId);
    }
}
function handleQuestAbandon(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    const questId = resolveQuestId(data);
    if (!questId) {
        ctx.sendToPlayer(characterId, { type: shared_1.PacketType.ERROR, timestamp: Date.now(), data: { message: 'Invalid quest id.' } });
        return;
    }
    if (ctx.questSys.abandonQuest(session, questId)) {
        // Abandoning ends the conversation — clear the busy flag.
        session.currentNpcId = null;
        ctx.sendToPlayer(characterId, {
            type: shared_1.PacketType.QUEST_ABANDON,
            timestamp: Date.now(),
            data: { questId, quests: session.quests }
        });
    }
}
