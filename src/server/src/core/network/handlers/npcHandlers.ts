import { Socket } from 'socket.io';
import {
  Packet, PacketType, NPC_DATABASE, getNPCsInZone, NATION_ZONE_MAP, getZoneDefinition, JobId,
} from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.NPC_INTERACT, handleNPCInteract);
  registry.set(PacketType.NPC_SHOP_BUY, handleShopBuy);
  registry.set(PacketType.NPC_DIALOG_CLOSE, handleNpcDialogClose);
}

function handleNPCInteract(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  const npc = NPC_DATABASE[data.npcId];
  if (!npc) return;

  const dx = session.position.x - npc.position.x;
  const dz = session.position.z - npc.position.z;
  if (Math.sqrt(dx * dx + dz * dz) > 5) return;

  session.currentNpcId = data.npcId;

  // Cutscene trigger: client sends dialogId = "cutscene:<id>"
  if (typeof data.dialogId === 'string' && data.dialogId.startsWith('cutscene:')) {
    const cutsceneId = data.dialogId.slice('cutscene:'.length);
    ctx.startCutscene(session, cutsceneId);
    return;
  }

  // Class advancement dialog actions: "adv:<step>:<param>"
  if (typeof data.dialogId === 'string' && data.dialogId.startsWith('adv:')) {
    handleAdvancementAction(ctx, characterId, session, npc, data.dialogId);
    return;
  }

  const talkProgress = ctx.questSys.onTalk(session, data.npcId);
  if (talkProgress.progressed.length > 0) {
    const msgs = talkProgress.completed.map(qid => {
      const def = ctx.questSys.getQuestDefinition(qid);
      return `Quest "${def?.title || qid}" completed! Return to the NPC.`;
    });
    ctx.sendToPlayer(characterId, {
      type: PacketType.QUEST_PROGRESS,
      timestamp: Date.now(),
      data: { quests: session.quests, message: msgs.join('\n') }
    });
  }

  let dialog = npc.dialogs.find(d => d.id === (data.dialogId || 'greeting'));
  if (!dialog) dialog = npc.dialogs[0];

  const staticQuestIds = npc.quests || [];
  const availableQuests = ctx.questSys.getAvailableQuests(session)
    .filter(qid => {
      const def = ctx.questSys.getQuestDefinition(qid);
      return def?.npcId === data.npcId || staticQuestIds.includes(qid);
    })
    .map(qid => {
      const def = ctx.questSys.getQuestDefinition(qid)!;
      const existing = session.quests.find(sq => sq.questId === qid);
      const nextAvailableAt = existing ? ctx.questSys.repeatAvailableAt(def, existing) : null;
      return {
        id: qid,
        title: def.title,
        description: def.description || '',
        offerDialog: def.offerDialog,
        rewards: def.rewards,
        requiredLevel: def.requiredLevel,
        repeatable: def.repeatable,
        completionCount: existing?.completionCount || 0,
        nextAvailableAt,
      };
    });

  const activeQuests = session.quests
    .filter(sq => {
      if (sq.status === 'turned_in') return false;
      const def = ctx.questSys.getQuestDefinition(sq.questId);
      if (!def) return false;
      return def.npcId === data.npcId || staticQuestIds.includes(sq.questId);
    })
    .map(sq => {
      const def = ctx.questSys.getQuestDefinition(sq.questId)!;
      return {
        id: sq.questId,
        title: sq.title || def.title,
        description: sq.description || def.description,
        status: sq.status,
        objectives: sq.objectives.map(o => ({
          id: o.id,
          type: o.type,
          targetName: o.targetName,
          requiredCount: o.requiredCount,
          currentCount: o.currentCount,
          cell: o.cell,
          waypoint: o.waypoint,
        })),
        inProgressDialog: def.inProgressDialog,
        turnInDialog: def.turnInDialog,
        rewards: def.rewards,
        turnInReady: sq.status === 'completed',
      };
    });

  ctx.sendToPlayer(characterId, {
    type: PacketType.NPC_DIALOG,
    timestamp: Date.now(),
    data: {
      npcId: data.npcId,
      npcName: npc.name,
      dialog,
      shopItems: npc.type === 'merchant' || npc.type === 'blacksmith' ? (npc.shopItems || []).map(id => ctx.itemSys.getItemDefinition(id)).filter(Boolean) : undefined,
      availableQuests,
      activeQuests,
      craftProfession: npc.craftProfession,
    }
  });

  if (data.dialogId === 'join_nation') {
    const nationOption = dialog.options?.find(o => o.action === 'join_nation');
    if (nationOption?.actionData?.nation) {
      session.nation = nationOption.actionData.nation as 'varik' | 'pfelstein' | 'latugan';
      const nationInfo = NATION_ZONE_MAP[session.nation];
      if (nationInfo) {
        const nationZoneDef = getZoneDefinition(nationInfo.zoneId);
        session.lastSafeZoneId = nationInfo.zoneId;
        ctx.sendToPlayer(characterId, {
          type: PacketType.CHAT_MESSAGE,
          timestamp: Date.now(),
          data: { sender: 'System', message: `You have joined the ${nationZoneDef?.name || session.nation}! You will now respawn here when you die.`, channel: 'system' }
        });
      }
    }
  }
}

function handleNpcDialogClose(ctx: NetworkContext, socket: Socket, _data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  session.currentNpcId = null;
}

