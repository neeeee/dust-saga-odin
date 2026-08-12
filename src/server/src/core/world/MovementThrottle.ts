/** Per-character movement-broadcast throttle timestamps (ephemeral, no persistence). */
export class MovementThrottle {
  private lastMoveBroadcast = new Map<string, number>();

  get(characterId: string): number {
    return this.lastMoveBroadcast.get(characterId) || 0;
  }

  set(characterId: string, time: number): void {
    this.lastMoveBroadcast.set(characterId, time);
  }

  clear(characterId: string): void {
    this.lastMoveBroadcast.delete(characterId);
  }
}
