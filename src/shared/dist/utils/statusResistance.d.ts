export declare function computeResist(totalStat: number, divisor: number, perStep: number, gearBonus?: number): number;
export declare function computeAilmentResist(totalSTA: number, gearBonus?: number): number;
export declare function computeDisorderResist(totalSPI: number, gearBonus?: number): number;
export declare function computeDebuffAccuracy(casterSPI: number, proficiencyAdeptness: number, category: string): number;
export declare function rollDebuffApplication(accuracy: number, resistPercent: number): {
    applied: boolean;
    roll: number;
};
