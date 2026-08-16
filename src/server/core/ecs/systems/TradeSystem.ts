import {
  PacketType, Packet, PlayerSession, InventoryItem,
  TradeOffer, TradeOfferItem, TradeState,
  GAME_CONFIG,
} from '@dust-saga/shared';
import type { ItemSystem } from '../../../systems/ItemSystem';

interface TradeSession {
  id: string;
  playerA: string;
  playerB: string;
  nameA: string;
  nameB: string;
  offerA: TradeOffer;
  offerB: TradeOffer;
  acceptedA: boolean;
  acceptedB: boolean;
  state: 'open' | 'executing' | 'done' | 'cancelled';
  zoneId: string;
}

const TRADE_DISTANCE = 5;
const MAX_OFFER_SLOTS = 12;

export class TradeSystem {
  itemSys!: ItemSystem;
  private tradeSessions = new Map<string, TradeSession>();
  private playerTrade = new Map<string, string>();
  private pendingInvites = new Map<string, string>();
  private nextId = 1;

  private sendFn: (characterId: string, packet: Packet) => void = () => {};
  private getPlayerFn: (characterId: string) => PlayerSession | undefined = () => undefined;

  init(opts: {
    sendToPlayer: (characterId: string, packet: Packet) => void;
    findPlayer: (characterId: string) => PlayerSession | undefined;
  }): void {
    this.sendFn = opts.sendToPlayer;
    this.getPlayerFn = opts.findPlayer;
  }

  isInTrade(characterId: string): boolean {
    return this.playerTrade.has(characterId);
  }

  hasPendingInvite(characterId: string): boolean {
    return this.pendingInvites.has(characterId);
  }

  requestTrade(
    requesterId: string,
    requesterSession: PlayerSession,
    targetId: string,
    targetSession: PlayerSession
  ): void {
    if (requesterSession.currentNpcId) {
      this.notify(requesterId, 'Finish talking to the NPC first.');
      return;
    }
    if (targetSession.currentNpcId) {
      this.notify(requesterId, `${targetSession.characterName} is busy.`);
      return;
    }
    if (this.isInTrade(requesterId) || this.hasPendingInvite(requesterId)) {
      this.notify(requesterId, 'You are already in a trade.');
      return;
    }
    if (this.isInTrade(targetId) || this.hasPendingInvite(targetId)) {
      this.notify(requesterId, `${targetSession.characterName} is already trading.`);
      return;
    }
    if (requesterSession.zoneId !== targetSession.zoneId) {
      this.notify(requesterId, 'Target is too far away.');
      return;
    }
    const dx = requesterSession.position.x - targetSession.position.x;
    const dz = requesterSession.position.z - targetSession.position.z;
    if (Math.sqrt(dx * dx + dz * dz) > TRADE_DISTANCE) {
      this.notify(requesterId, 'Target is too far away.');
      return;
    }

    this.pendingInvites.set(targetId, requesterId);

    this.sendFn(targetId, {
      type: PacketType.TRADE_INVITE,
      timestamp: Date.now(),
      data: { fromName: requesterSession.characterName, fromId: requesterId },
    });
  }

  respondToInvite(responderId: string, accepted: boolean): void {
    const requesterId = this.pendingInvites.get(responderId);
    if (!requesterId) return;

    this.pendingInvites.delete(responderId);

    if (!accepted) return;

    const requester = this.getPlayerFn(requesterId);
    const responder = this.getPlayerFn(responderId);
    if (!requester || !responder) {
      this.notify(responderId, 'Trade partner no longer available.');
      return;
    }
    if (this.isInTrade(requesterId) || this.isInTrade(responderId)) {
      this.notify(responderId, 'Trade no longer possible.');
      return;
    }
    if (requester.zoneId !== responder.zoneId) {
      this.notify(responderId, 'Too far away to trade.');
      return;
    }

    const tradeId = `trade_${this.nextId++}_${Date.now()}`;
    const trade: TradeSession = {
      id: tradeId,
      playerA: requesterId,
      playerB: responderId,
      nameA: requester.characterName,
      nameB: responder.characterName,
      offerA: { items: [], gold: 0, accepted: false },
      offerB: { items: [], gold: 0, accepted: false },
      acceptedA: false,
      acceptedB: false,
      state: 'open',
      zoneId: requester.zoneId,
    };

    this.tradeSessions.set(tradeId, trade);
    this.playerTrade.set(requesterId, tradeId);
    this.playerTrade.set(responderId, tradeId);

    this.sendFn(requesterId, {
      type: PacketType.TRADE_OPEN,
      timestamp: Date.now(),
      data: {},
    });
    this.sendFn(responderId, {
      type: PacketType.TRADE_OPEN,
      timestamp: Date.now(),
      data: {},
    });

    this.sendTradeUpdate(trade);
  }

