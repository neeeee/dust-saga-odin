import { reactive, computed } from 'vue';
import { setApiToken, api } from './api';

/**
 * Auth state for the dashboard shell.
 *
 * The server's admin API is gated by a shared `ADMIN_TOKEN` (see
 * `core/api/middleware/adminAuth.ts`). There is no login exchange — the user
 * pastes the configured token once; we persist it in localStorage and attach
 * it to every request via the API client. "Logging in" simply validates the
 * token against an existing authenticated endpoint (`/admin/items/schema`).
 *
 * To swap to JWT-based login later, only this module + `core/api.ts` change;
 * panels never touch auth directly.
 */
interface AuthState {
  token: string;
  status: 'unknown' | 'checking' | 'authenticated' | 'unauthenticated';
  error: string | null;
}

const state = reactive<AuthState>({
  token: localStorage.getItem('dust_admin_token') ?? '',
  status: stateStatusFromToken(),
  error: null,
});

function stateStatusFromToken(): AuthState['status'] {
  return localStorage.getItem('dust_admin_token') ? 'unknown' : 'unauthenticated';
}

export const auth = {
  state,
  isAuthenticated: computed(() => state.status === 'authenticated'),

  /** Validate the current token by hitting any admin endpoint. */
  async verify(): Promise<boolean> {
    if (!state.token) {
      state.status = 'unauthenticated';
      return false;
    }
    setApiToken(state.token);
    state.status = 'checking';
    state.error = null;
    try {
      // Hit an authenticated admin endpoint to validate the token. A valid
      // token returns 200; a bad/missing one returns 401 (thrown as ApiError).
      await api.get('/admin/items/schema');
      state.status = 'authenticated';
      return true;
    } catch (err) {
      state.status = 'unauthenticated';
      state.error = err instanceof Error ? err.message : 'Token rejected';
      return false;
    }
  },

  async login(token: string): Promise<boolean> {
    state.token = token.trim();
    setApiToken(state.token);
    return this.verify();
  },

  logout(): void {
    state.token = '';
    state.status = 'unauthenticated';
    state.error = null;
    setApiToken('');
  },
};
