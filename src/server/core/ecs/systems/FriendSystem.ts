import { Packet, PacketType, PlayerSession } from '@dust-saga/shared';
import { DatabaseManager } from '../../database/DatabaseManager';

export interface FriendEntry {
  characterId: string;
  name: string;
  level: number;
  jobId: string;
  zoneId: string;
  online: boolean;
}

export interface FriendSystemDeps {
  getPlayers(): Map<string, PlayerSession>;
  sendToPlayer(characterId: string, packet: Packet): void;
}

/**
 * Mutual friend lists, persisted in Postgres (two rows per friendship) and
 * cached in memory. Online status is resolved from live sessions; offline
 * level/job snapshots come from the characters table at load time.
 */
export class FriendSystem {
  private db: DatabaseManager;
  private cache = new Map<string, FriendEntry[]>();

  constructor(private deps: FriendSystemDeps) {
    this.db = DatabaseManager.getInstance();
  }

  /** Live-session snapshot, or null when the character is offline. */
  private sessionOf(characterId: string): PlayerSession | undefined {
    return this.deps.getPlayers().get(characterId);
  }

  private entryFromSession(s: PlayerSession): FriendEntry {
    return {
      characterId: s.characterId,
      name: s.characterName,
      level: s.stats.level,
      jobId: s.jobId || '',
      zoneId: s.zoneId,
      online: true,
    };
  }

  /** Load a character's friend list (DB → cache) and send FRIEND_LIST. */
  async sendFriendList(characterId: string): Promise<void> {
    const list = await this.loadFriends(characterId);
    this.deps.sendToPlayer(characterId, {
      type: PacketType.FRIEND_LIST,
      timestamp: Date.now(),
      data: { friends: list },
    });
  }

  async loadFriends(characterId: string): Promise<FriendEntry[]> {
    const cached = this.cache.get(characterId);
    if (cached) {
      this.refreshOnlineFlags(cached);
      return cached;
    }

    const entries: FriendEntry[] = [];
    if (this.db.postgres) {
      try {
        const result = await this.db.postgres.query(
          `SELECT c.id, c.name, c.level, c.job_id
           FROM friends f
           JOIN characters c ON c.id = f.friend_id
           WHERE f.character_id = $1
           ORDER BY c.name`,
          [characterId],
        );
        for (const row of result.rows) {
          const session = this.sessionOf(row.id);
          entries.push(
            session
              ? this.entryFromSession(session)
              : {
                  characterId: row.id,
                  name: row.name,
                  level: row.level,
                  jobId: row.job_id || '',
                  zoneId: '',
                  online: false,
                },
          );
        }
      } catch (error) {
        console.error('[FriendSystem] loadFriends failed:', error);
      }
    }

    this.cache.set(characterId, entries);
    return entries;
  }

  private refreshOnlineFlags(entries: FriendEntry[]): void {
    for (const e of entries) {
      const session = this.sessionOf(e.characterId);
      e.online = !!session;
      if (session) {
        e.name = session.characterName;
        e.level = session.stats.level;
        e.jobId = session.jobId || '';
        e.zoneId = session.zoneId;
      }
    }
  }

  /**
   * Send a friend request to `name`. Friendship is two-way and consented:
   * the target gets a FRIEND_REQUEST dialog; the rows are only written when
   * they accept (respondRequest). A request to someone who already requested
   * you auto-accepts (both sides clearly consented).
   */
  async requestFriend(session: PlayerSession, name: string): Promise<void> {
    const characterId = session.characterId;
    const trimmed = (name || '').trim();
    if (!trimmed) return;

    if (trimmed.toLowerCase() === session.characterName.toLowerCase()) {
      this.sendAddResult(characterId, false, "You can't add yourself.");
      return;
    }

    if (!this.db.postgres) {
      this.sendAddResult(characterId, false, 'Friends require the database.');
      return;
    }

    try {
      // Requests need a live target (the dialog is interactive).
      let target: PlayerSession | null = null;
      for (const [, s] of this.deps.getPlayers()) {
        if (s.characterName.toLowerCase() === trimmed.toLowerCase()) {
          target = s;
          break;
        }
      }
      if (!target) {
        this.sendAddResult(characterId, false, `${trimmed} is not online.`);
        return;
      }
      const targetId = target.characterId;

      const existing = this.cache.get(characterId);
      if (existing?.some(e => e.characterId === targetId)) {
        this.sendAddResult(characterId, false, 'Already on your friend list.');
        return;
      }

      // Reverse request pending → both consented; become friends now.
      const reverse = await this.db.postgres.query(
        'SELECT 1 FROM friend_requests WHERE from_id = $1 AND to_id = $2',
        [targetId, characterId],
      );
      if (reverse.rows.length > 0) {
        await this.acceptMutual(characterId, targetId);
        this.deps.sendToPlayer(targetId, {
          type: PacketType.NOTIFICATION,
          timestamp: Date.now(),
          data: { message: `${session.characterName} accepted your friend request.`, type: 'success' },
        });
        this.sendAddResult(characterId, true, `You are now friends with ${target.characterName}.`);
        return;
      }

      const dupe = await this.db.postgres.query(
        'SELECT 1 FROM friend_requests WHERE from_id = $1 AND to_id = $2',
        [characterId, targetId],
      );
      if (dupe.rows.length > 0) {
        this.sendAddResult(characterId, false, 'Request already sent.');
        return;
      }

      await this.db.postgres.query(
        'INSERT INTO friend_requests (from_id, to_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
        [characterId, targetId],
      );

      this.deps.sendToPlayer(targetId, {
        type: PacketType.FRIEND_REQUEST,
        timestamp: Date.now(),
        data: { characterId, name: session.characterName, level: session.stats.level },
      });
      this.sendAddResult(characterId, true, `Friend request sent to ${target.characterName}.`);
    } catch (error) {
      console.error('[FriendSystem] requestFriend failed:', error);
      this.sendAddResult(characterId, false, 'Could not send friend request.');
    }
  }

