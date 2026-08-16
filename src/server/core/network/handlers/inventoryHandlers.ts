import { Socket } from 'socket.io';
import {
  Packet, PacketType,
  applyRacialPotionHealing,
  LootRule, normalizeLootRule, LootRollKind, getRecipe,
} from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.ITEM_USE, handleItemUse);
  registry.set(PacketType.EQUIP_ITEM, handleEquipItem);
  registry.set(PacketType.UNEQUIP_ITEM, handleUnequipItem);
  registry.set(PacketType.LOOT_PICKUP, handleLootPickup);
  registry.set(PacketType.LOOT_TAKE, handleLootTake);
  registry.set(PacketType.PARTY_LOOT_RULE_CHANGE, handleLootRuleChange);
  registry.set(PacketType.PARTY_LOOT_ROLL_SUBMIT, handleLootRollSubmit);
  registry.set(PacketType.ITEM_DROP, handleItemDrop);
}

function handleItemUse(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  if (ctx.tradeSys.isInTrade(characterId)) return;

  const itemDef = ctx.itemSys.getItemDefinition(data.itemId);
  if (!itemDef) return;

  const invSlot = session.inventory.find(s => s.itemId === data.itemId);
  if (!invSlot) return;

  if (itemDef.type === 'consumable') {
    if (itemDef.stats.health && itemDef.type === 'consumable') {
      session.stats.health = Math.min(session.stats.maxHealth, session.stats.health + applyRacialPotionHealing(session.racialPassive, itemDef.stats.health || 0));
    }
    if (itemDef.stats.mana && itemDef.type === 'consumable') {
      session.stats.mana = Math.min(session.stats.maxMana, session.stats.mana + applyRacialPotionHealing(session.racialPassive, itemDef.stats.mana || 0));
    }

    ctx.playerSys.removeItemFromInventory(session, data.itemId, 1);
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
    return;
  }

  // RECIPE items teach a recipe on use (consumed in the process).
  if (itemDef.type === 'recipe' && itemDef.teachesRecipe) {
    const recipe = getRecipe(itemDef.teachesRecipe);
    if (!recipe) {
      ctx.sendToPlayer(characterId, {
        type: PacketType.NOTIFICATION,
        timestamp: Date.now(),
        data: { message: 'This recipe is unknown to the server.', type: 'error' }
      });
      return;
    }
    if (!session.learnedRecipes) session.learnedRecipes = [];
    if (session.learnedRecipes.includes(recipe.id)) {
      ctx.sendToPlayer(characterId, {
        type: PacketType.NOTIFICATION,
        timestamp: Date.now(),
        data: { message: `You already know "${recipe.name || recipe.id}".`, type: 'info' }
      });
      return;
    }
    session.learnedRecipes.push(recipe.id);
    ctx.playerSys.removeItemFromInventory(session, data.itemId, 1);
    ctx.sendToPlayer(characterId, {
      type: PacketType.RECIPE_LEARN,
      timestamp: Date.now(),
      data: { recipeId: recipe.id, learnedRecipes: session.learnedRecipes }
    });
    ctx.sendToPlayer(characterId, {
      type: PacketType.INVENTORY_UPDATE,
      timestamp: Date.now(),
      data: { inventory: session.inventory, equipment: session.equipment }
    });
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: `Learned recipe: ${recipe.name || recipe.id}`, type: 'success' }
    });
  }
}

function handleEquipItem(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  if (ctx.tradeSys.isInTrade(characterId)) return;

  if (ctx.playerSys.equipItem(session, data.itemId)) {
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
    // Sync status effects so an equipped/unequipped Obelisk weapon's buff
    // appears/disappears immediately.
    ctx.sendToPlayer(characterId, {
      type: PacketType.STATUS_EFFECT_UPDATE,
      timestamp: Date.now(),
      data: { effects: session.statusEffects }
    });
  }
}

function handleUnequipItem(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  if (ctx.tradeSys.isInTrade(characterId)) return;

  if (ctx.playerSys.unequipItem(session, data.slot)) {
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
    ctx.sendToPlayer(characterId, {
      type: PacketType.STATUS_EFFECT_UPDATE,
      timestamp: Date.now(),
      data: { effects: session.statusEffects }
    });
  }
}

