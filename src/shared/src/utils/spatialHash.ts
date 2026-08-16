export interface SpatialEntry<T> {
  id: string;
  x: number;
  z: number;
  data: T;
}

export class SpatialHash<T> {
  readonly cellSize: number;
  private cells: Map<string, SpatialEntry<T>[]> = new Map();
  private entryMap: Map<string, SpatialEntry<T>> = new Map();

  constructor(cellSize: number = 8) {
    this.cellSize = cellSize;
  }

  insert(id: string, x: number, z: number, data: T): void {
    const entry: SpatialEntry<T> = { id, x, z, data };
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

  remove(id: string): void {
    const entry = this.entryMap.get(id);
    if (!entry) return;
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

  move(id: string, x: number, z: number): void {
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
    this.insert(id, x, z, (this.entryMap.get(id)?.data) as T);
  }

  queryRadius(x: number, z: number, radius: number): SpatialEntry<T>[] {
    const results: SpatialEntry<T>[] = [];
    const radiusSq = radius * radius;
    const cellRadius = Math.ceil(radius / this.cellSize) + 1;
    const cx = Math.floor(x / this.cellSize);
    const cz = Math.floor(z / this.cellSize);

    for (let dx = -cellRadius; dx <= cellRadius; dx++) {
      for (let dz = -cellRadius; dz <= cellRadius; dz++) {
        const cell = this.cells.get(`${cx + dx},${cz + dz}`);
        if (!cell) continue;
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

  queryRadiusIds(x: number, z: number, radius: number): string[] {
    const results: string[] = [];
    const radiusSq = radius * radius;
    const cellRadius = Math.ceil(radius / this.cellSize) + 1;
    const cx = Math.floor(x / this.cellSize);
    const cz = Math.floor(z / this.cellSize);

    for (let dx = -cellRadius; dx <= cellRadius; dx++) {
      for (let dz = -cellRadius; dz <= cellRadius; dz++) {
        const cell = this.cells.get(`${cx + dx},${cz + dz}`);
        if (!cell) continue;
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

  get(id: string): SpatialEntry<T> | undefined {
    return this.entryMap.get(id);
  }

  has(id: string): boolean {
    return this.entryMap.has(id);
  }

  get size(): number {
    return this.entryMap.size;
  }

  clear(): void {
    this.cells.clear();
    this.entryMap.clear();
  }

  private cellKey(x: number, z: number): string {
    return `${Math.floor(x / this.cellSize)},${Math.floor(z / this.cellSize)}`;
  }
}
