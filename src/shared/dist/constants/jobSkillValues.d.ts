import type { JobId } from '../types/jobs';
export interface JobSkillEntry {
    minAdeptness: number;
    maxPotential: number;
}
export interface HotJobConfig {
    proficiencyStat: string;
    coef: number;
}
export declare const HOT_JOB_CONFIG: Partial<Record<JobId, HotJobConfig>>;
export declare const DESIGN_JOB_IDS: Record<number, string>;
export declare const ALL_SUB_CATEGORIES: readonly ["Slash", "Thrust", "Cleave", "Bash", "Defend", "Shot", "Alchemy", "Assassination", "Trap", "Dodge", "Grace", "Blessing", "Exorcism", "Hymn", "Elemental", "Invocation", "Darkness", "Confusion", "Racial", "Horsemanship"];
export declare const JOB_SKILL_VALUES: Record<number, Record<string, JobSkillEntry>>;
export declare function getJobSkillValues(designJobId: number): Record<string, JobSkillEntry>;
export declare function getMinAdeptness(designJobId: number, subCategoryName: string): number;
export declare function getMaxPotential(designJobId: number, subCategoryName: string): number;
export declare function getDesignJobId(jobId: string): number;
