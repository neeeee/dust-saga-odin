import { Router } from 'express';
import { requireAdmin } from '../../middleware/adminAuth';
import { createQuestsRouter } from './quests/route';
import { createCutscenesRouter } from './cutscenes/route';
import { createItemsRouter } from './items/route';
import type { ApiServices } from '../../index';

/**
 * Builds the `/api/admin` sub-tree. `requireAdmin` is applied once here so
 * every mounted admin router inherits the token check — individual route files
 * don't need to repeat it.
 */
export function createAdminRouter(services: ApiServices): Router {
  const admin = Router();
  admin.use(requireAdmin);
  admin.use('/quests', createQuestsRouter(services));
  admin.use('/cutscenes', createCutscenesRouter(services));
  admin.use('/items', createItemsRouter(services));
  return admin;
}
