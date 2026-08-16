"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MovementThrottle = void 0;
/** Per-character movement-broadcast throttle timestamps (ephemeral, no persistence). */
class MovementThrottle {
    constructor() {
        this.lastMoveBroadcast = new Map();
    }
    get(characterId) {
        return this.lastMoveBroadcast.get(characterId) || 0;
    }
    set(characterId, time) {
        this.lastMoveBroadcast.set(characterId, time);
    }
    clear(characterId) {
        this.lastMoveBroadcast.delete(characterId);
    }
}
exports.MovementThrottle = MovementThrottle;
