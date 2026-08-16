export declare enum ItemType {
    WEAPON = "weapon",
    ARMOR = "armor",
    HELMET = "helmet",
    BOOTS = "boots",
    GLOVES = "gloves",
    LEGS = "legs",
    SHIELD = "shield",
    EARRING = "earring",
    NECKLACE = "necklace",
    BELT = "belt",
    RING = "ring",
    ACCESSORY = "accessory",
    CONSUMABLE = "consumable",
    MATERIAL = "material",
    RECIPE = "recipe",
    QUEST = "quest"
}
export declare enum WeaponType {
    SWORD = "sword",
    DAGGER = "dagger",
    BOW = "bow",
    CROSSBOW = "crossbow",
    BLUNT = "blunt",
    TWO_HANDED_BLUNT = "2h_blunt",
    AXE = "axe",
    TWO_HANDED_AXE = "2h_axe",
    TWO_HANDED_SWORD = "2h_sword",
    SPEAR = "spear",
    TWO_HANDED_SPEAR = "2h_spear",
    STAFF = "staff",
    WAND = "wand",
    KNUCKLES = "knuckles"
}
export declare const RANGED_WEAPON_TYPES: Set<WeaponType>;
export declare enum ItemRarity {
    COMMON = "common",
    UNCOMMON = "uncommon",
    RARE = "rare",
    EPIC = "epic",
    LEGENDARY = "legendary"
}
export declare enum EquipmentSlot {
    WEAPON = "weapon",
    ARMOR = "armor",
    HELMET = "helmet",
    BOOTS = "boots",
    GLOVES = "gloves",
    LEGS = "legs",
    SHIELD = "shield",
    EARRING_1 = "earring_1",
    EARRING_2 = "earring_2",
    NECKLACE = "necklace",
    BELT = "belt",
    RING_1 = "ring_1",
    RING_2 = "ring_2"
}
export interface ItemStats {
    attack?: number;
    magicAttack?: number;
    defense?: number;
    health?: number;
    mana?: number;
    speed?: number;
    criticalChance?: number;
    STA?: number;
    STR?: number;
    AGI?: number;
    DEX?: number;
    SPI?: number;
    INT?: number;
    accuracy?: number;
    dodge?: number;
    attackSpeed?: number;
    castSpeed?: number;
    fireResist?: number;
    iceResist?: number;
    lightningResist?: number;
    poisonResist?: number;
    darkResist?: number;
    holyResist?: number;
    ailmentResist?: number;
    disorderResist?: number;
    stunResist?: number;
    tripResist?: number;
    freezeResist?: number;
    burnResist?: number;
    curseResist?: number;
    bleedResist?: number;
    sleepResist?: number;
    weaknessResist?: number;
    weakenResist?: number;
    knockdownResist?: number;
    knockbackResist?: number;
    weaponElement?: 'fire' | 'ice' | 'lightning' | 'holy' | 'dark' | 'poison';
    weaponElementPower?: number;
    healPercent?: number;
}
export type ProcEffectType = 'weaken' | 'burn' | 'sleep' | 'freeze' | 'drainLife' | 'trip' | 'stun' | 'poison' | 'bleed' | 'silence' | 'castSpeedDown' | 'slow';
export interface OnHitProc {
    effect: ProcEffectType;
    baseChance: number;
    chancePerLevel?: number;
    minLevel?: number;
    duration?: number;
    potency?: number;
    element?: string;
}
export interface ItemDefinition {
    id: string;
    name: string;
    type: ItemType;
    rarity: ItemRarity;
    stats: ItemStats;
    description: string;
    icon?: string;
    maxStack: number;
    sellPrice: number;
    requiredLevel: number;
    equipmentSlot?: EquipmentSlot;
    soulSlots?: number;
    weaponType?: WeaponType;
    onHitProcs?: OnHitProc[];
    innateProcs?: OnHitProc[];
    /**
     * Marks a weapon as an "Obelisk" weapon: while equipped and enhanced, it
     * grants the Obelisk buff (magic-resist ignored on the wielder's magic
     * attacks + flat damage-taken reduction), scaling with enhancement level per
     * OBELISK_BUFF_TABLE. Mutually exclusive with the Guardian skill buff.
     */
    obeliskBuff?: boolean;
    /** For RECIPE items: the recipe id this item teaches when consumed. */
    teachesRecipe?: string;
}
export interface InventoryItem {
    itemId: string;
    quantity: number;
    slot: number;
    enhancementLevel?: number;
    enhancementElement?: 'fire' | 'ice' | 'lightning' | 'holy' | 'dark' | 'poison' | 'magic_fire' | 'magic_ice' | 'magic_lightning' | 'magic_holy' | 'magic_dark' | 'magic_poison';
}
export interface Equipment {
    weapon: InventoryItem | null;
    armor: InventoryItem | null;
    helmet: InventoryItem | null;
    boots: InventoryItem | null;
    gloves: InventoryItem | null;
    legs: InventoryItem | null;
    shield: InventoryItem | null;
    earring_1: InventoryItem | null;
    earring_2: InventoryItem | null;
    necklace: InventoryItem | null;
    belt: InventoryItem | null;
    ring_1: InventoryItem | null;
    ring_2: InventoryItem | null;
}
export declare const DEFAULT_EQUIPMENT: Equipment;
export declare function normalizeEquipment(equipment: any): Equipment;
export interface LootDrop {
    itemId: string;
    quantity: number;
    chance: number;
}
export interface LootTable {
    rolls: number;
    drops: LootDrop[];
}
