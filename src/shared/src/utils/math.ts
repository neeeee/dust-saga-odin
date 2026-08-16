export class Vector3 {
  constructor(
    public x: number = 0,
    public y: number = 0,
    public z: number = 0
  ) {}

  add(other: Vector3): Vector3 {
    return new Vector3(this.x + other.x, this.y + other.y, this.z + other.z);
  }

  subtract(other: Vector3): Vector3 {
    return new Vector3(this.x - other.x, this.y - other.y, this.z - other.z);
  }

  multiply(scalar: number): Vector3 {
    return new Vector3(this.x * scalar, this.y * scalar, this.z * scalar);
  }

  distanceTo(other: Vector3): number {
    const dx = this.x - other.x;
    const dy = this.y - other.y;
    const dz = this.z - other.z;
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  length(): number {
    return Math.sqrt(this.x * this.x + this.y * this.y + this.z * this.z);
  }

  normalize(): Vector3 {
    const len = this.length();
    if (len === 0) return new Vector3(0, 0, 0);
    return new Vector3(this.x / len, this.y / len, this.z / len);
  }

  clone(): Vector3 {
    return new Vector3(this.x, this.y, this.z);
  }

  static fromObject(obj: { x: number; y: number; z: number }): Vector3 {
    return new Vector3(obj.x, obj.y, obj.z);
  }

  toObject(): { x: number; y: number; z: number } {
    return { x: this.x, y: this.y, z: this.z };
  }
}

export class Quaternion {
  constructor(
    public x: number = 0,
    public y: number = 0,
    public z: number = 0,
    public w: number = 1
  ) {}

  static fromEuler(pitch: number, yaw: number, roll: number): Quaternion {
    const cy = Math.cos(yaw * 0.5);
    const sy = Math.sin(yaw * 0.5);
    const cp = Math.cos(pitch * 0.5);
    const sp = Math.sin(pitch * 0.5);
    const cr = Math.cos(roll * 0.5);
    const sr = Math.sin(roll * 0.5);

    return new Quaternion(
      sr * cp * cy - cr * sp * sy,
      cr * sp * cy + sr * cp * sy,
      cr * cp * sy - sr * sp * cy,
      cr * cp * cy + sr * sp * sy
    );
  }

  clone(): Quaternion {
    return new Quaternion(this.x, this.y, this.z, this.w);
  }

  toObject(): { x: number; y: number; z: number; w: number } {
    return { x: this.x, y: this.y, z: this.z, w: this.w };
  }
}

export function lerp(start: number, end: number, t: number): number {
  return start + (end - start) * t;
}

export function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export function distanceSquared(pos1: { x: number; y: number; z: number }, pos2: { x: number; y: number; z: number }): number {
  const dx = pos1.x - pos2.x;
  const dy = pos1.y - pos2.y;
  const dz = pos1.z - pos2.z;
  return dx * dx + dy * dy + dz * dz;
}

export function distance2D(a: { x: number; z: number }, b: { x: number; z: number }): number {
  const dx = a.x - b.x;
  const dz = a.z - b.z;
  return Math.sqrt(dx * dx + dz * dz);
}

export function moveToward(
  entity: { position: { x: number; y: number; z: number }; rotation: number },
  target: { x: number; y: number; z: number },
  speed: number,
): void {
  const dx = target.x - entity.position.x;
  const dz = target.z - entity.position.z;
  const dist = Math.sqrt(dx * dx + dz * dz);
  if (dist > 0.01) {
    entity.position.x += (dx / dist) * speed;
    entity.position.z += (dz / dist) * speed;
    entity.rotation = Math.atan2(dx, dz);
  }
}