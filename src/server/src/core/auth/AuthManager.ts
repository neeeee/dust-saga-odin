import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { DatabaseManager } from '../database/DatabaseManager';
import { AccountRole } from '@dust-saga/shared';
import { createDefaultStatPoints, createDefaultSkillProficiencies, createDefaultSkillAdeptness, getDesignJobId, DEFAULT_EQUIPMENT } from '@dust-saga/shared';

const JWT_SECRET = process.env.JWT_SECRET || 'dust-saga-secret-key-change-in-production';
const JWT_EXPIRY = '24h';

export interface AuthToken {
  playerId: string;
  username: string;
}

export interface MockCharacter {
  id: string;
  name: string;
  class: string;
  race: string;
  job_id: string;
  level: number;
  position_x: number;
  position_y: number;
  position_z: number;
  zone_id: string;
  stat_points: string;
  unspent_stat_points: number;
  unspent_skill_points: number;
  skill_proficiencies: string;
  skill_adeptness: string;
  experience: number;
  nation?: string | null;
  last_safe_zone_id?: string;
  inventory?: string;
  equipment?: string;
  gold?: number;
  racial_passive?: string | null;
  character_quests?: string;
  character_recipes?: string;
  character_unlocked_zones?: string;
}

export class AuthManager {
  private static instance: AuthManager;
  private db: DatabaseManager;

  private mockPlayers: Map<string, { id: string; username: string }> = new Map();
  private mockCharacters: Map<string, MockCharacter[]> = new Map();
  private mockPlayerRoles: Map<string, AccountRole> = new Map();

  private constructor() {
    this.db = DatabaseManager.getInstance();
  }

  static getInstance(): AuthManager {
    if (!AuthManager.instance) {
      AuthManager.instance = new AuthManager();
    }
    return AuthManager.instance;
  }

  async register(username: string, email: string, password: string): Promise<{ success: boolean; playerId?: string; token?: string; error?: string }> {
    if (!this.db.isPostgresConnected()) {
      let player = this.mockPlayers.get(username);
      if (!player) {
        player = { id: uuidv4(), username };
        this.mockPlayers.set(username, player);
        this.mockCharacters.set(player.id, []);
      }
      return {
        success: true,
        playerId: player.id,
        token: this.generateToken(player.id, username)
      };
    }

    try {
      const existing = await this.db.postgres!.query(
        'SELECT id FROM players WHERE username = $1 OR email = $2',
        [username, email]
      );

      if (existing.rows.length > 0) {
        return { success: false, error: 'Username or email already exists' };
      }

      const passwordHash = await bcrypt.hash(password, 10);
      const result = await this.db.postgres!.query(
        'INSERT INTO players (username, email, password_hash) VALUES ($1, $2, $3) RETURNING id, username',
        [username, email, passwordHash]
      );

      const player = result.rows[0];
      return {
        success: true,
        playerId: player.id,
        token: this.generateToken(player.id, player.username)
      };
    } catch (error) {
      console.error('Registration error:', error);
      return { success: false, error: 'Registration failed' };
    }
  }

  async login(username: string, password: string): Promise<{ success: boolean; playerId?: string; username?: string; token?: string; level?: number; role?: AccountRole; error?: string }> {
    if (!this.db.isPostgresConnected()) {
      let player = this.mockPlayers.get(username);
      if (!player) {
        player = { id: uuidv4(), username };
        this.mockPlayers.set(username, player);
        this.mockCharacters.set(player.id, []);
        this.mockPlayerRoles.set(player.id, AccountRole.PLAYER);
      }
      const role = this.mockPlayerRoles.get(player.id) || AccountRole.PLAYER;
      return {
        success: true,
        playerId: player.id,
        username,
        token: this.generateToken(player.id, username),
        level: 1,
        role
      };
    }

    try {
      const result = await this.db.postgres!.query(
        'SELECT id, username, password_hash, level, role FROM players WHERE username = $1',
        [username]
      );

      if (result.rows.length === 0) {
        return { success: false, error: 'Invalid username or password' };
      }

      const player = result.rows[0];
      const validPassword = await bcrypt.compare(password, player.password_hash);

      if (!validPassword) {
        return { success: false, error: 'Invalid username or password' };
      }

      await this.db.postgres!.query(
        'UPDATE players SET last_login = NOW() WHERE id = $1',
        [player.id]
      );

      const role = this.normalizeRole(player.role);

      return {
        success: true,
        playerId: player.id,
        username: player.username,
        token: this.generateToken(player.id, player.username),
        level: player.level,
        role
      };
    } catch (error) {
      console.error('Login error:', error);
      return { success: false, error: 'Login failed' };
    }
  }

