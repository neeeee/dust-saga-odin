export interface SpatialEntry<T> {
    id: string;
    x: number;
    z: number;
    data: T;
}
export declare class SpatialHash<T> {
    readonly cellSize: number;
    private cells;
    private entryMap;
    constructor(cellSize?: number);
    insert(id: string, x: number, z: number, data: T): void;
    remove(id: string): void;
    move(id: string, x: number, z: number): void;
    queryRadius(x: number, z: number, radius: number): SpatialEntry<T>[];
    queryRadiusIds(x: number, z: number, radius: number): string[];
    get(id: string): SpatialEntry<T> | undefined;
    has(id: string): boolean;
    get size(): number;
    clear(): void;
    private cellKey;
}
