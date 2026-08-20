import { Pool } from 'pg';
import { createClient, RedisClientType } from 'redis';
import dotenv from 'dotenv';

dotenv.config();

export class DatabaseManager {
  private static instance: DatabaseManager;
  public postgres: Pool | null = null;
  public redis: RedisClientType | null = null;
  private postgresConnected: boolean = false;
  private redisConnected: boolean = false;

  private constructor() {
    try {
      this.postgres = new Pool({
        host: process.env.DB_HOST || 'localhost',
        port: parseInt(process.env.DB_PORT || '5432'),
        database: process.env.DB_NAME || 'dust_saga',
        user: process.env.DB_USER || 'postgres',
        password: process.env.DB_PASSWORD || 'password',
        max: 20,
        idleTimeoutMillis: 30000,
        connectionTimeoutMillis: 2000,
      });
    } catch (error) {
      console.warn('Failed to initialize PostgreSQL pool:', error);
      this.postgres = null;
    }

    try {
      this.redis = createClient({
        url: process.env.REDIS_URL || 'redis://localhost:6379'
      });
    } catch (error) {
      console.warn('Failed to initialize Redis client:', error);
      this.redis = null;
    }
  }

  static getInstance(): DatabaseManager {
    if (!DatabaseManager.instance) {
      DatabaseManager.instance = new DatabaseManager();
    }
    return DatabaseManager.instance;
  }

  async connect(): Promise<void> {
    if (this.postgres) {
      try {
        await this.postgres.connect();
        this.postgresConnected = true;
        console.log('PostgreSQL connected successfully');
      } catch (error) {
        console.warn('PostgreSQL connection error, running without database:', error);
        this.postgresConnected = false;
      }
    } else {
      console.warn('PostgreSQL not initialized, running without database');
    }

    if (this.redis) {
      try {
        await this.redis.connect();
        this.redisConnected = true;
        console.log('Redis connected successfully');
      } catch (error) {
        console.warn('Redis connection error, running without cache:', error);
        this.redisConnected = false;
      }
    } else {
      console.warn('Redis not initialized, running without cache');
    }
  }

  async disconnect(): Promise<void> {
    if (this.postgres) {
      await this.postgres.end();
    }
    if (this.redis) {
      await this.redis.quit();
    }
  }

