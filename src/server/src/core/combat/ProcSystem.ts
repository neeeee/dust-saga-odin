import {
  PlayerSession, StatusEffect, StatusEffectType,
  OnHitProc, ProcEffectType, STATUS_EFFECT_DEFS,
} from '@dust-saga/shared';
import type { ItemSystem } from '../../systems/ItemSystem';

interface ProcMapping {
  statusType: StatusEffectType;
  debuffCategory?: 'ailment' | 'disorder' | 'stun' | 'trip' | 'freeze' | 'burn' | 'curse' | 'bleed' | 'sleep' | 'weakness' | 'weaken' | 'knockdown' | 'knockback';
  tickInterval?: number;
}

const PROC_EFFECT_MAP: Record<ProcEffectType, ProcMapping> = {
  weaken:        { statusType: StatusEffectType.BUFF_GENERIC,          debuffCategory: 'weaken' },
  burn:          { statusType: StatusEffectType.BURN,                  debuffCategory: 'burn',    tickInterval: 1000 },
  sleep:         { statusType: StatusEffectType.SLEEP,                 debuffCategory: 'sleep' },
  freeze:        { statusType: StatusEffectType.FREEZE,                debuffCategory: 'freeze' },
  drainLife:     { statusType: StatusEffectType.BUFF_GENERIC },
  trip:          { statusType: StatusEffectType.BUFF_GENERIC,          debuffCategory: 'trip' },
  stun:          { statusType: StatusEffectType.STUN,                  debuffCategory: 'stun' },
  poison:        { statusType: StatusEffectType.POISON,                debuffCategory: 'ailment', tickInterval: 3000 },
  bleed:         { statusType: StatusEffectType.BLEED,                 debuffCategory: 'bleed',   tickInterval: 2000 },
  silence:       { statusType: StatusEffectType.SILENCE,               debuffCategory: 'ailment' },
  castSpeedDown: { statusType: StatusEffectType.DEBUFF_CAST_SPEED_DOWN,debuffCategory: 'disorder' },
  slow:          { statusType: StatusEffectType.SLOW,                  debuffCategory: 'ailment' },
};

export interface CollectedProcs {
  procs: OnHitProc[];
  enhancementLevel: number;
  enhancementElement?: string;
}

export function collectProcs(session: PlayerSession, itemSys: ItemSystem): CollectedProcs {
  const procs: OnHitProc[] = [];

  const souls = session.socketedSouls;
  if (souls) {
    for (const soul of souls) {
      if (!soul) continue;
      const def = itemSys.getItemDefinition(soul.itemId);
      if (def?.onHitProcs) {
        procs.push(...def.onHitProcs);
      }
    }
  }

  const weapon = session.equipment?.weapon;
  let enhancementLevel = 0;
  let enhancementElement: string | undefined;

  if (weapon) {
    enhancementLevel = weapon.enhancementLevel || 0;
    enhancementElement = weapon.enhancementElement;
    const weaponDef = itemSys.getItemDefinition(weapon.itemId);
    if (weaponDef?.innateProcs) {
      for (const proc of weaponDef.innateProcs) {
        if (proc.element && proc.element !== enhancementElement) continue;
        procs.push(proc);
      }
    }
  }

  return { procs, enhancementLevel, enhancementElement };
}

export function buildProcStatusEffect(
  proc: OnHitProc,
  sourceId: string,
  targetId: string,
): StatusEffect | null {
  const mapping = PROC_EFFECT_MAP[proc.effect];
  if (!mapping) return null;

  const def = STATUS_EFFECT_DEFS[mapping.statusType];
  if (!def) return null;

  const now = Date.now();
  const durationMs = (proc.duration || 0) * 1000 || def.duration;

  return {
    id: `proc_${proc.effect}_${targetId}_${now}`,
    type: mapping.statusType,
    sourceId,
    targetId,
    potency: proc.potency || 0,
    appliedAt: now,
    duration: durationMs,
    tickInterval: mapping.tickInterval ?? def.tickInterval,
    lastTickAt: now,
    stacks: 1,
    skillName: `proc_${proc.effect}`,
    debuffCategory: mapping.debuffCategory,
  };
}

export function getProcResistCategory(proc: OnHitProc): string | undefined {
  const mapping = PROC_EFFECT_MAP[proc.effect];
  return mapping?.debuffCategory;
}

export function isDrainLifeProc(proc: OnHitProc): boolean {
  return proc.effect === 'drainLife';
}

const DARK_RECOIL_TABLE: Record<number, number> = {
  0: 0.50, 1: 0.50, 2: 0.50, 3: 0.50, 4: 0.50,
  5: 0.40, 6: 0.36, 7: 0.30, 8: 0.25, 9: 0.15, 10: 0.12,
};

export function getDarkRecoilPercent(enhancementLevel: number): number {
  return DARK_RECOIL_TABLE[enhancementLevel] ?? 0;
}
