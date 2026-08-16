export interface TradeOfferItem {
  slot: number;
  itemId: string;
  quantity: number;
  enhancementLevel?: number;
  enhancementElement?: string;
}

export interface TradeOffer {
  items: TradeOfferItem[];
  gold: number;
  accepted: boolean;
}

export interface TradeState {
  partnerName: string;
  partnerId: string;
  yourOffer: TradeOffer;
  theirOffer: TradeOffer;
}
