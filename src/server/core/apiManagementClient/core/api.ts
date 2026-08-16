import { ApiError, type ApiResult } from './types';

/**
 * Central API client. All requests go to the Express admin API
 * (`/api/admin/*`) and carry the admin token via the `X-Admin-Token` header
 * (the server's `requireAdmin` middleware accepts that header for browsers).
 *
 * The token itself is managed by `auth.ts`; this module only reads it so the
 * transport layer stays free of storage concerns.
 */

const TOKEN_KEY = 'dust_admin_token';
const API_BASE = '/api';

let authToken: string = localStorage.getItem(TOKEN_KEY) ?? '';

/** Called by the auth module whenever the token changes. */
export function setApiToken(token: string): void {
  authToken = token;
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

export function getApiToken(): string {
  return authToken;
}

function buildHeaders(init?: HeadersInit): Headers {
  const headers = new Headers(init);
  if (authToken) headers.set('X-Admin-Token', authToken);
  if (!headers.has('Accept')) headers.set('Accept', 'application/json');
  return headers;
}

async function parseBody(res: Response): Promise<unknown> {
  const ctype = res.headers.get('content-type') ?? '';
  if (ctype.includes('application/json')) {
    try {
      return await res.json();
    } catch {
      return null;
    }
  }
  try {
    return await res.text();
  } catch {
    return null;
  }
}

/**
 * Core fetch wrapper. Throws `ApiError` on non-2xx so callers can simply
 * `await api.get(...)` inside try/catch (or rely on the useNotify composable).
 *
 * `basePath` is the prefix to prepend (`/api` for the normal client, `''` for
 * the root client used by endpoints mounted at the server root like `/health`).
 */
export async function request<T = unknown>(
  path: string,
  options: RequestInit = {},
  basePath: string = API_BASE,
): Promise<ApiResult<T>> {
  const isJsonBody =
    options.body !== undefined && !(options.body instanceof FormData);
  const headers = buildHeaders(options.headers);
  if (isJsonBody && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  let res: Response;
  try {
    res = await fetch(basePath + path, { ...options, headers });
  } catch (err) {
    throw new ApiError(
      err instanceof Error ? err.message : 'Network request failed',
      0,
      null,
    );
  }

  const body = await parseBody(res);
  if (!res.ok) {
    const message =
      (typeof body === 'object' && body && 'error' in body
        ? String((body as { error: unknown }).error)
        : `Request failed (${res.status})`);
    throw new ApiError(message, res.status, body);
  }

  return { ok: true, status: res.status, data: body as T };
}

function verbs(basePath: string) {
  return {
    get: <T = unknown>(path: string, init?: RequestInit) =>
      request<T>(path, { ...init, method: 'GET' }, basePath),
    post: <T = unknown>(path: string, body?: unknown, init?: RequestInit) =>
      request<T>(
        path,
        { ...init, method: 'POST', body: body === undefined ? undefined : JSON.stringify(body) },
        basePath,
      ),
    put: <T = unknown>(path: string, body?: unknown, init?: RequestInit) =>
      request<T>(
        path,
        { ...init, method: 'PUT', body: body === undefined ? undefined : JSON.stringify(body) },
        basePath,
      ),
    del: <T = unknown>(path: string, init?: RequestInit) =>
      request<T>(path, { ...init, method: 'DELETE' }, basePath),
  };
}

/** Convenience verbs. Each takes a path relative to `/api` (the admin API). */
export const api = verbs(API_BASE);

/**
 * Same verbs but for endpoints mounted at the server root (e.g. `/health`),
 * which are NOT under `/api`. The admin token header is still attached.
 */
export const rootApi = verbs('');