  async initializeSchema(): Promise<void> {
    if (!this.postgres || !this.postgresConnected) {
      console.warn('Skipping database schema initialization (PostgreSQL not connected)');
      return;
    }

    const schema = `
      CREATE TABLE IF NOT EXISTS players (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(100) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT NOW(),
        last_login TIMESTAMP,
        level INTEGER DEFAULT 1,
        experience BIGINT DEFAULT 0
      );

      CREATE TABLE IF NOT EXISTS characters (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        player_id UUID REFERENCES players(id) ON DELETE CASCADE,
        name VARCHAR(50) NOT NULL,
        class VARCHAR(20) NOT NULL,
        race VARCHAR(20) NOT NULL DEFAULT 'human',
        racial_passive VARCHAR(50),
        job_id VARCHAR(30) NOT NULL DEFAULT 'warrior',
        level INTEGER DEFAULT 1,
        position_x FLOAT DEFAULT 0,
        position_y FLOAT DEFAULT 0,
        position_z FLOAT DEFAULT 0,
        rotation_x FLOAT DEFAULT 0,
        rotation_y FLOAT DEFAULT 0,
        rotation_z FLOAT DEFAULT 0,
        rotation_w FLOAT DEFAULT 1,
        zone_id VARCHAR(50) DEFAULT 'starter_zone',
        stat_points JSONB DEFAULT '{"STA":0,"STR":0,"AGI":0,"DEX":0,"SPI":0,"INT":0}',
        unspent_stat_points INTEGER DEFAULT 0,
        unspent_skill_points INTEGER DEFAULT 0,
        skill_proficiencies JSONB DEFAULT '{"melee":0,"technique":0,"prayer":0,"magic":0,"special":0}',
        skill_adeptness JSONB DEFAULT '{}',
        experience BIGINT DEFAULT 0,
        nation VARCHAR(20),
        last_safe_zone_id VARCHAR(50) DEFAULT 'starter_zone',
        created_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(player_id, name)
      );

      CREATE TABLE IF NOT EXISTS items (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(100) NOT NULL,
        type VARCHAR(20) NOT NULL,
        rarity VARCHAR(20) NOT NULL,
        stats JSONB NOT NULL,
        icon_url VARCHAR(255)
      );

      CREATE TABLE IF NOT EXISTS inventories (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        character_id UUID REFERENCES characters(id) ON DELETE CASCADE,
        item_id UUID REFERENCES items(id),
        quantity INTEGER DEFAULT 1,
        slot INTEGER,
        UNIQUE(character_id, slot)
      );

      CREATE TABLE IF NOT EXISTS quests (
        id VARCHAR(80) PRIMARY KEY,
        title VARCHAR(120) NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        type VARCHAR(20) NOT NULL,
        required_level INTEGER NOT NULL DEFAULT 1,
        required_quest VARCHAR(80),
        npc_id VARCHAR(80) NOT NULL,
        objectives JSONB NOT NULL DEFAULT '[]',
        rewards JSONB NOT NULL DEFAULT '{"experience":0,"gold":0,"items":[]}',
        dialog JSONB DEFAULT '{}',
        repeatable VARCHAR(20),
        max_completions INTEGER,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_quests_npc ON quests(npc_id);

      CREATE INDEX IF NOT EXISTS idx_characters_zone ON characters(zone_id);
      CREATE INDEX IF NOT EXISTS idx_characters_player ON characters(player_id);

      CREATE TABLE IF NOT EXISTS friends (
        character_id UUID NOT NULL,
        friend_id UUID NOT NULL,
        created_at TIMESTAMP DEFAULT NOW(),
        PRIMARY KEY (character_id, friend_id)
      );
      CREATE INDEX IF NOT EXISTS idx_friends_friend ON friends(friend_id);

      CREATE TABLE IF NOT EXISTS friend_requests (
        from_id UUID NOT NULL,
        to_id UUID NOT NULL,
        created_at TIMESTAMP DEFAULT NOW(),
        PRIMARY KEY (from_id, to_id)
      );
      CREATE INDEX IF NOT EXISTS idx_friend_requests_to ON friend_requests(to_id);

      CREATE TABLE IF NOT EXISTS guilds (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(40) UNIQUE NOT NULL,
        tag VARCHAR(6) NOT NULL,
        leader_id UUID NOT NULL,
        level INTEGER DEFAULT 1,
        experience BIGINT DEFAULT 0,
        gold BIGINT DEFAULT 0,
        bank_items JSONB DEFAULT '[]',
        rank_perms JSONB DEFAULT '{}',
        motd VARCHAR(255),
        created_at TIMESTAMP DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_guilds_leader ON guilds(leader_id);

      CREATE TABLE IF NOT EXISTS guild_members (
        guild_id UUID NOT NULL REFERENCES guilds(id) ON DELETE CASCADE,
        character_id UUID NOT NULL UNIQUE,
        rank VARCHAR(20) NOT NULL DEFAULT 'member',
        joined_at TIMESTAMP DEFAULT NOW(),
        PRIMARY KEY (guild_id, character_id)
      );
      CREATE INDEX IF NOT EXISTS idx_guild_members_character ON guild_members(character_id);
    `;

    try {
      await this.postgres.query(schema);
      console.log('Database schema initialized successfully');
      await this.runMigrations();
    } catch (error) {
      console.error('Error initializing database schema:', error);
      throw error;
    }
  }

