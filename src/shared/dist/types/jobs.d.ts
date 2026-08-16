import { StatType } from './races';
export declare enum BaseClass {
    WARRIOR = "warrior",
    SCOUT = "scout",
    ACOLYTE = "acolyte",
    MAGE = "mage"
}
export declare enum JobId {
    WARRIOR = "warrior",
    GLADIATOR = "gladiator",
    JUGGERNAUT = "juggernaut",
    DRAGOON = "dragoon",
    KNIGHT = "knight",
    WARLORD = "warlord",
    PALADIN = "paladin",
    SCOUT = "scout",
    ARCHER = "archer",
    SNIPER = "sniper",
    HUNTER = "hunter",
    PROVOCATEUR = "provocateur",
    ASSASSIN = "assassin",
    SABOTEUR = "saboteur",
    ACOLYTE = "acolyte",
    PRIEST = "priest",
    CLERIC = "cleric",
    ENCHANTER = "enchanter",
    ASCETIC = "ascetic",
    MONK = "monk",
    EXORCIST = "exorcist",
    MAGE = "mage",
    WIZARD = "wizard",
    WARLOCK = "warlock",
    CONJURER = "conjurer",
    SORCERER = "sorcerer",
    CORRUPTOR = "corruptor",
    SHADOWBLADE = "shadowblade"
}
export interface JobDefinition {
    id: JobId;
    name: string;
    baseClass: BaseClass;
    tier: 1 | 2 | 3;
    parentJob: JobId | null;
    description: string;
    modelFile: string;
    baseStatModifiers: Partial<Record<StatType, number>>;
    lpBase: number;
    lpPerLevel: number;
    lpPerSta: number;
    mpBase: number;
    mpPerLevel: number;
    mpPerSpi: number;
}
export type SkillCategoryKey = 'melee' | 'technique' | 'prayer' | 'magic' | 'special';
export interface SkillProficiencies {
    melee: number;
    technique: number;
    prayer: number;
    magic: number;
    special: number;
    [subCategoryName: string]: number;
}
export declare const SUB_CATEGORY_TO_CATEGORY: Record<string, SkillCategoryKey>;
export declare function getCategoryTotal(proficiencies: SkillProficiencies, category: SkillCategoryKey): number;
export declare function recalculateCategoryTotals(proficiencies: SkillProficiencies): void;
export declare function createDefaultSkillProficiencies(): SkillProficiencies;
export declare function createDefaultSkillAdeptness(designJobId: number): SkillProficiencies;
export declare function getValidSubCategoryNames(): string[];
export interface ProficiencyGainResult {
    gained: boolean;
    subCategory: string;
    amount: number;
    newAdeptness: number;
    cap: number;
}
export declare function calculateProficiencyGain(currentAdeptness: number, maxProficiency: number, hasCastTime: boolean): ProficiencyGainResult | null;
export interface CharacterInfo {
    id: string;
    name: string;
    race: string;
    jobId: JobId;
    level: number;
    experience: number;
    experienceToNext: number;
    position: {
        x: number;
        y: number;
        z: number;
    };
    rotation: {
        x: number;
        y: number;
        z: number;
        w: number;
    };
    zoneId: string;
}
export declare function getBaseClassForJob(jobId: JobId): BaseClass;
export declare function getAvailableJobs(baseClass: BaseClass, tier: 1 | 2 | 3): JobId[];
export declare function getAdvancementOptions(currentJob: JobId): JobId[];
export declare const JOB_DEFINITIONS: Record<JobId, JobDefinition>;
