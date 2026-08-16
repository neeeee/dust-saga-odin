import { JobId, JobDefinition } from '../types/jobs';
import { Race, StatPoints } from '../types/races';
import { MAX_LEVEL, MAX_STAT_VALUE } from '../constants/races';
export { JobId, BaseClass, JOB_DEFINITIONS } from '../types/jobs';
export declare function getExperienceToNextLevel(level: number): number;
export declare function calculateMaxLP(job: JobDefinition, level: number, sta: number): number;
export declare function calculateMaxMP(job: JobDefinition, level: number, spi: number): number;
export declare function calculateDerivedStats(race: Race, jobId: JobId, level: number, allocatedStats: StatPoints): {
    maxHealth: number;
    maxMana: number;
    attack: number;
    defense: number;
    speed: number;
    magicAttack: number;
    critChance: number;
    baseStats: {
        STA: number;
        STR: number;
        AGI: number;
        DEX: number;
        SPI: number;
        INT: number;
    };
};
export declare function getStatPointsGainedAtLevel(level: number): number;
export declare function getSkillPointsGainedAtLevel(level: number): number;
export { MAX_LEVEL, MAX_STAT_VALUE, getExperienceToNextLevel as getExperienceToNext };
