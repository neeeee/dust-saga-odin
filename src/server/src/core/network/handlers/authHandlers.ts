import { Socket } from 'socket.io';
import {
  Packet, PacketType, PlayerSession,
  JOB_DEFINITIONS, RACE_DATA, createDefaultStatPoints, createDefaultSkillProficiencies, createDefaultSkillAdeptness,
  getDesignJobId, calculateDerivedStats,
  getZoneDefinition, normalizeEquipment, Validator,
} from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.LOGIN, handleLogin);
  registry.set(PacketType.REGISTER, handleRegister);
}

async function handleLogin(ctx: NetworkContext, socket: Socket, data: any): Promise<void> {
  const result = await ctx.auth.login(data.username, data.password);

  if (result.success) {
    ctx.state.socketToPlayer.set(socket.id, result.playerId!);
    ctx.sendToSocket(socket.id, {
      type: PacketType.AUTH_SUCCESS,
      timestamp: Date.now(),
      data: { playerId: result.playerId, username: result.username, token: result.token, level: result.level, role: result.role }
    });
  } else {
    ctx.sendToSocket(socket.id, {
      type: PacketType.AUTH_FAILURE,
      timestamp: Date.now(),
      data: { message: result.error }
    });
  }
}

async function handleRegister(ctx: NetworkContext, socket: Socket, data: any): Promise<void> {
  const result = await ctx.auth.register(data.username, data.email, data.password);

  if (result.success) {
    ctx.state.socketToPlayer.set(socket.id, result.playerId!);
    ctx.sendToSocket(socket.id, {
      type: PacketType.AUTH_SUCCESS,
      timestamp: Date.now(),
      data: { playerId: result.playerId, token: result.token }
    });
  } else {
    ctx.sendToSocket(socket.id, {
      type: PacketType.AUTH_FAILURE,
      timestamp: Date.now(),
      data: { message: result.error }
    });
  }
}
