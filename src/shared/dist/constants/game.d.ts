export declare const GAME_CONFIG: {
    readonly TICK_RATE: 30;
    readonly PLAYER_SPEED: 5.5;
    readonly PLAYER_ROTATION_SPEED: 3;
    readonly JUMP_FORCE: 8;
    readonly GRAVITY: 20;
    readonly MAX_HEALTH: 100;
    readonly RESPAWN_TIME: 5000;
    readonly ZONE_SIZE: 100;
    readonly VIEW_DISTANCE: 50;
    readonly INTERPOLATION_DELAY: 100;
    readonly ATTACK_COOLDOWN: 1000;
    readonly AUTO_ATTACK_BASE_COOLDOWN: 3000;
    readonly AUTO_ATTACK_MIN_COOLDOWN: 1000;
    readonly MANUAL_ATTACK_COOLDOWN: 2000;
    readonly MAX_INVENTORY_SLOTS: 64;
    readonly MAX_LEVEL: 60;
    readonly COMBAT_LOG_SIZE: 50;
    readonly MAX_POSITION: 500;
};
export declare const COMBAT_CONFIG: {
    readonly BASE_ATTACK_POWER: 10;
    readonly BASE_DEFENSE: 5;
    readonly BASE_ATTACK_SPEED: 1;
    readonly CRITICAL_CHANCE: 0.1;
    readonly CRITICAL_MULTIPLIER: 2;
    readonly ATTACK_RANGE: 2.5;
    readonly RANGED_ATTACK_RANGE: 15;
    readonly MANUAL_ATTACK_RANGE: 3.5;
    readonly MANUAL_ATTACK_CONE_ANGLE: number;
    readonly MANUAL_ATTACK_MAX_TARGETS: 5;
    readonly MANUAL_ATTACK_FALLOFF: 0.8;
    readonly MANUAL_ATTACK_ARROW_HALF_WIDTH: 0.9;
    readonly SKILL_COOLDOWN: 3000;
    readonly DAMAGE_REDUCTION_PER_DEFENSE: 0.02;
    readonly MIN_DAMAGE: 1;
};
export declare const REGEN_CONFIG: {
    readonly TICK_INTERVAL_MS: 10000;
    readonly LP_DIVISOR: 80;
    readonly LP_STA_DIVISOR: 6;
    readonly MP_DIVISOR: 60;
    readonly MP_SPI_DIVISOR: 6;
    readonly OUT_OF_COMBAT_DELAY_MS: 7000;
    readonly IN_COMBAT_LP_MULTIPLIER: 0.25;
    readonly IN_COMBAT_MP_MULTIPLIER: 0.1;
};
export declare const REST_REGEN_CONFIG: {
    readonly HP_DIVISOR: 10;
    readonly MP_DIVISOR: 10;
    readonly HP_STA_DIVISOR: 1;
    readonly MP_SPI_DIVISOR: 1;
    readonly RAMP_TICK_0: 0.5;
    readonly RAMP_TICK_1: 0.75;
};
export declare const NETWORK_CONFIG: {
    readonly HEARTBEAT_INTERVAL: 30000;
    readonly CONNECTION_TIMEOUT: 10000;
    readonly MAX_RECONNECT_ATTEMPTS: 5;
    readonly RECONNECT_DELAY: 2000;
    readonly MOVEMENT_SEND_RATE: 50;
};
export declare const PROFICIENCY_CONFIG: {
    readonly TIER_1_RATIO: 0.33;
    readonly TIER_1_GAIN_MIN: 0.7;
    readonly TIER_1_GAIN_MAX: 0.8;
    readonly TIER_2_RATIO: 0.66;
    readonly TIER_2_GAIN: 0.04;
    readonly TIER_3_GAIN: 0.01;
    readonly INSTANT_CAST_MULTIPLIER: 0.5;
    readonly CAST_TIME_THRESHOLD: 0.1;
};
export declare const WORLD_CONFIG: {
    readonly CHUNK_SIZE: 32;
    readonly MAX_ENTITIES_PER_ZONE: 100;
    readonly SPAWN_RADIUS: 10;
    readonly DESPAWN_DISTANCE: 100;
};
