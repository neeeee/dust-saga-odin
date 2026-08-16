import { Socket } from 'socket.io';
import {
  Packet, PacketType,
} from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.WEAPON_ENHANCE, handleWeaponEnhance);
}

function handleWeaponEnhance(ctx: NetworkContext, socket: Socket, data: any): void {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (!session) return;

  if (ctx.tradeSys.isInTrade(characterId)) return;

  const { weaponSlot, materialSlots } = data;
  if (!weaponSlot?.slotIndex && weaponSlot?.slotIndex !== 0) {
    ctx.sendToPlayer(characterId, { type: PacketType.NOTIFICATION, timestamp: Date.now(), data: { message: 'No weapon selected.', type: 'error' } });
    return;
  }

  const weaponItem = session.inventory[weaponSlot.slotIndex];
  if (!weaponItem) {
    ctx.sendToPlayer(characterId, { type: PacketType.NOTIFICATION, timestamp: Date.now(), data: { message: 'Weapon not found in inventory.', type: 'error' } });
    return;
  }

  const weaponDef = ctx.itemSys.getItemDefinition(weaponItem.itemId);
  if (!weaponDef) {
    ctx.sendToPlayer(characterId, { type: PacketType.NOTIFICATION, timestamp: Date.now(), data: { message: 'Invalid weapon.', type: 'error' } });
    return;
  }

  const enhancableTypes: string[] = ['weapon', 'armor', 'helmet', 'boots', 'gloves', 'legs', 'shield'];
  if (!enhancableTypes.includes(weaponDef.type) && !weaponDef.equipmentSlot) {
    ctx.sendToPlayer(characterId, { type: PacketType.NOTIFICATION, timestamp: Date.now(), data: { message: 'This item cannot be enhanced.', type: 'error' } });
    return;
  }

  const currentLevel = weaponItem.enhancementLevel || 0;
  if (currentLevel >= 10) {
    ctx.sendToPlayer(characterId, { type: PacketType.NOTIFICATION, timestamp: Date.now(), data: { message: 'Enhancement level is already at maximum.', type: 'error' } });
    return;
  }

  const GEM_ELEMENT_MAP: Record<string, string> = {
    fire_gem: 'fire', ice_gem: 'ice', lightning_gem: 'lightning',
    holy_gem: 'holy', dark_gem: 'dark', poison_gem: 'poison',
    fire_magic_gem: 'magic_fire', ice_magic_gem: 'magic_ice', lightning_magic_gem: 'magic_lightning',
    holy_magic_gem: 'magic_holy', dark_magic_gem: 'magic_dark', poison_magic_gem: 'magic_poison',
  };

  let element: string | null = weaponItem.enhancementElement || null;
  const materialSlotArr: Array<{ slotIndex: number } | null> = materialSlots || [];
  const consumedSlots: number[] = [];

  for (const mat of materialSlotArr) {
    if (!mat?.slotIndex && mat?.slotIndex !== 0) continue;
    const matItem = session.inventory[mat.slotIndex];
    if (!matItem || matItem.quantity <= 0) continue;
    const matDef = ctx.itemSys.getItemDefinition(matItem.itemId);
    if (!matDef) continue;

    const gemElement = GEM_ELEMENT_MAP[matItem.itemId];
    if (gemElement) {
      if (element === null) {
        element = gemElement;
      } else if (element !== gemElement) {
        ctx.sendToPlayer(characterId, { type: PacketType.NOTIFICATION, timestamp: Date.now(), data: { message: 'Cannot mix different element gems.', type: 'error' } });
        return;
      }
      consumedSlots.push(mat.slotIndex);
    }
  }

  if (!element) {
    ctx.sendToPlayer(characterId, { type: PacketType.NOTIFICATION, timestamp: Date.now(), data: { message: 'No element gem provided.', type: 'error' } });
    return;
  }

  const ENHANCE_FAILURE_CHANCE: number[] = [0, 0, 5, 15, 25, 35, 50, 65, 80, 90];
  const failChance = currentLevel < ENHANCE_FAILURE_CHANCE.length ? ENHANCE_FAILURE_CHANCE[currentLevel] : 50;
  if (Math.random() * 100 < failChance) {
    const sortedSlots = [...consumedSlots].sort((a, b) => b - a);
    for (const slotIdx of sortedSlots) {
      const matItem = session.inventory[slotIdx];
      if (matItem) {
        matItem.quantity -= 1;
        if (matItem.quantity <= 0) {
          session.inventory.splice(slotIdx, 1);
        }
      }
    }
    session.inventory.forEach((s, i) => { s.slot = i; });
    ctx.sendToPlayer(characterId, { type: PacketType.NOTIFICATION, timestamp: Date.now(), data: { message: `Enhancement failed! Level remains at +${currentLevel}.`, type: 'error' } });
    ctx.sendToPlayer(characterId, {
      type: PacketType.ENHANCEMENT_RESULT,
      timestamp: Date.now(),
      data: { success: false, weaponSlotIndex: weaponSlot.slotIndex, enhancementLevel: currentLevel, enhancementElement: element }
    });
    ctx.sendToPlayer(characterId, {
      type: PacketType.INVENTORY_UPDATE,
      timestamp: Date.now(),
      data: { inventory: session.inventory, equipment: session.equipment }
    });
    return;
  }

  const newLevel = currentLevel + 1;
  weaponItem.enhancementLevel = newLevel;
  weaponItem.enhancementElement = element as any;

  const sortedSlots = [...consumedSlots].sort((a, b) => b - a);
  for (const slotIdx of sortedSlots) {
    const matItem = session.inventory[slotIdx];
    if (matItem) {
      matItem.quantity -= 1;
      if (matItem.quantity <= 0) {
        session.inventory.splice(slotIdx, 1);
      }
    }
  }
  session.inventory.forEach((s, i) => { s.slot = i; });

  ctx.playerSys.recalcStats(session);

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
    type: PacketType.ENHANCEMENT_RESULT,
    timestamp: Date.now(),
    data: { success: true, weaponSlotIndex: weaponSlot.slotIndex, enhancementLevel: newLevel, enhancementElement: element }
  });
}