/**
 * Loot pickup — multi-item bag model. The client requests either a specific
 * item from the bag (data.itemId) or everything (no itemId). The server
 * validates range + assignment, mutates inventory, and broadcasts a
 * LOOT_PICKUP ack to the whole zone so other clients can update.
 *
 * Inventory-full no longer silently deletes loot: addItemToInventory is
 * checked before pickupItem/pickupAll commits the removal.
 */
function handleLootPickup(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;
  const session = ctx.state.players.get(characterId);
  if (!session) return;
  if (ctx.tradeSys.isInTrade(characterId)) return;

  const lootId = data?.lootId;
  const takeAll = data?.takeAll === true || data?.itemId === undefined;
  const requestedItemId = data?.itemId;

  const check = ctx.loot.canPickup(lootId, characterId);
  if (!check.ok || !check.bag) {
    if (check.reason === 'assigned') {
      ctx.sendToPlayer(characterId, {
        type: PacketType.NOTIFICATION,
        timestamp: Date.now(),
        data: { message: 'Assigned to another party member.', type: 'info' }
      });
    }
    return;
  }
  const bag = check.bag;

  const dx = session.position.x - bag.position.x;
  const dz = session.position.z - bag.position.z;
  if (Math.sqrt(dx * dx + dz * dz) > 5) return;

  if (takeAll) {
    const items = ctx.loot.pickupAll(lootId);
    if (!items || items.length === 0) return;
    const rejected: Array<{ itemId: string; quantity: number }> = [];
    for (const it of items) {
      const ok = ctx.playerSys.addItemToInventory(session, it.itemId, it.quantity);
      if (ok) {
        ctx.questSys.onItemCollect(session, it.itemId);
      } else {
        rejected.push(it);
      }
    }
    finalizeLootPickup(ctx, session, bag, items, rejected);
    return;
  }

  // Single-item pickup
  const entry = ctx.loot.pickupItem(lootId, requestedItemId);
  if (!entry) return;
  const added = ctx.playerSys.addItemToInventory(session, entry.itemId, entry.quantity);
  if (added) {
    ctx.questSys.onItemCollect(session, entry.itemId);
    finalizeLootPickup(ctx, session, bag, [entry], []);
  } else {
    // inventory full — re-insert into the bag so someone else (or the same
    // player after dropping something) can grab it.
    const stillHasBag = ctx.loot.getBag(lootId) !== null;
    if (stillHasBag) {
      ctx.loot.addItemToBag(lootId, entry.itemId, entry.quantity);
    } else {
      ctx.loot.spawnFFA([{ itemId: entry.itemId, quantity: entry.quantity }], bag.position, bag.zoneId, bag.sourceName);
    }
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: 'Inventory full.', type: 'error' }
    });
  }
}

function finalizeLootPickup(
  ctx: NetworkContext,
  session: PlayerSessionLike,
  bag: { id: string; zoneId: string },
  taken: Array<{ itemId: string; quantity: number }>,
  rejected: Array<{ itemId: string; quantity: number }>
): void {
  ctx.sendToPlayer(session.characterId, {
    type: PacketType.LOOT_PICKUP,
    timestamp: Date.now(),
    data: { lootId: bag.id, taken, rejected }
  });
  ctx.broadcastInZone(bag.zoneId, {
    type: PacketType.LOOT_PICKUP,
    timestamp: Date.now(),
    data: { lootId: bag.id, by: session.characterId, taken }
  }, session.characterId);
  ctx.sendToPlayer(session.characterId, {
    type: PacketType.INVENTORY_UPDATE,
    timestamp: Date.now(),
    data: { inventory: session.inventory, equipment: session.equipment }
  });
}

type PlayerSessionLike = {
  characterId: string;
  inventory: any[];
  equipment: any;
};

