import { StatusEffect, StatusEffectType } from '../types/status';

export interface ElementalDamageLine {
  element: string;
  damage: number;
}

const ELEMENT_RESIST_KEYS: Record<string, string> = {
  fire: 'fireResist',
  ice: 'iceResist',
  lightning: 'lightningResist',
  dark: 'darkResist',
  holy: 'holyResist',
  poison: 'poisonResist',
};

/**
 * Caller resolves the weapon's base element/power from the item definition
 * (via ItemSystem) and passes it in directly, so this util stays free of any
 * data-source dependency and works equally for static or DB-backed items.
 */
export function calculateWeaponElementalDamage(
  weaponElement: string | null | undefined,
  weaponElementPower: number | undefined,
  statusEffects: StatusEffect[],
  attackerSPI: number,
  attackerINT: number,
  attackerLevel: number,
  targetResists: Record<string, number | undefined>,
  enhancementElement?: string | null,
  enhancementLevel?: number,
  auraDamageMultiplier?: number
): ElementalDamageLine[] {
  const lines: ElementalDamageLine[] = [];

  const resolvedElement = enhancementElement || null;
  const isMagicEnhancement = resolvedElement?.startsWith('magic_') || false;
  const hasBaseElement = weaponElement && weaponElementPower;

  if (hasBaseElement && !isMagicEnhancement) {
    const el = weaponElement!;
    const basePower = weaponElementPower!;
    let damage = Math.floor(
      basePower * (attackerSPI * 0.3 + attackerINT * 0.2 + attackerLevel * 0.2)
    );
    damage = applyResistance(damage, el, targetResists);
    damage = Math.max(1, Math.floor(damage * (0.9 + Math.random() * 0.2)));
    if (damage > 0) {
      lines.push({ element: el, damage });
    }
  }

  if (resolvedElement && !isMagicEnhancement && (enhancementLevel || 0) > 0) {
    const basePower = 1 + (enhancementLevel || 0) * 0.5;
    let damage = Math.floor(
      basePower * (attackerSPI * 0.3 + attackerINT * 0.2 + attackerLevel * 0.2)
    );
    damage = applyResistance(damage, resolvedElement, targetResists);
    damage = Math.max(1, Math.floor(damage * (0.9 + Math.random() * 0.2)));
    if (damage > 0) {
      lines.push({ element: resolvedElement, damage });
    }
  }

  const auraMultiplier = auraDamageMultiplier ?? 1;

  for (const effect of statusEffects) {
    if (effect.type === StatusEffectType.WEAPON_AURA && effect.buffData?.weaponAura) {
      const { element, minDamage, maxDamage } = effect.buffData.weaponAura;
      let damage = Math.floor(minDamage * auraMultiplier) + Math.floor(Math.random() * (Math.floor(maxDamage * auraMultiplier) - Math.floor(minDamage * auraMultiplier) + 1));
      damage = applyResistance(damage, element, targetResists);
      if (damage > 0) {
        lines.push({ element, damage });
      }
    }
  }

  return lines;
}

export function getMagicEnhancementElement(enhancementElement?: string | null): string | null {
  if (!enhancementElement?.startsWith('magic_')) return null;
  return enhancementElement.slice(6);
}

export function getMagicEnhancementBoost(
  enhancementElement: string | null | undefined,
  enhancementLevel: number | undefined,
  spellElement: string | null | undefined
): number {
  if (!enhancementElement?.startsWith('magic_')) return 0;
  const enhElement = enhancementElement.slice(6);
  if (spellElement && enhElement === spellElement) {
    return 1 + (enhancementLevel || 0) * 0.08;
  }
  return 0;
}

export function computeElementalDamageLine(
  basePower: number,
  attackerSPI: number,
  attackerINT: number,
  attackerLevel: number,
  element: string,
  targetResists: Record<string, number | undefined>
): ElementalDamageLine {
  let damage = Math.floor(
    basePower * (attackerSPI * 0.3 + attackerINT * 0.2 + attackerLevel * 0.2)
  );
  damage = applyResistance(damage, element, targetResists);
  damage = Math.max(1, Math.floor(damage * (0.9 + Math.random() * 0.2)));
  return { element, damage };
}

function applyResistance(
  damage: number,
  element: string,
  targetResists: Record<string, number | undefined>
): number {
  const resistKey = ELEMENT_RESIST_KEYS[element];
  if (!resistKey) return damage;
  const resist = targetResists[resistKey] || 0;
  if (resist === 0) return damage;
  const multiplier = resist > 0
    ? 1 - Math.min(0.75, resist / 100)
    : 1 + Math.min(1.0, Math.abs(resist) / 100);
  return Math.floor(damage * multiplier);
}