  addItem(playerId: string, slot: number, quantity: number): void {
    const trade = this.getTrade(playerId);
    if (!trade || trade.state !== 'open') return;

    const session = this.getPlayerFn(playerId);
    if (!session) return;

    const isA = trade.playerA === playerId;
    if (isA ? trade.acceptedA : trade.acceptedB) return;

    const invItem = session.inventory.find(s => s.slot === slot);
    if (!invItem) return;

    const offer = isA ? trade.offerA : trade.offerB;

    const alreadyCommitted = offer.items
      .filter(i => i.slot === slot)
      .reduce((sum, i) => sum + i.quantity, 0);
    const available = invItem.quantity - alreadyCommitted;
    const qty = Math.min(quantity, available);
    if (qty <= 0) return;

    const existing = offer.items.find(
      i => i.slot === slot &&
        i.itemId === invItem.itemId &&
        i.enhancementLevel === invItem.enhancementLevel
    );
    if (existing) {
      existing.quantity += qty;
    } else {
      if (offer.items.length >= MAX_OFFER_SLOTS) {
        this.notify(playerId, 'Trade window is full.');
        return;
      }
      offer.items.push({
        slot,
        itemId: invItem.itemId,
        quantity: qty,
        ...(invItem.enhancementLevel !== undefined ? { enhancementLevel: invItem.enhancementLevel } : {}),
        ...(invItem.enhancementElement ? { enhancementElement: invItem.enhancementElement } : {}),
      });
    }

    this.resetAccepts(trade);
    this.sendTradeUpdate(trade);
  }

  removeItem(playerId: string, offerIndex: number): void {
    const trade = this.getTrade(playerId);
    if (!trade || trade.state !== 'open') return;

    const isA = trade.playerA === playerId;
    if (isA ? trade.acceptedA : trade.acceptedB) return;

    const offer = isA ? trade.offerA : trade.offerB;
    if (offerIndex < 0 || offerIndex >= offer.items.length) return;

    offer.items.splice(offerIndex, 1);

    this.resetAccepts(trade);
    this.sendTradeUpdate(trade);
  }

  setGold(playerId: string, gold: number): void {
    const trade = this.getTrade(playerId);
    if (!trade || trade.state !== 'open') return;

    const session = this.getPlayerFn(playerId);
    if (!session) return;

    const isA = trade.playerA === playerId;
    if (isA ? trade.acceptedA : trade.acceptedB) return;

    const clamped = Math.max(0, Math.min(Math.floor(gold), session.gold));
    const offer = isA ? trade.offerA : trade.offerB;
    offer.gold = clamped;

    this.resetAccepts(trade);
    this.sendTradeUpdate(trade);
  }

  acceptOffer(playerId: string): void {
    const trade = this.getTrade(playerId);
    if (!trade || trade.state !== 'open') return;

    if (!this.checkProximity(trade)) {
      this.cancelTradeInternal(trade, 'too_far');
      return;
    }

    const isA = trade.playerA === playerId;
    if (isA) {
      if (trade.acceptedA) return;
      trade.acceptedA = true;
    } else {
      if (trade.acceptedB) return;
      trade.acceptedB = true;
    }

    if (trade.acceptedA && trade.acceptedB) {
      trade.state = 'executing';
      this.executeTrade(trade);
    } else {
      this.sendTradeUpdate(trade);
    }
  }

  cancelTrade(playerId: string): void {
    const trade = this.getTrade(playerId);
    if (!trade) return;
    this.cancelTradeInternal(trade, 'cancelled');
  }