/** Take a single item from a party pool (POOL rule). First-click wins. */
function handleLootTake(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;
  const session = ctx.state.players.get(characterId);
  if (!session) return;
  if (ctx.tradeSys.isInTrade(characterId)) return;

  const party = ctx.partySys.getPartyForMember(characterId);
  if (!party) return;
  const result = ctx.loot.claimFromPartyPool(party.partyId, data?.lootId);
  if (!result) return;

  const added = ctx.playerSys.addItemToInventory(session, result.itemId, result.quantity);
  if (!added) {
    ctx.loot.addToPartyPool(party.partyId, { itemId: result.itemId, quantity: result.quantity }, data?.lootId);
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: 'Inventory full.', type: 'error' }
    });
    return;
  }
  ctx.questSys.onItemCollect(session, result.itemId);
  ctx.sendToPlayer(characterId, {
    type: PacketType.LOOT_TAKE,
    timestamp: Date.now(),
    data: { lootId: data?.lootId, itemId: result.itemId, quantity: result.quantity }
  });
  ctx.sendToPlayer(characterId, {
    type: PacketType.INVENTORY_UPDATE,
    timestamp: Date.now(),
    data: { inventory: session.inventory, equipment: session.equipment }
  });
  for (const m of party.members) {
    ctx.sendToPlayer(m.characterId, {
      type: PacketType.PARTY_LOOT_RESULT,
      timestamp: Date.now(),
      data: { lootId: data?.lootId, itemId: result.itemId, winnerId: characterId, claimed: true }
    });
  }
}

/** Leader switches the party loot rule. */
function handleLootRuleChange(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;
  const party = ctx.partySys.getPartyForMember(characterId);
  if (!party || party.leaderId !== characterId) return;

  const rule = normalizeLootRule(data?.rule);
  party.settings.lootRule = rule;
  ctx.sendPartyUpdate(party.partyId);
}

/** Submit a need/greed/pass choice for an in-progress roll. */
function handleLootRollSubmit(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;
  const party = ctx.partySys.getPartyForMember(characterId);
  if (!party) return;

  const kind = data?.kind as LootRollKind;
  if (kind !== 'need' && kind !== 'greed' && kind !== 'pass') return;

  const entry = ctx.loot.submitRoll(party.partyId, data?.lootId, characterId, kind);
  if (!entry) return;

  // If everyone has rolled, resolve immediately
  if (ctx.loot.isRollComplete(data?.lootId)) {
    const result = ctx.loot.resolveRoll(party.partyId, data?.lootId);
    if (result) {
      for (const m of party.members) {
        ctx.sendToPlayer(m.characterId, {
          type: PacketType.PARTY_LOOT_RESULT,
          timestamp: Date.now(),
          data: {
            lootId: data?.lootId,
            itemId: result.entry.itemId,
            itemName: result.entry.itemName,
            quantity: result.entry.quantity,
            winnerId: result.winnerId,
            rolls: entry.rolls,
          }
        });
      }
      if (result.winnerId) {
        const ws = ctx.state.players.get(result.winnerId);
        if (ws) {
          ctx.playerSys.addItemToInventory(ws, result.entry.itemId, result.entry.quantity);
          ctx.sendToPlayer(result.winnerId, {
            type: PacketType.INVENTORY_UPDATE,
            timestamp: Date.now(),
            data: { inventory: ws.inventory, equipment: ws.equipment }
          });
        }
      }
    }
  }
}

function handleItemDrop(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  if (ctx.tradeSys.isInTrade(characterId)) return;

  const { itemId, quantity } = data;
  if (!itemId || quantity <= 0) return;

  const removed = ctx.playerSys.removeItemFromInventory(session, itemId, quantity);
  if (removed) {
    const itemDef = ctx.itemSys.getItemDefinition(itemId);
    const name = itemDef?.name || itemId;
    ctx.sendToPlayer(characterId, {
      type: PacketType.INVENTORY_UPDATE,
      timestamp: Date.now(),
      data: { inventory: session.inventory, equipment: session.equipment }
    });
    ctx.sendToPlayer(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message: `Trashed ${name}${quantity > 1 ? ` x${quantity}` : ''}.`, type: 'info' }
    });
  }
}
