import type { ClassSpecificSkill } from "../types/skills";
import { BaseClass } from "../types/jobs";
export declare const CLASS_SPECIFIC_SKILLS: Record<number, Record<string, ClassSpecificSkill>>;
export declare const JOB_TO_CLASS_SKILLS_INDEX: Record<string, number>;
export declare function getClassSpecificSkillsForJob(jobId: string, baseClass: BaseClass): Record<string, ClassSpecificSkill>;
