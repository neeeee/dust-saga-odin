import type { Request, Response, NextFunction } from 'express';

/**
 * Guards admin routes behind a shared `ADMIN_TOKEN`. Fails closed (503) when
 * the token env var is unset so the surface is never accidentally open.
 *
 * Accepts the token via either `Authorization: Bearer <token>` or the
 * `X-Admin-Token` header — the latter is convenient for browser-based admin
 * UIs that can't easily set the Authorization header on downloads / image tags.
 */
export function requireAdmin(req: Request, res: Response, next: NextFunction): void {
  const expected = process.env.ADMIN_TOKEN;
  if (!expected) {
    console.warn(`[admin] rejected ${req.method} ${req.path} — ADMIN_TOKEN env var is not set`);
    res.status(503).json({ error: 'Admin API disabled (ADMIN_TOKEN not configured)' });
    return;
  }
  const provided = req.headers['authorization'];
  const token = typeof provided === 'string' && provided.startsWith('Bearer ')
    ? provided.slice(7)
    : (req.headers['x-admin-token'] as string | undefined);
  if (token !== expected) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }
  next();
}