  async getAccountRole(playerId: string): Promise<AccountRole> {
    if (!this.db.isPostgresConnected()) {
      return this.mockPlayerRoles.get(playerId) || AccountRole.PLAYER;
    }
    try {
      const result = await this.db.postgres!.query('SELECT role FROM players WHERE id = $1', [playerId]);
      if (result.rows.length === 0) return AccountRole.PLAYER;
      return this.normalizeRole(result.rows[0].role);
    } catch (error) {
      console.error('Get account role error:', error);
      return AccountRole.PLAYER;
    }
  }

  async setAccountRole(playerId: string, role: AccountRole): Promise<boolean> {
    if (!this.db.isPostgresConnected()) {
      this.mockPlayerRoles.set(playerId, role);
      return true;
    }
    try {
      const result = await this.db.postgres!.query(
        'UPDATE players SET role = $1 WHERE id = $2',
        [role, playerId]
      );
      return (result.rowCount ?? 0) > 0;
    } catch (error) {
      console.error('Set account role error:', error);
      return false;
    }
  }

  async getAccountIdByUsername(username: string): Promise<string | null> {
    if (!this.db.isPostgresConnected()) {
      for (const player of this.mockPlayers.values()) {
        if (player.username.toLowerCase() === username.toLowerCase()) return player.id;
      }
      return null;
    }
    try {
      const result = await this.db.postgres!.query('SELECT id FROM players WHERE username = $1', [username]);
      return result.rows.length > 0 ? result.rows[0].id : null;
    } catch (error) {
      console.error('Get account id error:', error);
      return null;
    }
  }

  private normalizeRole(raw: unknown): AccountRole {
    if (typeof raw !== 'string') return AccountRole.PLAYER;
    return (Object.values(AccountRole) as string[]).includes(raw) ? (raw as AccountRole) : AccountRole.PLAYER;
  }

  verifyToken(token: string): AuthToken | null {
    try {
      return jwt.verify(token, JWT_SECRET) as AuthToken;
    } catch {
      return null;
    }
  }

  async getCharacters(playerId: string): Promise<MockCharacter[]> {
    if (!this.db.isPostgresConnected()) {
      return this.mockCharacters.get(playerId) || [];
    }

    try {
      const result = await this.db.postgres!.query(
        'SELECT id, name, class, race, racial_passive, job_id, level, position_x, position_y, position_z, zone_id, stat_points, unspent_stat_points, unspent_skill_points, skill_proficiencies, skill_adeptness, experience, nation, last_safe_zone_id, inventory, equipment, gold, character_quests, character_recipes, character_unlocked_zones FROM characters WHERE player_id = $1',
        [playerId]
      );
      return result.rows;
    } catch (error) {
      console.error('Get characters error:', error);
      return [];
    }
  }

  async createCharacter(
    playerId: string,
    name: string,
    race: string,
    jobId: string,
    racialPassive?: string
  ): Promise<{ success: boolean; characterId?: string; error?: string }> {
    if (!this.db.isPostgresConnected()) {
      const characters = this.mockCharacters.get(playerId) || [];
      if (characters.find(c => c.name === name)) {
        return { success: false, error: 'Character name already exists' };
      }
      const defaultStats = createDefaultStatPoints();
      const defaultSkills = createDefaultSkillProficiencies();
      const defaultAdeptness = createDefaultSkillAdeptness(getDesignJobId(jobId));
      const newChar: MockCharacter = {
        id: uuidv4(),
        name,
        class: jobId,
        race,
        job_id: jobId,
        level: 1,
        position_x: 0,
        position_y: 0,
        position_z: 0,
        zone_id: 'starter_zone',
        stat_points: JSON.stringify(defaultStats),
        unspent_stat_points: 0,
        unspent_skill_points: 0,
        skill_proficiencies: JSON.stringify(defaultSkills),
        skill_adeptness: JSON.stringify(defaultAdeptness),
        experience: 0,
        racial_passive: racialPassive || null,
      };
      characters.push(newChar);
      this.mockCharacters.set(playerId, characters);
      return { success: true, characterId: newChar.id };
    }

    try {
      const existing = await this.db.postgres!.query(
        'SELECT id FROM characters WHERE player_id = $1 AND name = $2',
        [playerId, name]
      );

      if (existing.rows.length > 0) {
        return { success: false, error: 'Character name already exists' };
      }

      const defaultStats = createDefaultStatPoints();
      const defaultSkills = createDefaultSkillProficiencies();
      const defaultAdeptness = createDefaultSkillAdeptness(getDesignJobId(jobId));
      const result = await this.db.postgres!.query(
        `INSERT INTO characters (player_id, name, class, race, racial_passive, job_id, level, position_x, position_y, position_z, zone_id, stat_points, unspent_stat_points, unspent_skill_points, skill_proficiencies, skill_adeptness)
         VALUES ($1, $2, $3, $4, $5, $6, 1, 0, 0, 0, $7, $8, 0, 0, $9, $10) RETURNING id`,
        [playerId, name, jobId, race, racialPassive || null, jobId, 'starter_zone', JSON.stringify(defaultStats), JSON.stringify(defaultSkills), JSON.stringify(defaultAdeptness)]
      );

      return { success: true, characterId: result.rows[0].id };
    } catch (error) {
      console.error('Create character error:', error);
      return { success: false, error: 'Failed to create character' };
    }
  }