function handleShopBuy(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  if (ctx.tradeSys.isInTrade(characterId)) return;

  const itemDef = ctx.itemSys.getItemDefinition(data.itemId);
  if (!itemDef) return;

  const qty = data.quantity || 1;
  const cost = (itemDef.sellPrice || 0) * 2 * qty;
  if (cost > 0 && session.gold < cost) {
    ctx.sendToPlayer(characterId, { type: PacketType.NOTIFICATION, timestamp: Date.now(), data: { message: `Not enough gold. Need ${cost}g, have ${session.gold}g.`, type: 'error' } });
    return;
  }

  const added = ctx.playerSys.addItemToInventory(session, data.itemId, qty);
  if (added) {
    session.gold -= cost;
    ctx.sendToPlayer(characterId, {
      type: PacketType.INVENTORY_UPDATE,
      timestamp: Date.now(),
      data: { inventory: session.inventory, equipment: session.equipment, gold: session.gold }
    });
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: `Purchased ${itemDef.name}${qty > 1 ? ` x${qty}` : ''} for ${cost}g`, type: 'success' }
    });
    ctx.sendToPlayer(characterId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { characterId, stats: session.stats }
    });
  }
}

/**
 * Class advancement dialog actions. The client sends NPC_INTERACT with
 * dialogId = "adv:<step>:<param>" and the server executes the action,
 * then serves the next dialog page (or closes).
 *
 * Flow:
 *   adv:strip:<nextDialogId>   → unequip all gear to inventory
 *   adv:reset:<nextDialogId>   → refund stat + skill points
 *   adv:advance:<jobId>        → advance class + broadcast "Advanced!" effect
 */
function handleAdvancementAction(
  ctx: NetworkContext,
  characterId: string,
  session: any,
  npc: any,
  dialogId: string
): void {
  const parts = dialogId.split(':');
  const step = parts[1];
  const param = parts.slice(2).join(':');

  if (step === 'strip') {
    const result = ctx.playerSys.unequipAll(session);
    ctx.sendToPlayer(characterId, {
      type: PacketType.INVENTORY_UPDATE,
      timestamp: Date.now(),
      data: { inventory: session.inventory, equipment: session.equipment }
    });
    ctx.sendToPlayer(characterId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { characterId, stats: session.stats, statBreakdown: session.statBreakdown }
    });
    if (result.failed > 0) {
      ctx.sendToPlayer(characterId, {
        type: PacketType.NOTIFICATION,
        timestamp: Date.now(),
        data: { message: `${result.moved} items unequipped. ${result.failed} couldn't be moved — inventory full.`, type: 'info' }
      });
    }
    // Serve the next dialog page (respec question)
    if (param) serveDialog(ctx, characterId, npc, param);
    return;
  }

  if (step === 'reset') {
    ctx.playerSys.resetStatPoints(session);
    ctx.playerSys.resetSkillPoints(session);
    ctx.sendToPlayer(characterId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: {
        characterId, stats: session.stats, statPoints: session.statPoints,
        unspentStatPoints: session.unspentStatPoints, unspentSkillPoints: session.unspentSkillPoints,
        skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness,
        statBreakdown: session.statBreakdown
      }
    });
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: 'Stat and skill points reset. Reallocate them now.', type: 'info' }
    });
    if (param) serveDialog(ctx, characterId, npc, param);
    return;
  }

  if (step === 'advance') {
    const jobId = param as JobId;
    const advanced = ctx.playerSys.advanceJob(session, jobId);
    if (advanced) {
      ctx.sendToPlayer(characterId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: {
          characterId, stats: session.stats, statPoints: session.statPoints,
          jobId: session.jobId, baseClass: session.baseClass, statBreakdown: session.statBreakdown
        }
      });
      ctx.sendToPlayer(characterId, {
        type: PacketType.NOTIFICATION,
        timestamp: Date.now(),
        data: { message: `You are now a ${jobId}!`, type: 'success' }
      });
      // Broadcast "Advanced!" floating text to everyone in the zone
      ctx.broadcastInZone(session.zoneId, {
        type: PacketType.FLOATING_TEXT,
        timestamp: Date.now(),
        data: { entityId: session.characterId, text: 'Advanced!', color: '#ffd166' }
      });
    } else {
      ctx.sendToPlayer(characterId, {
        type: PacketType.NOTIFICATION,
        timestamp: Date.now(),
        data: { message: 'Advancement failed.', type: 'error' }
      });
    }
    // Close dialog after advancement
    ctx.sendToPlayer(characterId, {
      type: PacketType.NPC_DIALOG,
      timestamp: Date.now(),
      data: { npcId: npc.id, npcName: npc.name, dialog: undefined }
    });
    session.currentNpcId = null;
    return;
  }
}

/** Helper: look up a dialog page from the NPC and send it to the player. */
function serveDialog(ctx: NetworkContext, characterId: string, npc: any, dialogId: string): void {
  const dialog = npc.dialogs?.find((d: any) => d.id === dialogId) || npc.dialogs?.[0];
  ctx.sendToPlayer(characterId, {
    type: PacketType.NPC_DIALOG,
    timestamp: Date.now(),
    data: {
      npcId: npc.id,
      npcName: npc.name,
      dialog,
      shopItems: undefined,
      availableQuests: [],
      activeQuests: [],
    }
  });
}
