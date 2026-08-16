import { SUB_CATEGORY_TO_CATEGORY } from '../types/jobs';
import { getMinAdeptness } from '../constants/jobSkillValues';

export function getEffectiveProficiencies(
  proficiencies: Record<string, number>,
  designJobId: number,
): Record<string, number> {
  const result: Record<string, number> = {};
  for (const subName of Object.keys(SUB_CATEGORY_TO_CATEGORY)) {
    result[subName] = (proficiencies[subName] || 0) + getMinAdeptness(designJobId, subName);
  }
  return result;
}
