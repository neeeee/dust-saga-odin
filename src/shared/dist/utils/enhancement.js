"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getEnhancedItemName = getEnhancedItemName;
const ELEMENT_PREFIXES = {
    fire: 'Flaming',
    ice: 'Icy',
    lightning: 'Thunderous',
    holy: 'Blessed',
    dark: 'Darkened',
    poison: 'Poisonous',
    magic_fire: 'Arcane Fire',
    magic_ice: 'Arcane Ice',
    magic_lightning: 'Arcane Storm',
    magic_holy: 'Arcane Holy',
    magic_dark: 'Arcane Shadow',
    magic_poison: 'Arcane Venom',
};
function getEnhancedItemName(baseName, enhancementLevel, enhancementElement) {
    const prefix = enhancementElement ? (ELEMENT_PREFIXES[enhancementElement] || '') : '';
    const suffix = enhancementLevel ? ` +${enhancementLevel}` : '';
    return prefix ? `${prefix} ${baseName}${suffix}` : `${baseName}${suffix}`;
}
