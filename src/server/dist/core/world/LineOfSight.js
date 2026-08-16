"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.hasLineOfSight = hasLineOfSight;
const shared_1 = require("@dust-saga/shared");
const OBSTACLE_RADIUS = {
    house: 3.0,
    rock: 1.5,
    tree: 0.6,
    bush: 0.3,
};
function hasLineOfSight(zoneId, from, to) {
    const zone = (0, shared_1.getZoneDefinition)(zoneId);
    if (!zone)
        return true;
    const dx = to.x - from.x;
    const dz = to.z - from.z;
    const distSq = dx * dx + dz * dz;
    if (distSq < 1)
        return true;
    const dist = Math.sqrt(distSq);
    const dirX = dx / dist;
    const dirZ = dz / dist;
    for (const group of zone.environmentObjects) {
        const radius = OBSTACLE_RADIUS[group.type] ?? 1.0;
        const rSq = radius * radius;
        for (const obj of group.positions) {
            const fx = obj.x - from.x;
            const fz = obj.z - from.z;
            const projection = fx * dirX + fz * dirZ;
            if (projection < 0 || projection > dist)
                continue;
            const perpX = fx - projection * dirX;
            const perpZ = fz - projection * dirZ;
            const perpDistSq = perpX * perpX + perpZ * perpZ;
            if (perpDistSq < rSq)
                return false;
        }
    }
    return true;
}