  /** Target accepts/declines a pending FRIEND_REQUEST. */
  async respondRequest(session: PlayerSession, fromId: string, accept: boolean): Promise<void> {
    if (!this.db.postgres || !fromId) return;
    const toId = session.characterId;

    try {
      const pending = await this.db.postgres.query(
        'SELECT 1 FROM friend_requests WHERE from_id = $1 AND to_id = $2',
        [fromId, toId],
      );
      if (pending.rows.length === 0) return; // stale/unknown request

      await this.db.postgres.query(
        'DELETE FROM friend_requests WHERE from_id = $1 AND to_id = $2',
        [fromId, toId],
      );

      const requester = this.deps.getPlayers().get(fromId);
      const requesterName = requester?.characterName || 'Player';

      if (!accept) {
        if (requester) {
          this.deps.sendToPlayer(fromId, {
            type: PacketType.NOTIFICATION,
            timestamp: Date.now(),
            data: { message: `${session.characterName} declined your friend request.`, type: 'info' },
          });
        }
        this.deps.sendToPlayer(toId, {
          type: PacketType.NOTIFICATION,
          timestamp: Date.now(),
          data: { message: 'Friend request declined.', type: 'info' },
        });
        return;
      }

      await this.acceptMutual(fromId, toId);
      if (requester) {
        this.deps.sendToPlayer(fromId, {
          type: PacketType.NOTIFICATION,
          timestamp: Date.now(),
          data: { message: `${session.characterName} accepted your friend request.`, type: 'success' },
        });
      }
      this.deps.sendToPlayer(toId, {
        type: PacketType.NOTIFICATION,
        timestamp: Date.now(),
        data: { message: `You are now friends with ${requesterName}.`, type: 'success' },
      });
    } catch (error) {
      console.error('[FriendSystem] respondRequest failed:', error);
    }
  }

  /** Write the mutual friendship rows + refresh both online sides' lists. */
  private async acceptMutual(aId: string, bId: string): Promise<void> {
    if (!this.db.postgres) return;
    await this.db.postgres.query(
      `INSERT INTO friends (character_id, friend_id) VALUES ($1, $2), ($2, $1)
       ON CONFLICT DO NOTHING`,
      [aId, bId],
    );
    await this.db.postgres.query(
      'DELETE FROM friend_requests WHERE (from_id = $1 AND to_id = $2) OR (from_id = $2 AND to_id = $1)',
      [aId, bId],
    );
    this.cache.delete(aId);
    this.cache.delete(bId);
    if (this.sessionOf(aId)) await this.sendFriendList(aId);
    if (this.sessionOf(bId)) await this.sendFriendList(bId);
  }

  private sendAddResult(characterId: string, success: boolean, message: string): void {
    this.deps.sendToPlayer(characterId, {
      type: PacketType.FRIEND_ADD_RESULT,
      timestamp: Date.now(),
      data: { success, message },
    });
  }

  /** Remove a friend (mutual). Sender gets a fresh FRIEND_LIST. */
  async removeFriend(characterId: string, friendId: string): Promise<void> {
    if (!this.db.postgres || !friendId) return;
    try {
      await this.db.postgres.query(
        'DELETE FROM friends WHERE (character_id = $1 AND friend_id = $2) OR (character_id = $2 AND friend_id = $1)',
        [characterId, friendId],
      );
      this.cache.delete(characterId);
      this.cache.delete(friendId);
      if (this.sessionOf(characterId)) {
        await this.sendFriendList(characterId);
      }
      if (this.sessionOf(friendId)) {
        await this.sendFriendList(friendId);
      }
    } catch (error) {
      console.error('[FriendSystem] removeFriend failed:', error);
    }
  }

  /** On login: send the list and tell mutual friends we're online. */
  async onLogin(session: PlayerSession): Promise<void> {
    const list = await this.loadFriends(session.characterId);
    this.deps.sendToPlayer(session.characterId, {
      type: PacketType.FRIEND_LIST,
      timestamp: Date.now(),
      data: { friends: list },
    });
    for (const entry of list) {
      if (entry.characterId !== session.characterId && this.sessionOf(entry.characterId)) {
        this.deps.sendToPlayer(entry.characterId, {
          type: PacketType.FRIEND_STATUS,
          timestamp: Date.now(),
          data: { characterId: session.characterId, name: session.characterName, online: true },
        });
      }
    }
  }

  /** On disconnect: tell mutual friends we're offline, drop the cache entry. */
  onDisconnect(characterId: string): void {
    const list = this.cache.get(characterId) || [];
    this.cache.delete(characterId);
    for (const entry of list) {
      if (this.sessionOf(entry.characterId)) {
        this.deps.sendToPlayer(entry.characterId, {
          type: PacketType.FRIEND_STATUS,
          timestamp: Date.now(),
          data: { characterId, name: entry.name, online: false },
        });
      }
    }
  }
}
