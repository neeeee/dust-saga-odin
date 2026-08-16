export declare class Vector3 {
    x: number;
    y: number;
    z: number;
    constructor(x?: number, y?: number, z?: number);
    add(other: Vector3): Vector3;
    subtract(other: Vector3): Vector3;
    multiply(scalar: number): Vector3;
    distanceTo(other: Vector3): number;
    length(): number;
    normalize(): Vector3;
    clone(): Vector3;
    static fromObject(obj: {
        x: number;
        y: number;
        z: number;
    }): Vector3;
    toObject(): {
        x: number;
        y: number;
        z: number;
    };
}
export declare class Quaternion {
    x: number;
    y: number;
    z: number;
    w: number;
    constructor(x?: number, y?: number, z?: number, w?: number);
    static fromEuler(pitch: number, yaw: number, roll: number): Quaternion;
    clone(): Quaternion;
    toObject(): {
        x: number;
        y: number;
        z: number;
        w: number;
    };
}
export declare function lerp(start: number, end: number, t: number): number;
export declare function clamp(value: number, min: number, max: number): number;
export declare function distanceSquared(pos1: {
    x: number;
    y: number;
    z: number;
}, pos2: {
    x: number;
    y: number;
    z: number;
}): number;
export declare function distance2D(a: {
    x: number;
    z: number;
}, b: {
    x: number;
    z: number;
}): number;
export declare function moveToward(entity: {
    position: {
        x: number;
        y: number;
        z: number;
    };
    rotation: number;
}, target: {
    x: number;
    y: number;
    z: number;
}, speed: number): void;