  async deleteCharacter(playerId: string, characterId: string): Promise<boolean> {
    if (!this.db.isPostgresConnected()) {
      const characters = this.mockCharacters.get(playerId);
      if (characters) {
        const idx = characters.findIndex(c => c.id === characterId);
        if (idx >= 0) characters.splice(idx, 1);
      }
      return true;
    }

    try {
      await this.db.postgres!.query(
        'DELETE FROM characters WHERE id = $1 AND player_id = $2',
        [characterId, playerId]
      );
      return true;
    } catch (error) {
      console.error('Delete character error:', error);
      return false;
    }
  }

  async saveCharacter(characterId: string, data: {
    level: number;
    experience: number;
    position: { x: number; y: number; z: number };
    zoneId: string;
    statPoints: any;
    unspentStatPoints: number;
    unspentSkillPoints: number;
    skillProficiencies: any;
    skillAdeptness: any;
    jobId: string;
    nation?: string | null;
    lastSafeZoneId?: string;
    inventory?: any;
    equipment?: any;
    gold?: number;
    quests?: any;
    recipes?: any;
    unlockedZones?: any;
  }): Promise<void> {
    if (!this.db.isPostgresConnected()) {
      for (const [, chars] of this.mockCharacters) {
        const ch = chars.find(c => c.id === characterId);
        if (ch) {
          ch.level = data.level;
          ch.job_id = data.jobId;
          ch.position_x = data.position.x;
          ch.position_y = data.position.y;
          ch.position_z = data.position.z;
          ch.zone_id = data.zoneId;
          ch.stat_points = JSON.stringify(data.statPoints);
          ch.unspent_stat_points = data.unspentStatPoints;
          ch.unspent_skill_points = data.unspentSkillPoints;
          ch.skill_proficiencies = JSON.stringify(data.skillProficiencies);
          ch.skill_adeptness = JSON.stringify(data.skillAdeptness);
          ch.experience = data.experience;
          if (data.nation !== undefined) ch.nation = data.nation;
          if (data.lastSafeZoneId !== undefined) ch.last_safe_zone_id = data.lastSafeZoneId;
          if (data.inventory !== undefined) ch.inventory = JSON.stringify(data.inventory);
          if (data.equipment !== undefined) ch.equipment = JSON.stringify(data.equipment);
          if (data.gold !== undefined) ch.gold = data.gold;
          if (data.quests !== undefined) ch.character_quests = JSON.stringify(data.quests);
          if (data.recipes !== undefined) ch.character_recipes = JSON.stringify(data.recipes);
          if (data.unlockedZones !== undefined) ch.character_unlocked_zones = JSON.stringify(data.unlockedZones);
          break;
        }
      }
      return;
    }

    try {
      await this.db.postgres!.query(
        `UPDATE characters SET
          level = $1, experience = $2, position_x = $3, position_y = $4, position_z = $5,
          zone_id = $6, stat_points = $7, unspent_stat_points = $8,
          unspent_skill_points = $9, skill_proficiencies = $10, skill_adeptness = $11, job_id = $12,
          nation = $14, last_safe_zone_id = $15, inventory = $16, equipment = $17, gold = $18,
          character_quests = $19, character_recipes = $20, character_unlocked_zones = $21
         WHERE id = $13`,
        [
          data.level, data.experience.toString(),
          data.position.x, data.position.y, data.position.z,
          data.zoneId, JSON.stringify(data.statPoints),
          data.unspentStatPoints, data.unspentSkillPoints,
          JSON.stringify(data.skillProficiencies), JSON.stringify(data.skillAdeptness), data.jobId,
          characterId,
          data.nation || null,
          data.lastSafeZoneId || null,
          JSON.stringify(data.inventory || []),
          JSON.stringify(data.equipment || { ...DEFAULT_EQUIPMENT }),
          data.gold ?? 100,
          JSON.stringify(data.quests || []),
          JSON.stringify(data.recipes || []),
          JSON.stringify(data.unlockedZones || []),
        ]
      );
    } catch (error) {
      console.error('Save character error:', error);
    }
  }

  private generateToken(playerId: string, username: string): string {
    return jwt.sign({ playerId, username }, JWT_SECRET, { expiresIn: JWT_EXPIRY });
  }
}
