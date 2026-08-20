import { Socket } from 'socket.io';
import {
  Packet, PacketType, PartyVisibility, LootRule,
} from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.PARTY_CREATE_REQUEST, handlePartyCreateRequest);
  registry.set(PacketType.PARTY_INVITE_REQUEST, handlePartyInviteRequest);
  registry.set(PacketType.PARTY_JOIN_REQUEST, handlePartyJoinRequest);
  registry.set(PacketType.PARTY_LEAVE, handlePartyLeave);
  registry.set(PacketType.PARTY_KICK, handlePartyKick);
  registry.set(PacketType.PARTY_PROMOTE, handlePartyPromote);
}

function handlePartyCreateRequest(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  const targetId = data.targetId;
  if (!targetId || targetId === characterId) return;

  const targetSession = ctx.state.players.get(targetId);
  if (!targetSession) return;

  if (ctx.partySys.getPartyForMember(characterId)) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: 'You are already in a party.', type: 'error' }
    });
    return;
  }

  if (ctx.partySys.getPartyForMember(targetId)) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: 'Target is already in a party.', type: 'error' }
    });
    return;
  }

  if (targetSession.currentNpcId) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: `${targetSession.characterName} is busy.`, type: 'error' }
    });
    return;
  }

  const visibility = data.visibility === 'open' ? PartyVisibility.OPEN : PartyVisibility.PRIVATE;
  const lootRule = data.lootRule === 'pool' ? LootRule.POOL : LootRule.RANDOM;

  const party = ctx.partySys.createParty(characterId, session, { visibility, lootRule });
  if (!party) return;

  ctx.sendToPlayer(characterId, {
    type: PacketType.PARTY_UPDATE,
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
    type: PacketType.PARTY_INVITE,
    timestamp: Date.now(),
    data: {
      partyId: party.partyId,
      leaderName: session.characterName,
      settings: party.settings,
      memberCount: party.members.length
    }
  });
}

function handlePartyInviteRequest(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  const targetId = data.targetId;
  if (!targetId || targetId === characterId) return;

  const targetSession = ctx.state.players.get(targetId);
  if (!targetSession) return;

  const party = ctx.partySys.getPartyForMember(characterId);
  if (!party || party.leaderId !== characterId) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: 'Only the party leader can invite members.', type: 'error' }
    });
    return;
  }

  if (ctx.partySys.getPartyForMemberOf(targetId)) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: 'Target is already in a party.', type: 'error' }
    });
    return;
  }

  if (party.members.length >= ctx.partySys.getMaxPartySize()) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: 'Party is full.', type: 'error' }
    });
    return;
  }

  if (targetSession.currentNpcId) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: `${targetSession.characterName} is busy.`, type: 'error' }
    });
    return;
  }

  ctx.sendToPlayer(targetId, {
    type: PacketType.PARTY_INVITE,
    timestamp: Date.now(),
    data: {
      partyId: party.partyId,
      leaderName: session.characterName,
      settings: party.settings,
      memberCount: party.members.length
    }
  });

  ctx.sendToPlayer(characterId, {
    type: PacketType.NOTIFICATION,
    timestamp: Date.now(),
    data: { message: `Invitation sent to ${targetSession.characterName}.`, type: 'success' }
  });
}

function handlePartyJoinRequest(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  if (!data.partyId) return;

  // Decline: tell the leader their invite was refused, confirm to the decliner.
  // If the party disbanded while the invite was pending, the notify is a no-op.
  if (data.accept === false) {
    const party = ctx.partySys.getPartyData(data.partyId);
    if (party) {
      ctx.sendToPlayer(party.leaderId, {
        type: PacketType.PARTY_JOIN_RESPONSE,
        timestamp: Date.now(),
        data: { partyId: party.partyId, accepted: false, characterId, name: session.characterName }
      });
      ctx.sendToPlayer(party.leaderId, {
        type: PacketType.NOTIFICATION,
        timestamp: Date.now(),
        data: { message: `${session.characterName} declined the party invitation.`, type: 'info' }
      });
    }
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: 'Invitation declined.', type: 'info' }
    });
    return;
  }

  const party = ctx.partySys.joinByInvite(data.partyId, characterId, session);
  if (!party) {
    const joinParty = ctx.partySys.joinParty(data.partyId, characterId, session);
    if (!joinParty) {
      ctx.sendToPlayer(characterId, {
        type: PacketType.NOTIFICATION,
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

function handlePartyLeave(ctx: NetworkContext, socket: Socket, _data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const result = ctx.partySys.leaveParty(characterId);
  if (!result) return;

  // Guardian requires a party link; break any Guardian link involving the
  // departing member (both protector and protected sides).
  ctx.breakGuardianLinksFor(characterId);

  if (result.party.members.length === 0) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.PARTY_DISBAND,
      timestamp: Date.now(),
      data: {}
    });
    return;
  }

  ctx.sendToPlayer(characterId, {
    type: PacketType.PARTY_DISBAND,
    timestamp: Date.now(),
    data: {}
  });

  ctx.sendPartyUpdate(result.party.partyId);

  for (const m of result.party.members) {
    ctx.sendToPlayer(m.characterId, {
      type: PacketType.CHAT_MESSAGE,
      timestamp: Date.now(),
      data: {
        sender: 'Party',
        message: `${ctx.state.players.get(characterId)?.characterName || 'Player'} has left the party.`,
        channel: 'party'
      }
    });
  }
}

function handlePartyKick(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const result = ctx.partySys.kickMember(characterId, data.targetId);
  if (!result) return;

  // Guardian requires a party link; break any Guardian link involving the
  // kicked member.
  ctx.breakGuardianLinksFor(data.targetId);

  ctx.sendToPlayer(data.targetId, {
    type: PacketType.PARTY_DISBAND,
    timestamp: Date.now(),
    data: {}
  });

  const targetName = ctx.state.players.get(data.targetId)?.characterName || 'Player';
  ctx.sendPartyUpdate(result.party.partyId);
  for (const m of result.party.members) {
    ctx.sendToPlayer(m.characterId, {
      type: PacketType.CHAT_MESSAGE,
      timestamp: Date.now(),
      data: {
        sender: 'Party',
        message: `${targetName} has been removed from the party.`,
        channel: 'party'
      }
    });
  }
}

function handlePartyPromote(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const party = ctx.partySys.promoteLeader(characterId, data.targetId);
  if (!party) return;

  ctx.sendPartyUpdate(party.partyId);
  for (const m of party.members) {
    ctx.sendToPlayer(m.characterId, {
      type: PacketType.CHAT_MESSAGE,
      timestamp: Date.now(),
      data: {
        sender: 'Party',
        message: `${ctx.state.players.get(data.targetId)?.characterName || 'Player'} is now the party leader.`,
        channel: 'party'
      }
    });
  }
}

function handlePartyLootRoll(_ctx: NetworkContext, _socket: Socket, _data: any): void {
  // Deprecated: loot rolls are now submitted via PARTY_LOOT_ROLL_SUBMIT and
  // resolved by LootSystem. PARTY_LOOT_ROLL is server→client only.
}