  handleDisconnect(characterId: string): void {
    this.pendingInvites.delete(characterId);
    for (const [targetId, requesterId] of this.pendingInvites) {
      if (requesterId === characterId) {
        this.pendingInvites.delete(targetId);
      }
    }

    const tradeId = this.playerTrade.get(characterId);
    if (!tradeId) return;
    const trade = this.tradeSessions.get(tradeId);
    if (!trade) return;
    this.cancelTradeInternal(trade, 'cancelled');
  }

  private getTrade(playerId: string): TradeSession | undefined {
    const tradeId = this.playerTrade.get(playerId);
    if (!tradeId) return undefined;
    return this.tradeSessions.get(tradeId);
  }

  private resetAccepts(trade: TradeSession): void {
    trade.acceptedA = false;
    trade.acceptedB = false;
  }

  private checkProximity(trade: TradeSession): boolean {
    const a = this.getPlayerFn(trade.playerA);
    const b = this.getPlayerFn(trade.playerB);
    if (!a || !b) return false;
    if (a.zoneId !== b.zoneId) return false;
    const dx = a.position.x - b.position.x;
    const dz = a.position.z - b.position.z;
    return Math.sqrt(dx * dx + dz * dz) <= TRADE_DISTANCE;
  }

  private cancelTradeInternal(trade: TradeSession, reason: string): void {
    trade.state = 'cancelled';

    this.sendFn(trade.playerA, {
      type: PacketType.TRADE_CLOSE,
      timestamp: Date.now(),
      data: { reason },
    });
    this.sendFn(trade.playerB, {
      type: PacketType.TRADE_CLOSE,
      timestamp: Date.now(),
      data: { reason },
    });

    this.playerTrade.delete(trade.playerA);
    this.playerTrade.delete(trade.playerB);
    this.tradeSessions.delete(trade.id);
  }

  private executeTrade(trade: TradeSession): void {
    const sessionA = this.getPlayerFn(trade.playerA);
    const sessionB = this.getPlayerFn(trade.playerB);
    if (!sessionA || !sessionB) {
      this.cancelTradeInternal(trade, 'error');
      return;
    }

    for (const item of trade.offerA.items) {
      const inv = sessionA.inventory.find(s => s.slot === item.slot);
      if (!inv || inv.itemId !== item.itemId || inv.quantity < item.quantity) {
        this.notify(trade.playerA, 'Trade failed: items changed.');
        this.notify(trade.playerB, 'Trade failed: partner items changed.');
        this.cancelTradeInternal(trade, 'error');
        return;
      }
    }
    for (const item of trade.offerB.items) {
      const inv = sessionB.inventory.find(s => s.slot === item.slot);
      if (!inv || inv.itemId !== item.itemId || inv.quantity < item.quantity) {
        this.notify(trade.playerA, 'Trade failed: partner items changed.');
        this.notify(trade.playerB, 'Trade failed: items changed.');
        this.cancelTradeInternal(trade, 'error');
        return;
      }
    }

    if (sessionA.gold < trade.offerA.gold || sessionB.gold < trade.offerB.gold) {
      this.notify(trade.playerA, 'Trade failed: not enough gold.');
      this.notify(trade.playerB, 'Trade failed: not enough gold.');
      this.cancelTradeInternal(trade, 'error');
      return;
    }

    const invA: InventoryItem[] = sessionA.inventory.map(i => ({ ...i }));
    const invB: InventoryItem[] = sessionB.inventory.map(i => ({ ...i }));

    this.removeOfferedFromClone(invA, trade.offerA.items);
    this.removeOfferedFromClone(invB, trade.offerB.items);

    const okA = this.addOfferedToClone(invA, trade.offerB.items);
    const okB = this.addOfferedToClone(invB, trade.offerA.items);

    if (!okA || !okB) {
      this.notify(trade.playerA, 'Trade failed: inventory full.');
      this.notify(trade.playerB, 'Trade failed: inventory full.');
      this.cancelTradeInternal(trade, 'error');
      return;
    }

    sessionA.inventory = invA;
    sessionB.inventory = invB;
    sessionA.gold = sessionA.gold - trade.offerA.gold + trade.offerB.gold;
    sessionB.gold = sessionB.gold - trade.offerB.gold + trade.offerA.gold;

    trade.state = 'done';

    this.sendFn(trade.playerA, {
      type: PacketType.TRADE_CLOSE,
      timestamp: Date.now(),
      data: { reason: 'completed' },
    });
    this.sendFn(trade.playerB, {
      type: PacketType.TRADE_CLOSE,
      timestamp: Date.now(),
      data: { reason: 'completed' },
    });

    this.sendFn(trade.playerA, {
      type: PacketType.INVENTORY_UPDATE,
      timestamp: Date.now(),
      data: { inventory: sessionA.inventory, equipment: sessionA.equipment, gold: sessionA.gold },
    });
    this.sendFn(trade.playerB, {
      type: PacketType.INVENTORY_UPDATE,
      timestamp: Date.now(),
      data: { inventory: sessionB.inventory, equipment: sessionB.equipment, gold: sessionB.gold },
    });

    this.playerTrade.delete(trade.playerA);
    this.playerTrade.delete(trade.playerB);
    this.tradeSessions.delete(trade.id);
  }

