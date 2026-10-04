import { timingSafeEqual } from 'crypto';
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { json } from './_db.js';

/**
 * Bearer-token auth for the Soma serverless API.
 *
 * Every /api/* handler should call this first:
 *
 *   import { requireApiToken } from './_auth.js';
 *   export default async function handler(req: VercelRequest, res: VercelResponse) {
 *     if (!requireApiToken(req, res)) return;
 *     ...
 *   }
 *
 * The expected token comes from the SOMA_API_TOKEN env var (set in Vercel).
 * Fails closed: if the env var is missing, all requests are rejected with 500
 * rather than served unauthenticated.
 */
export function requireApiToken(req: VercelRequest, res: VercelResponse): boolean {
  const expected = process.env.SOMA_API_TOKEN;
  if (!expected) {
    json(res, 500, { error: 'API token is not configured on the server' });
    return false;
  }

  const header = req.headers.authorization ?? '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token || !safeEqual(token, expected)) {
    json(res, 401, { error: 'Unauthorized' });
    return false;
  }
  return true;
}

/** Constant-time string comparison (pads to equal length first). */
function safeEqual(a: string, b: string): boolean {
  const aBuf = Buffer.from(a);
  const bBuf = Buffer.from(b);
  if (aBuf.length !== bBuf.length) {
    // Compare against a same-length buffer so timing doesn't leak the length.
    return timingSafeEqual(aBuf, Buffer.alloc(aBuf.length)) && false;
  }
  return timingSafeEqual(aBuf, bBuf);
}
