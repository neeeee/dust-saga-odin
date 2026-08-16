export interface MovementInput {
    velocityX: number;
    velocityY: number;
    velocityZ: number;
    speed: number;
    direction: number;
}
export declare class Validator {
    static validatePosition(pos: {
        x: number;
        y: number;
        z: number;
    }): boolean;
    static validateRotation(rot: {
        x: number;
        y: number;
        z: number;
        w: number;
    }): boolean;
    static validateMovement(input: MovementInput): boolean;
    static validateHealth(health: number, maxHealth: number): boolean;
    static validateEntityId(id: string): boolean;
    static validatePlayerName(name: string): boolean;
}
