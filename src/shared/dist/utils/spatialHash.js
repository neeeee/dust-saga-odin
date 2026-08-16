"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SpatialHash = void 0;
class SpatialHash {
    constructor(cellSize = 8) {
        this.cells = new Map();
        this.entryMap = new Map();
        this.cellSize = cellSize;
    }
    insert(id, x, z, data) {
        const entry = { id, x, z, data };
        this.remove(id);
        this.entryMap.set(id, entry);
        const key = this.cellKey(x, z);
        let cell = this.cells.get(key);
        if (!cell) {
            cell = [];
            this.cells.set(key, cell);
        }
        cell.push(entry);
    }
    remove(id) {
        const entry = this.entryMap.get(id);
        if (!entry)
            return;
        this.entryMap.delete(id);
        const key = this.cellKey(entry.x, entry.z);
        const cell = this.cells.get(key);
        if (cell) {
            let writeIdx = 0;
            for (let i = 0; i < cell.length; i++) {
                if (cell[i].id !== id) {
                    cell[writeIdx++] = cell[i];
                }
            }
            cell.length = writeIdx;
            if (cell.length === 0) {
                this.cells.delete(key);
            }
        }
    }
    move(id, x, z) {
        const entry = this.entryMap.get(id);
        if (entry) {
            const oldKey = this.cellKey(entry.x, entry.z);
            const newKey = this.cellKey(x, z);
            if (oldKey === newKey) {
                entry.x = x;
                entry.z = z;
                return;
            }
        }
        this.insert(id, x, z, (this.entryMap.get(id)?.data));
    }
    queryRadius(x, z, radius) {
        const results = [];
        const radiusSq = radius * radius;
        const cellRadius = Math.ceil(radius / this.cellSize) + 1;
        const cx = Math.floor(x / this.cellSize);
        const cz = Math.floor(z / this.cellSize);
        for (let dx = -cellRadius; dx <= cellRadius; dx++) {
            for (let dz = -cellRadius; dz <= cellRadius; dz++) {
                const cell = this.cells.get(`${cx + dx},${cz + dz}`);
                if (!cell)
                    continue;
                for (let i = 0; i < cell.length; i++) {
                    const entry = cell[i];
                    const ddx = entry.x - x;
                    const ddz = entry.z - z;
                    if (ddx * ddx + ddz * ddz <= radiusSq) {
                        results.push(entry);
                    }
                }
            }
        }
        return results;
    }
    queryRadiusIds(x, z, radius) {
        const results = [];
        const radiusSq = radius * radius;
        const cellRadius = Math.ceil(radius / this.cellSize) + 1;
        const cx = Math.floor(x / this.cellSize);
        const cz = Math.floor(z / this.cellSize);
        for (let dx = -cellRadius; dx <= cellRadius; dx++) {
            for (let dz = -cellRadius; dz <= cellRadius; dz++) {
                const cell = this.cells.get(`${cx + dx},${cz + dz}`);
                if (!cell)
                    continue;
                for (let i = 0; i < cell.length; i++) {
                    const entry = cell[i];
                    const ddx = entry.x - x;
                    const ddz = entry.z - z;
                    if (ddx * ddx + ddz * ddz <= radiusSq) {
                        results.push(entry.id);
                    }
                }
            }
        }
        return results;
    }
    get(id) {
        return this.entryMap.get(id);
    }
    has(id) {
        return this.entryMap.has(id);
    }
    get size() {
        return this.entryMap.size;
    }
    clear() {
        this.cells.clear();
        this.entryMap.clear();
    }
    cellKey(x, z) {
        return `${Math.floor(x / this.cellSize)},${Math.floor(z / this.cellSize)}`;
    }
}
exports.SpatialHash = SpatialHash;
