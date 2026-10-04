# Soma API token auth

The `/api/*` routes currently have no app-level authentication. This patch adds
a shared bearer token so the iOS app (and the web app) must present it.

## Setup

1. **Generate a token** (on your Mac):
   ```
   openssl rand -hex 32
   ```

2. **Copy the new file** into the Soma web repo:
   ```
   cp api/_auth.ts /path/to/soma/api/_auth.ts
   ```

3. **Guard every route handler.** In each of these files —
   `api/blood-pressure.ts`, `api/sleep.ts`, `api/activities.ts`,
   `api/blood-tests.ts`, `api/blood-tests-bulk.ts`, `api/blood-tests-metrics.ts`,
   `api/backup.ts` (and `api/health.ts` if you want it private too) —
   add the import and the first line of the handler:
   ```ts
   import { requireApiToken } from './_auth.js';

   export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
     if (!requireApiToken(req, res)) return;
     await handleErrors(res, '...', async () => {
       ...
   ```
   (Note the `.js` extension — Vercel compiles to ESM, extensionless imports fail.)

4. **Send the token from the web app.** In `src/lib/api.ts`, inside `request()`:
   ```ts
   headers: {
     'Content-Type': 'application/json',
     // Soma API token (same value as the server's SOMA_API_TOKEN)
     Authorization: `Bearer ${import.meta.env.VITE_SOMA_API_TOKEN ?? ''}`,
     ...init?.headers,
   },
   ```

5. **Set Vercel env vars** (project Settings → Environment Variables):
   - `SOMA_API_TOKEN` = the token (all environments) — read server-side only.
   - `VITE_SOMA_API_TOKEN` = the same token (all environments) — bundled into the web app.

6. Run the full check suite (`npm run typecheck`, prettier, eslint, `vitest run`, build), commit, and push. Redeploy on Vercel.

7. In the **iOS app**, enter the API base URL and the same token in Settings (first launch). The token is stored in the Keychain and sent as `Authorization: Bearer …` on every request.

## Notes

- Fails closed: if `SOMA_API_TOKEN` is not set server-side, every request gets a 500 instead of being served openly.
- The comparison is constant-time.
- The web app keeps working because it sends the token from `VITE_SOMA_API_TOKEN`.
