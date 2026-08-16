"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MovementSystem = void 0;
const EntityManager_1 = require("../EntityManager");
const shared_1 = require("@dust-saga/shared");
class MovementSystem extends EntityManager_1.System {
    constructor(entityManager) {
        super(entityManager);
    }
    update(deltaTime) {
        const entities = this.entityManager.getEntitiesWithComponent('movement');
        entities.forEach(entity => {
            const movement = this.entityManager.getComponent(entity.id, 'movement');
            const position = this.entityManager.getComponent(entity.id, 'position');
            if (movement && position) {
                const speed = Math.min(movement.data.speed, shared_1.GAME_CONFIG.PLAYER_SPEED * 2);
                position.data.x += movement.data.velocityX * deltaTime * speed;
                position.data.y += movement.data.velocityY * deltaTime;
                position.data.z += movement.data.velocityZ * deltaTime * speed;
            }
        });
    }
}
exports.MovementSystem = MovementSystem;
