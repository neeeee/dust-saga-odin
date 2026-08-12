import { Socket } from 'socket.io';
import { PacketType, CraftProfession, NPC_DATABASE } from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.CRAFT_REQUEST, handleCraftRequest);
}

/**
 * Craft request — player asks the server to craft `recipeId` at `npcId`.
 * The server validates:
 *   1. Player is in range of the NPC
 *   2. Player knows the recipe (learned via RECIPE item use)
 *   3. The NPC's profession matches the recipe's profession
 *   4. Player level is high enough + all materials present
 *
 * On success: consume materials, produce result item, broadcast CRAFT_RESULT.
 */
function handleCraftRequest(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;
  const session = ctx.state.players.get(characterId);
  if (!session) return;
  if (ctx.tradeSys.isInTrade(characterId)) return;

  const recipeId = data?.recipeId;
  const npcId = data?.npcId;
  if (!recipeId || !npcId) {
    ctx.sendToPlayer(characterId, { type: PacketType.ERROR, timestamp: Date.now(), data: { message: 'Invalid craft request.' } });
    return;
  }

  const npc = NPC_DATABASE[npcId];
  if (!npc) {
    ctx.sendToPlayer(characterId, { type: PacketType.ERROR, timestamp: Date.now(), data: { message: 'Unknown NPC.' } });
    return;
  }

  // Range check
  const dx = session.position.x - npc.position.x;
  const dz = session.position.z - npc.position.z;
  if (Math.sqrt(dx * dx + dz * dz) > 5) {
    ctx.sendToPlayer(characterId, { type: PacketType.ERROR, timestamp: Date.now(), data: { message: 'Too far from NPC.' } });
    return;
  }

  // Profession check: NPC must be tagged with a crafting profession (stored
  // on NPCDefinition.craftProfession — see npcHandlers).
  const npcProfession = (npc as any).craftProfession as CraftProfession | undefined;
  const recipe = ctx.craftSys.resolveCraftableRecipe(session, recipeId, npcProfession);
  if (!recipe) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.CRAFT_RESULT,
      timestamp: Date.now(),
      data: { success: false, error: 'You do not know that recipe, or this NPC cannot craft it.' }
    });
    return;
  }

  const plan = ctx.craftSys.planCraft(session, recipe);
  if (!plan.success) {
    ctx.sendToPlayer(characterId, {
      type: PacketType.CRAFT_RESULT,
      timestamp: Date.now(),
      data: { success: false, error: plan.error }
    });
    return;
  }

  // Execute: consume materials, produce result
  for (const mat of plan.consumedMaterials || []) {
    ctx.playerSys.removeItemFromInventory(session, mat.itemId, mat.quantity);
  }
  const added = ctx.playerSys.addItemToInventory(session, plan.producedItemId!, plan.producedQuantity || 1);
  if (!added) {
    // Refund on inventory full
    for (const mat of plan.consumedMaterials || []) {
      ctx.playerSys.addItemToInventory(session, mat.itemId, mat.quantity);
    }
    ctx.sendToPlayer(characterId, {
      type: PacketType.CRAFT_RESULT,
      timestamp: Date.now(),
      data: { success: false, error: 'Inventory full.' }
    });
    return;
  }

  ctx.questSys.onItemCollect(session, plan.producedItemId!);
  ctx.sendToPlayer(characterId, {
    type: PacketType.CRAFT_RESULT,
    timestamp: Date.now(),
    data: {
      success: true,
      recipeId,
      producedItemId: plan.producedItemId,
      producedQuantity: plan.producedQuantity,
    }
  });
  ctx.sendToPlayer(characterId, {
    type: PacketType.INVENTORY_UPDATE,
    timestamp: Date.now(),
    data: { inventory: session.inventory, equipment: session.equipment }
  });
}
