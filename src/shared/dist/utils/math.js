"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Quaternion = exports.Vector3 = void 0;
exports.lerp = lerp;
exports.clamp = clamp;
exports.distanceSquared = distanceSquared;
exports.distance2D = distance2D;
exports.moveToward = moveToward;
class Vector3 {
    constructor(x = 0, y = 0, z = 0) {
        this.x = x;
        this.y = y;
        this.z = z;
    }
    add(other) {
        return new Vector3(this.x + other.x, this.y + other.y, this.z + other.z);
    }
    subtract(other) {
        return new Vector3(this.x - other.x, this.y - other.y, this.z - other.z);
    }
    multiply(scalar) {
        return new Vector3(this.x * scalar, this.y * scalar, this.z * scalar);
    }
    distanceTo(other) {
        const dx = this.x - other.x;
        const dy = this.y - other.y;
        const dz = this.z - other.z;
        return Math.sqrt(dx * dx + dy * dy + dz * dz);
    }
    length() {
        return Math.sqrt(this.x * this.x + this.y * this.y + this.z * this.z);
    }
    normalize() {
        const len = this.length();
        if (len === 0)
            return new Vector3(0, 0, 0);
        return new Vector3(this.x / len, this.y / len, this.z / len);
    }
    clone() {
        return new Vector3(this.x, this.y, this.z);
    }
    static fromObject(obj) {
        return new Vector3(obj.x, obj.y, obj.z);
    }
    toObject() {
        return { x: this.x, y: this.y, z: this.z };
    }
}
exports.Vector3 = Vector3;
class Quaternion {
    constructor(x = 0, y = 0, z = 0, w = 1) {
        this.x = x;
        this.y = y;
        this.z = z;
        this.w = w;
    }
    static fromEuler(pitch, yaw, roll) {
        const cy = Math.cos(yaw * 0.5);
        const sy = Math.sin(yaw * 0.5);
        const cp = Math.cos(pitch * 0.5);
        const sp = Math.sin(pitch * 0.5);
        const cr = Math.cos(roll * 0.5);
        const sr = Math.sin(roll * 0.5);
        return new Quaternion(sr * cp * cy - cr * sp * sy, cr * sp * cy + sr * cp * sy, cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy);
    }
    clone() {
        return new Quaternion(this.x, this.y, this.z, this.w);
    }
    toObject() {
        return { x: this.x, y: this.y, z: this.z, w: this.w };
    }
}
exports.Quaternion = Quaternion;
function lerp(start, end, t) {
    return start + (end - start) * t;
}
function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}
function distanceSquared(pos1, pos2) {
    const dx = pos1.x - pos2.x;
    const dy = pos1.y - pos2.y;
    const dz = pos1.z - pos2.z;
    return dx * dx + dy * dy + dz * dz;
}
function distance2D(a, b) {
    const dx = a.x - b.x;
    const dz = a.z - b.z;
    return Math.sqrt(dx * dx + dz * dz);
}
function moveToward(entity, target, speed) {
    const dx = target.x - entity.position.x;
    const dz = target.z - entity.position.z;
    const dist = Math.sqrt(dx * dx + dz * dz);
    if (dist > 0.01) {
        entity.position.x += (dx / dist) * speed;
        entity.position.z += (dz / dist) * speed;
        entity.rotation = Math.atan2(dx, dz);
    }
}
