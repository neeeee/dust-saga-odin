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
export declare const GRID_CELL_SIZE = 8;
export declare const GRID_MAX_COLUMNS = 26;
export interface GridCell {
    x: number;
    z: number;
}
export interface ZoneGridInfo {
    cellSize: number;
    columns: number;
    rows: number;
    originX: number;
    originZ: number;
}
export declare function getZoneGridInfo(zoneSize: number): ZoneGridInfo;
export declare function worldToCell(x: number, z: number, zoneSize: number): GridCell | null;
export declare function cellCenter(cell: GridCell, zoneSize: number): {
    x: number;
    z: number;
};
export declare function cellLabel(cell: GridCell): string;
export declare function parseCellLabel(label: string): GridCell | null;
export declare function isValidCellLabel(label: string): boolean;
