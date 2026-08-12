export const GLOOM_RECOIL_REDUCTION_ADEPTNESS = 71;

export function getGloomRecoilRate(darknessAdeptness: number): number {
  return darknessAdeptness >= GLOOM_RECOIL_REDUCTION_ADEPTNESS ? 0.10 : 0.50;
}
