import { EntityManager, System } from '../EntityManager';
import { GAME_CONFIG } from '@dust-saga/shared';

export class MovementSystem extends System {
  constructor(entityManager: EntityManager) {
    super(entityManager);
  }

  update(deltaTime: number): void {
    const entities = this.entityManager.getEntitiesWithComponent('movement');

    entities.forEach(entity => {
      const movement = this.entityManager.getComponent(entity.id, 'movement');
      const position = this.entityManager.getComponent(entity.id, 'position');

      if (movement && position) {
        const speed = Math.min(movement.data.speed, GAME_CONFIG.PLAYER_SPEED * 2);
        position.data.x += movement.data.velocityX * deltaTime * speed;
        position.data.y += movement.data.velocityY * deltaTime;
        position.data.z += movement.data.velocityZ * deltaTime * speed;
      }
    });
  }
}
