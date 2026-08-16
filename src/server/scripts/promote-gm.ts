/**
 * Promote (or demote) an account to a GM/admin role.
 *
 * Usage:
 *   npm run gm -- <username> <player|gm|admin>
 *
 * Examples:
 *   npm run gm -- neeeee admin
 *   npm run gm -- tester gm
 *   npm run gm -- badactor player    # demote
 *
 * Resolves the account by username (case-insensitive), updates the `role`
 * column on the `players` table, and exits. Works against the same database
 * the game server uses (configured via the same env vars / .env file).
 */
import 'dotenv/config';
import { AccountRole } from '@dust-saga/shared';
import { AuthManager } from '../core/auth/AuthManager';
import { DatabaseManager } from '../core/database/DatabaseManager';

async function main(): Promise<void> {
  const [usernameArg, roleArg] = process.argv.slice(2);

  if (!usernameArg || !roleArg) {
    console.error('Usage: npm run gm -- <username> <player|gm|admin>');
    process.exit(2);
  }

  const validRoles = Object.values(AccountRole) as string[];
  if (!validRoles.includes(roleArg.toLowerCase())) {
    console.error(`Invalid role "${roleArg}". Must be one of: ${validRoles.join(', ')}`);
    process.exit(2);
  }
  const role = roleArg.toLowerCase() as AccountRole;

  const db = DatabaseManager.getInstance();
  await db.connect();

  try {
    if (!db.isPostgresConnected()) {
      console.error('Database is not connected. Check DATABASE_URL / DB credentials and try again.');
      console.error('(Mock/dev mode does not persist roles across processes — run against a real DB.)');
      process.exit(1);
    }

    const auth = AuthManager.getInstance();
    const playerId = await auth.getAccountIdByUsername(usernameArg);
    if (!playerId) {
      console.error(`No account found with username "${usernameArg}".`);
      process.exit(1);
    }

    const ok = await auth.setAccountRole(playerId, role);
    if (!ok) {
      console.error(`Failed to update role for "${usernameArg}".`);
      process.exit(1);
    }

    console.log(`OK: ${usernameArg} → ${role}`);
    process.exit(0);
  } finally {
    await db.disconnect();
  }
}

main().catch(err => {
  console.error('GM promotion failed:', err);
  process.exit(1);
});
