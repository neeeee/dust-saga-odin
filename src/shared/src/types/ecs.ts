export interface Entity {
  id: string;
  components: Map<string, Component>;
}

export interface Component {
  type: string;
  data: any;
}

export interface PositionComponent extends Component {
  type: 'position';
  data: { x: number; y: number; z: number };
}

export interface RotationComponent extends Component {
  type: 'rotation';
  data: { x: number; y: number; z: number; w: number };
}

export interface MovementComponent extends Component {
  type: 'movement';
  data: { velocityX: number; velocityY: number; velocityZ: number; speed: number; direction: number };
}

export interface HealthComponent extends Component {
  type: 'health';
  data: { current: number; max: number };
}

export interface CombatComponent extends Component {
  type: 'combat';
  data: { attackPower: number; defense: number; attackSpeed: number };
}

export interface CharacterComponent extends Component {
  type: 'character';
  data: { name: string; level: number; class: string; experience: number };
}

export interface NetworkComponent extends Component {
  type: 'network';
  data: { socketId: string; lastUpdate: number };
}