  private removeOfferedFromClone(clone: InventoryItem[], items: TradeOfferItem[]): void {
    for (const item of items) {
      const inv = clone.find(s => s.slot === item.slot);
      if (inv) {
        inv.quantity -= item.quantity;
      }
    }
    for (let i = clone.length - 1; i >= 0; i--) {
      if (clone[i].quantity <= 0) {
        clone.splice(i, 1);
      }
    }
  }

  private addOfferedToClone(clone: InventoryItem[], items: TradeOfferItem[]): boolean {
    const usedSlots = new Set(clone.map(s => s.slot));

    for (const item of items) {
      const itemDef = this.itemSys.getItemDefinition(item.itemId);
      const isStackable = itemDef && itemDef.maxStack > 1 && !item.enhancementLevel;

      if (isStackable) {
        const existing = clone.find(s => s.itemId === item.itemId && !s.enhancementLevel);
        if (existing && existing.quantity + item.quantity <= itemDef.maxStack) {
          existing.quantity += item.quantity;
          continue;
        }
      }

      let emptySlot = -1;
      for (let i = 0; i < GAME_CONFIG.MAX_INVENTORY_SLOTS; i++) {
        if (!usedSlots.has(i)) {
          emptySlot = i;
          break;
        }
      }
      if (emptySlot === -1) return false;

      const newItem: InventoryItem = {
        itemId: item.itemId,
        quantity: item.quantity,
        slot: emptySlot,
      };
      if (item.enhancementLevel !== undefined) newItem.enhancementLevel = item.enhancementLevel;
      if (item.enhancementElement) newItem.enhancementElement = item.enhancementElement as any;

      clone.push(newItem);
      usedSlots.add(emptySlot);
    }
    return true;
  }

  private sendTradeUpdate(trade: TradeSession): void {
    const stateA: TradeState = {
      partnerName: trade.nameB,
      partnerId: trade.playerB,
      yourOffer: { items: trade.offerA.items.map(i => ({ ...i })), gold: trade.offerA.gold, accepted: trade.acceptedA },
      theirOffer: { items: trade.offerB.items.map(i => ({ ...i })), gold: trade.offerB.gold, accepted: trade.acceptedB },
    };
    const stateB: TradeState = {
      partnerName: trade.nameA,
      partnerId: trade.playerA,
      yourOffer: { items: trade.offerB.items.map(i => ({ ...i })), gold: trade.offerB.gold, accepted: trade.acceptedB },
      theirOffer: { items: trade.offerA.items.map(i => ({ ...i })), gold: trade.offerA.gold, accepted: trade.acceptedA },
    };

    this.sendFn(trade.playerA, {
      type: PacketType.TRADE_UPDATE,
      timestamp: Date.now(),
      data: stateA,
    });
    this.sendFn(trade.playerB, {
      type: PacketType.TRADE_UPDATE,
      timestamp: Date.now(),
      data: stateB,
    });
  }

  private notify(characterId: string, message: string): void {
    this.sendFn(characterId, {
      type: PacketType.NOTIFICATION,
      timestamp: Date.now(),
      data: { message, type: 'error' },
    });
  }
}
