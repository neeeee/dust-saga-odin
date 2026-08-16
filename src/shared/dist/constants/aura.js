"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GLOOM_RECOIL_REDUCTION_ADEPTNESS = void 0;
exports.getGloomRecoilRate = getGloomRecoilRate;
exports.GLOOM_RECOIL_REDUCTION_ADEPTNESS = 71;
function getGloomRecoilRate(darknessAdeptness) {
    return darknessAdeptness >= exports.GLOOM_RECOIL_REDUCTION_ADEPTNESS ? 0.10 : 0.50;
}
