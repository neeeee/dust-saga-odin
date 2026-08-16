"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerHandlers = registerHandlers;
const shared_1 = require("@dust-saga/shared");
function registerHandlers(registry) {
    registry.set(shared_1.PacketType.PARTY_CREATE_REQUEST, handlePartyCreateRequest);
    registry.set(shared_1.PacketType.PARTY_INVITE_REQUEST, handlePartyInviteRequest);
    registry.set(shared_1.PacketType.PARTY_JOIN_REQUEST, handlePartyJoinRequest);
    registry.set(shared_1.PacketType.PARTY_LEAVE, handlePartyLeave);
    registry.set(shared_1.PacketType.PARTY_KICK, handlePartyKick);
    registry.set(shared_1.PacketType.PARTY_PROMOTE, handlePartyPromote);
}
function handlePartyCreateRequest(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    const targetId = data.targetId;
    if (!targetId || targetId === characterId)
        return;
    const targetSession = ctx.state.players.get(targetId);
    if (!targetSession)
        return;
    if (ctx.partySys.getPartyForMember(characterId)) {
        ctx.sendToPlayer(characterId, {
            type: shared_1.PacketType.NOTIFICATION,
            timestamp: Date.now(),
            data: { message: 'You are already in a party.', type: 'error' }
        });
        return;
    }
    if (ctx.partySys.getPartyForMember(targetId)) {
        ctx.sendToPlayer(characterId, {
            type: shared_1.PacketType.NOTIFICATION,
            timestamp: Date.now(),
            data: { message: 'Target is already in a party.', type: 'error' }
        });
        return;
    }
    if (targetSession.currentNpcId) {
        ctx.sendToPlayer(characterId, {
            type: shared_1.PacketType.NOTIFICATION,
            timestamp: Date.now(),
            data: { message: `${targetSession.characterName} is busy.`, type: 'error' }
        });
        return;
    }
    const visibility = data.visibility === 'open' ? shared_1.PartyVisibility.OPEN : shared_1.PartyVisibility.PRIVATE;
    const lootRule = data.lootRule === 'pool' ? shared_1.LootRule.POOL : shared_1.LootRule.RANDOM;
    const party = ctx.partySys.createParty(characterId, session, { visibility, lootRule });
    if (!party)
        return;
    ctx.sendToPlayer(characterId, {
        type: shared_1.PacketType.PARTY_UPDATE,
        timestamp: Date.now(),
        data: {
            partyId: party.partyId,
            leaderId: party.leaderId,
            members: party.members,
            settings: party.settings,
            lootPool: []
        }
    });
    ctx.sendToPlayer(targetId, {
        type: shared_1.PacketType.PARTY_INVITE,
        timestamp: Date.now(),
        data: {
            partyId: party.partyId,
            leaderName: session.characterName,
            settings: party.settings,
            memberCount: party.members.length
        }
    });
}
function handlePartyInviteRequest(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    const targetId = data.targetId;
    if (!targetId || targetId === characterId)
        return;
    const targetSession = ctx.state.players.get(targetId);
    if (!targetSession)
        return;
    const party = ctx.partySys.getPartyForMember(characterId);
    if (!party || party.leaderId !== characterId) {
        ctx.sendToPlayer(characterId, {
            type: shared_1.PacketType.NOTIFICATION,
            timestamp: Date.now(),
            data: { message: 'Only the party leader can invite members.', type: 'error' }
        });
        return;
    }
    if (ctx.partySys.getPartyForMemberOf(targetId)) {
        ctx.sendToPlayer(characterId, {
            type: shared_1.PacketType.NOTIFICATION,
            timestamp: Date.now(),
            data: { message: 'Target is already in a party.', type: 'error' }
        });
        return;
    }
    if (party.members.length >= ctx.partySys.getMaxPartySize()) {
        ctx.sendToPlayer(characterId, {
            type: shared_1.PacketType.NOTIFICATION,
            timestamp: Date.now(),
            data: { message: 'Party is full.', type: 'error' }
        });
        return;
    }
    if (targetSession.currentNpcId) {
        ctx.sendToPlayer(characterId, {
            type: shared_1.PacketType.NOTIFICATION,
            timestamp: Date.now(),
            data: { message: `${targetSession.characterName} is busy.`, type: 'error' }
        });
        return;
    }
    ctx.sendToPlayer(targetId, {
        type: shared_1.PacketType.PARTY_INVITE,
        timestamp: Date.now(),
        data: {
            partyId: party.partyId,
            leaderName: session.characterName,
            settings: party.settings,
            memberCount: party.members.length
        }
    });
    ctx.sendToPlayer(characterId, {
        type: shared_1.PacketType.NOTIFICATION,
        timestamp: Date.now(),
        data: { message: `Invitation sent to ${targetSession.characterName}.`, type: 'success' }
    });
}
function handlePartyJoinRequest(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    if (!data.partyId)
        return;
    if (data.accept === false)
        return;
    const party = ctx.partySys.joinByInvite(data.partyId, characterId, session);
    if (!party) {
        const joinParty = ctx.partySys.joinParty(data.partyId, characterId, session);
        if (!joinParty) {
            ctx.sendToPlayer(characterId, {
                type: shared_1.PacketType.NOTIFICATION,
                timestamp: Date.now(),
                data: { message: 'Could not join party.', type: 'error' }
            });
            return;
        }
        ctx.sendPartyUpdate(data.partyId);
        return;
    }
    ctx.sendPartyUpdate(data.partyId);
}
function handlePartyLeave(ctx, socket, _data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const result = ctx.partySys.leaveParty(characterId);
    if (!result)
        return;
    // Guardian requires a party link; break any Guardian link involving the
    // departing member (both protector and protected sides).
    ctx.breakGuardianLinksFor(characterId);
    if (result.party.members.length === 0) {
        ctx.sendToPlayer(characterId, {
            type: shared_1.PacketType.PARTY_DISBAND,
            timestamp: Date.now(),
            data: {}
        });
        return;
    }
    ctx.sendToPlayer(characterId, {
        type: shared_1.PacketType.PARTY_DISBAND,
        timestamp: Date.now(),
        data: {}
    });
    ctx.sendPartyUpdate(result.party.partyId);
    for (const m of result.party.members) {
        ctx.sendToPlayer(m.characterId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: {
                sender: 'Party',
                message: `${ctx.state.players.get(characterId)?.characterName || 'Player'} has left the party.`,
                channel: 'party'
            }
        });
    }
}
function handlePartyKick(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const result = ctx.partySys.kickMember(characterId, data.targetId);
    if (!result)
        return;
    // Guardian requires a party link; break any Guardian link involving the
    // kicked member.
    ctx.breakGuardianLinksFor(data.targetId);
    ctx.sendToPlayer(data.targetId, {
        type: shared_1.PacketType.PARTY_DISBAND,
        timestamp: Date.now(),
        data: {}
    });
    const targetName = ctx.state.players.get(data.targetId)?.characterName || 'Player';
    ctx.sendPartyUpdate(result.party.partyId);
    for (const m of result.party.members) {
        ctx.sendToPlayer(m.characterId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: {
                sender: 'Party',
                message: `${targetName} has been removed from the party.`,
                channel: 'party'
            }
        });
    }
}
function handlePartyPromote(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const party = ctx.partySys.promoteLeader(characterId, data.targetId);
    if (!party)
        return;
    ctx.sendPartyUpdate(party.partyId);
    for (const m of party.members) {
        ctx.sendToPlayer(m.characterId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: {
                sender: 'Party',
                message: `${ctx.state.players.get(data.targetId)?.characterName || 'Player'} is now the party leader.`,
                channel: 'party'
            }
        });
    }
}
function handlePartyLootRoll(_ctx, _socket, _data) {
    // Deprecated: loot rolls are now submitted via PARTY_LOOT_ROLL_SUBMIT and
    // resolved by LootSystem. PARTY_LOOT_ROLL is server→client only.
}
