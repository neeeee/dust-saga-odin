"use strict";
/**
 * Per-zone world grid.
 *
 * Each zone owns a flat grid of 8-unit cells (matches SpatialHash default).
 * The grid is anchored at the zone's corner (-size/2, -size/2) so cell
 * indices are always non-negative within the zone bounds. Columns are
 * lettered A–Z (max 26), rows are numbered 1..N.
 *
 *   ┌────┬────┬────┬────┐
 *   │ A1 │ B1 │ C1 │ D1 │   ← row 1 (cellZ = 0)
 *   ├────┼────┼────┼────┤
 *   │ A2 │ B2 │ C2 │ D2 │   ← row 2 (cellZ = 1)
 *   └────┴────┴────┴────┘
 *     ↑    ↑
 *   cellX=0   cellX=1
 *
 * "K10" parses to column K (cellX = 10), row 10 (cellZ = 9). Quests can
 * reference cells with this label, e.g. EXPLORE targetId = "k10".
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.GRID_MAX_COLUMNS = exports.GRID_CELL_SIZE = void 0;
exports.getZoneGridInfo = getZoneGridInfo;
exports.worldToCell = worldToCell;
exports.cellCenter = cellCenter;
exports.cellLabel = cellLabel;
exports.parseCellLabel = parseCellLabel;
exports.isValidCellLabel = isValidCellLabel;
exports.GRID_CELL_SIZE = 8;
exports.GRID_MAX_COLUMNS = 26;
function getZoneGridInfo(zoneSize) {
    const cellsPerAxis = Math.max(1, Math.ceil(zoneSize / exports.GRID_CELL_SIZE));
    return {
        cellSize: exports.GRID_CELL_SIZE,
        columns: Math.min(cellsPerAxis, exports.GRID_MAX_COLUMNS),
        rows: cellsPerAxis,
        originX: -zoneSize / 2,
        originZ: -zoneSize / 2,
    };
}
function worldToCell(x, z, zoneSize) {
    const grid = getZoneGridInfo(zoneSize);
    const cx = Math.floor((x - grid.originX) / grid.cellSize);
    const cz = Math.floor((z - grid.originZ) / grid.cellSize);
    if (cx < 0 || cz < 0 || cx >= grid.columns || cz >= grid.rows)
        return null;
    return { x: cx, z: cz };
}
function cellCenter(cell, zoneSize) {
    const grid = getZoneGridInfo(zoneSize);
    return {
        x: grid.originX + cell.x * grid.cellSize + grid.cellSize / 2,
        z: grid.originZ + cell.z * grid.cellSize + grid.cellSize / 2,
    };
}
function cellLabel(cell) {
    const col = String.fromCharCode('A'.charCodeAt(0) + cell.x);
    return `${col}${cell.z + 1}`;
}
function parseCellLabel(label) {
    const m = /^([A-Za-z])([0-9]+)$/.exec(label.trim());
    if (!m)
        return null;
    const colIdx = m[1].toUpperCase().charCodeAt(0) - 'A'.charCodeAt(0);
    const rowIdx = parseInt(m[2], 10) - 1;
    if (colIdx < 0 || colIdx >= exports.GRID_MAX_COLUMNS || rowIdx < 0)
        return null;
    return { x: colIdx, z: rowIdx };
}
function isValidCellLabel(label) {
    return parseCellLabel(label) !== null;
}
