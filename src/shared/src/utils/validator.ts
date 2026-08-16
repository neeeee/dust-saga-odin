import { GAME_CONFIG } from '../constants/game';

export interface MovementInput {
  velocityX: number;
  velocityY: number;
  velocityZ: number;
  speed: number;
  direction: number;
}

export class Validator {
  static validatePosition(pos: { x: number; y: number; z: number }): boolean {
    const MAX = GAME_CONFIG.MAX_POSITION;
    return (
      typeof pos.x === 'number' &&
      typeof pos.y === 'number' &&
      typeof pos.z === 'number' &&
      !isNaN(pos.x) &&
      !isNaN(pos.y) &&
      !isNaN(pos.z) &&
      isFinite(pos.x) &&
      isFinite(pos.y) &&
      isFinite(pos.z) &&
      Math.abs(pos.x) <= MAX &&
      Math.abs(pos.y) <= MAX &&
      Math.abs(pos.z) <= MAX
    );
  }

  static validateRotation(rot: { x: number; y: number; z: number; w: number }): boolean {
    const length = Math.sqrt(rot.x * rot.x + rot.y * rot.y + rot.z * rot.z + rot.w * rot.w);
    return (
      typeof rot.x === 'number' &&
      typeof rot.y === 'number' &&
      typeof rot.z === 'number' &&
      typeof rot.w === 'number' &&
      !isNaN(rot.x) &&
      !isNaN(rot.y) &&
      !isNaN(rot.z) &&
      !isNaN(rot.w) &&
      Math.abs(length - 1.0) < 0.01
    );
  }

  static validateMovement(input: MovementInput): boolean {
    return (
      typeof input.speed === 'number' &&
      input.speed >= 0 &&
      input.speed <= GAME_CONFIG.PLAYER_SPEED * 2 &&
      typeof input.direction === 'number' &&
      !isNaN(input.direction) &&
      Math.abs(input.direction) <= Math.PI * 2 &&
      typeof input.velocityX === 'number' &&
      typeof input.velocityY === 'number' &&
      typeof input.velocityZ === 'number' &&
      !isNaN(input.velocityX) &&
      !isNaN(input.velocityY) &&
      !isNaN(input.velocityZ)
    );
  }

  static validateHealth(health: number, maxHealth: number): boolean {
    return (
      typeof health === 'number' &&
      typeof maxHealth === 'number' &&
      health >= 0 &&
      health <= maxHealth &&
      maxHealth > 0
    );
  }

  static validateEntityId(id: string): boolean {
    return typeof id === 'string' && id.length > 0 && id.length <= 100;
  }

  static validatePlayerName(name: string): boolean {
    return (
      typeof name === 'string' &&
      name.length >= 3 &&
      name.length <= 20 &&
      /^[a-zA-Z0-9_]+$/.test(name)
    );
  }
}