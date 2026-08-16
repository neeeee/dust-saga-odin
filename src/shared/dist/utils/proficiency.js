"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getEffectiveProficiencies = getEffectiveProficiencies;
const jobs_1 = require("../types/jobs");
const jobSkillValues_1 = require("../constants/jobSkillValues");
function getEffectiveProficiencies(proficiencies, designJobId) {
    const result = {};
    for (const subName of Object.keys(jobs_1.SUB_CATEGORY_TO_CATEGORY)) {
        result[subName] = (proficiencies[subName] || 0) + (0, jobSkillValues_1.getMinAdeptness)(designJobId, subName);
    }
    return result;
}
