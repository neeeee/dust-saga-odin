import { ItemDefinition } from '../types/items';
export declare const ITEM_DATABASE: Record<string, ItemDefinition>;
export declare function getItem(id: string): ItemDefinition | undefined;
