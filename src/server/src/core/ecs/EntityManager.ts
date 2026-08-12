import { Entity, Component } from '@dust-saga/shared';

export class EntityManager {
  private entities: Map<string, Entity> = new Map();
  private nextId: number = 1;

  createEntity(components?: Map<string, Component>): Entity {
    const id = `entity_${this.nextId++}`;
    const entity: Entity = {
      id,
      components: components || new Map()
    };
    this.entities.set(id, entity);
    return entity;
  }

  getEntity(id: string): Entity | undefined {
    return this.entities.get(id);
  }

  removeEntity(id: string): void {
    this.entities.delete(id);
  }

  getAllEntities(): Entity[] {
    return Array.from(this.entities.values());
  }

  addComponent(entityId: string, component: Component): void {
    const entity = this.entities.get(entityId);
    if (entity) {
      entity.components.set(component.type, component);
    }
  }

  removeComponent(entityId: string, componentType: string): void {
    const entity = this.entities.get(entityId);
    if (entity) {
      entity.components.delete(componentType);
    }
  }

  getComponent<T extends Component>(entityId: string, componentType: string): T | undefined {
    const entity = this.entities.get(entityId);
    if (!entity) return undefined;
    return entity.components.get(componentType) as T;
  }

  getEntitiesWithComponent(componentType: string): Entity[] {
    return Array.from(this.entities.values()).filter(entity =>
      entity.components.has(componentType)
    );
  }
}

export class System {
  protected entityManager: EntityManager;

  constructor(entityManager: EntityManager) {
    this.entityManager = entityManager;
  }

  update(deltaTime: number): void {
    // To be implemented by specific systems
  }
}

export class MovementSystem extends System {
  update(deltaTime: number): void {
    const entities = this.entityManager.getEntitiesWithComponent('movement');

    entities.forEach(entity => {
      const movement = this.entityManager.getComponent(entity.id, 'movement');
      const position = this.entityManager.getComponent(entity.id, 'position');

      if (movement && position) {
        position.data.x += movement.data.velocityX * deltaTime;
        position.data.y += movement.data.velocityY * deltaTime;
        position.data.z += movement.data.velocityZ * deltaTime;
      }
    });
  }
}

export class CombatSystem extends System {
  update(deltaTime: number): void {
    const combatEntities = this.entityManager.getEntitiesWithComponent('combat');

    combatEntities.forEach(entity => {
      const combat = this.entityManager.getComponent(entity.id, 'combat');
      const health = this.entityManager.getComponent(entity.id, 'health');

      if (combat && health) {
        // Process combat logic
        if (health.data.current <= 0) {
          // Handle death
        }
      }
    });
  }
}