  private async runMigrations(): Promise<void> {
    if (!this.postgres || !this.postgresConnected) return;

    const migrations = [
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS race VARCHAR(20) NOT NULL DEFAULT 'human'`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS job_id VARCHAR(30) NOT NULL DEFAULT 'warrior'`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS stat_points JSONB DEFAULT '{"STA":0,"STR":0,"AGI":0,"DEX":0,"SPI":0,"INT":0}'`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS unspent_stat_points INTEGER DEFAULT 0`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS unspent_skill_points INTEGER DEFAULT 0`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS skill_proficiencies JSONB DEFAULT '{"melee":0,"technique":0,"prayer":0,"magic":0,"special":0}'`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS skill_adeptness JSONB DEFAULT '{}'`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS experience BIGINT DEFAULT 0`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS nation VARCHAR(20)`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS last_safe_zone_id VARCHAR(50) DEFAULT 'starter_zone'`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS inventory JSONB DEFAULT '[]'`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS equipment JSONB DEFAULT '{"weapon":null,"armor":null,"helmet":null,"boots":null,"gloves":null,"legs":null,"shield":null,"earring_1":null,"earring_2":null,"necklace":null,"belt":null,"ring_1":null,"ring_2":null}'`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS gold INTEGER DEFAULT 100`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS racial_passive VARCHAR(50)`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS character_quests JSONB DEFAULT '[]'`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS character_recipes JSONB DEFAULT '[]'`,
      `ALTER TABLE characters ADD COLUMN IF NOT EXISTS character_unlocked_zones JSONB DEFAULT '[]'`,
      `ALTER TABLE players ADD COLUMN IF NOT EXISTS role VARCHAR(16) NOT NULL DEFAULT 'player'`,
      `ALTER TABLE quests ADD COLUMN IF NOT EXISTS dialog JSONB DEFAULT '{}'`,
      `ALTER TABLE quests ADD COLUMN IF NOT EXISTS repeatable VARCHAR(20)`,
      `ALTER TABLE quests ADD COLUMN IF NOT EXISTS max_completions INTEGER`,

      `CREATE TABLE IF NOT EXISTS cutscenes (
        id VARCHAR(80) PRIMARY KEY,
        zone_id VARCHAR(80) NOT NULL,
        script JSONB NOT NULL DEFAULT '[]',
        created_at TIMESTAMP DEFAULT NOW()
      )`,

      `CREATE TABLE IF NOT EXISTS item_definitions (
        id VARCHAR(80) PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        type VARCHAR(20) NOT NULL,
        rarity VARCHAR(20) NOT NULL,
        stats JSONB NOT NULL DEFAULT '{}',
        icon VARCHAR(255),
        max_stack INTEGER NOT NULL DEFAULT 1,
        sell_price INTEGER NOT NULL DEFAULT 0,
        required_level INTEGER NOT NULL DEFAULT 1,
        equipment_slot VARCHAR(20),
        weapon_type VARCHAR(20),
        soul_slots INTEGER,
        on_hit_procs JSONB,
        innate_procs JSONB,
        teaches_recipe VARCHAR(80),
        created_at TIMESTAMP DEFAULT NOW()
      )`,
      `CREATE INDEX IF NOT EXISTS idx_item_definitions_type ON item_definitions(type)`,
      `CREATE INDEX IF NOT EXISTS idx_item_definitions_rarity ON item_definitions(rarity)`,
      // Obelisk weapon flag (added in a later migration). Idempotent — the
      // runner ignores "column already exists" errors.
      `ALTER TABLE item_definitions ADD COLUMN IF NOT EXISTS obelisk_buff BOOLEAN DEFAULT FALSE`,
    ];

    for (const sql of migrations) {
      try {
        await this.postgres.query(sql);
      } catch {
        // Column already exists, ignore
      }
    }

    await this.postgres.query(`UPDATE characters SET job_id = class WHERE job_id = 'warrior' AND class != 'warrior'`).catch(() => {});
  }

  isPostgresConnected(): boolean {
    return this.postgresConnected;
  }

  isRedisConnected(): boolean {
    return this.redisConnected;
  }

  /** Create an additional, independent Redis client (e.g. for the Socket.IO adapter's pub/sub). */
  createRedisClient(): RedisClientType {
    return createClient({
      url: process.env.REDIS_URL || 'redis://localhost:6379'
    });
  }
}