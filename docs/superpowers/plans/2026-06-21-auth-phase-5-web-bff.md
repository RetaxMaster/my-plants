# Auth Phase 5 — Web BFF (Nitro proxy + sealed session) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the browser talk only to the Nuxt server. The JWT lives in a sealed `httpOnly` session cookie (under the `secure` key, server-only); Nitro proxies all API calls to NestJS attaching the bearer.

**Architecture:** `nuxt-auth-utils` provides sealed sessions. `server/api/auth/{login,logout,me}` manage the session; `server/api/[...]` is a generic proxy. `useApi` targets the same-origin proxy and uses `useRequestFetch()` during SSR so the session cookie reaches the proxy.

**Tech Stack:** Nuxt 3 / Nitro, `nuxt-auth-utils`, Vitest.

**Repo:** `repos/my-plants-web`. Branch: `feature/user-auth`.

---

### Task 1: Install + configure `nuxt-auth-utils` and runtimeConfig

**Files:** `package.json`, `nuxt.config.ts`, `.env` / `.env.example`

- [ ] **Step 1: Install**

Run: `npm install nuxt-auth-utils`

- [ ] **Step 2: Configure `nuxt.config.ts`**

```ts
export default defineNuxtConfig({
  modules: ['@nuxt/ui', 'nuxt-auth-utils'],
  typescript: { strict: true, typeCheck: false, tsConfig: { compilerOptions: { types: ['node'] } } },
  runtimeConfig: {
    apiBase: process.env.NUXT_API_BASE ?? 'http://localhost:8000', // SERVER-ONLY: internal NestJS base
    // public.apiBase removed — the browser uses the same-origin /api proxy.
  },
  devServer: { port: 8001 },
  compatibilityDate: '2026-06-18',
});
```

- [ ] **Step 3: Env** — add `NUXT_SESSION_PASSWORD` (≥32 chars) to local `.env` (required by nuxt-auth-utils to seal the cookie) and a placeholder to `.env.example`. Add `NUXT_API_BASE` placeholder too. `.env` is gitignored.

- [ ] **Step 4: Commit**

```bash
git add package.json package-lock.json nuxt.config.ts .env.example
git commit -m "chore(auth): add nuxt-auth-utils + server-only apiBase runtimeConfig"
```

---

### Task 2: Auth server routes (login / logout / me)

**Files:**
- Create: `server/api/auth/login.post.ts`, `server/api/auth/logout.post.ts`, `server/api/auth/me.get.ts`

- [ ] **Step 1: `login.post.ts`** — token stored under `secure` (server-only):

```ts
export default defineEventHandler(async (event) => {
  const body = await readBody<{ username: string; password: string }>(event);
  const { apiBase } = useRuntimeConfig(event);
  try {
    const res = await $fetch<{ token: string; user: { username: string; role: 'USER'|'ADMIN' } }>(`${apiBase}/auth/login`, {
      method: 'POST', body: { username: body?.username, password: body?.password },
    });
    await setUserSession(event, { user: res.user, secure: { token: res.token } });
    return { user: res.user };
  } catch {
    throw createError({ statusCode: 401, statusMessage: 'Invalid credentials' });
  }
});
```

- [ ] **Step 2: `logout.post.ts`** — always clear the local session; revoke upstream best-effort:

```ts
export default defineEventHandler(async (event) => {
  const { apiBase } = useRuntimeConfig(event);
  const session = await getUserSession(event);
  const token = (session as any)?.secure?.token;
  if (token) {
    try { await $fetch(`${apiBase}/auth/logout`, { method: 'POST', headers: { Authorization: `Bearer ${token}` } }); }
    catch { /* expired/invalid upstream — still clear locally */ }
  }
  await clearUserSession(event);
  return { ok: true };
});
```

- [ ] **Step 3: `me.get.ts`** — read identity from the sealed session, no backend call:

```ts
export default defineEventHandler(async (event) => {
  const session = await getUserSession(event);
  if (!session?.user) throw createError({ statusCode: 401, statusMessage: 'Not authenticated' });
  return { user: session.user };
});
```

- [ ] **Step 4: Commit**

```bash
git add server/api/auth
git commit -m "feat(auth): BFF auth routes (login seals token under secure; logout; me)"
```

---

### Task 3: Generic proxy `server/api/[...].ts`

**Files:**
- Create: `server/api/[...].ts`

- [ ] **Step 1: Implement** — forward method/path/query/body to NestJS, attach the bearer from `session.secure.token`, do NOT forward incoming Host/Cookie:

```ts
export default defineEventHandler(async (event) => {
  const { apiBase } = useRuntimeConfig(event);
  const session = await getUserSession(event);
  const token = (session as any)?.secure?.token as string | undefined;

  // event.path is like "/api/plants?x=1"; strip the leading "/api" so it maps to NestJS.
  const path = event.path.replace(/^\/api/, '');
  const method = event.method;
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  const contentType = getRequestHeader(event, 'content-type');
  if (contentType) headers['content-type'] = contentType;

  const body = method === 'GET' || method === 'HEAD' ? undefined : await readRawBody(event);

  try {
    return await $fetch(`${apiBase}${path}`, { method, headers, body });
  } catch (err: any) {
    // Surface upstream status (notably 401) to the client.
    throw createError({ statusCode: err?.statusCode ?? err?.response?.status ?? 500, statusMessage: err?.statusMessage ?? 'Upstream error', data: err?.data });
  }
});
```

> The more specific `server/api/auth/*` routes take precedence over this catch-all by Nitro routing — verify in Task 5.

- [ ] **Step 2: Commit**

```bash
git add server/api/[...].ts
git commit -m "feat(auth): generic Nitro proxy to NestJS with bearer injection"
```

---

### Task 4: `useApi` → same-origin proxy + SSR cookie forwarding

**Files:**
- Modify: `composables/useApi.ts`

- [ ] **Step 1: Switch base + fetcher** (capture `useRequestFetch()` in setup scope):

```ts
export function useApi() {
  // On the server, clone the incoming request (cookies/headers) so the sealed session reaches the proxy
  // during SSR. Capture in setup scope — useRequestFetch() must not be called lazily inside a handler.
  const fetcher = import.meta.server ? useRequestFetch() : $fetch;
  const api = <T>(path: string, opts?: Parameters<typeof $fetch>[1]) => fetcher<T>(`/api${path}`, opts as any);
  // ...rest of the method map is UNCHANGED (every call already uses `api('/...')`).
}
```

- [ ] **Step 2: Typecheck + build**

Run: `npm run typecheck && npm run build`
Expected: green (note: `nuxt build` alone does not typecheck; run `typecheck`).

- [ ] **Step 3: Commit**

```bash
git add composables/useApi.ts
git commit -m "feat(auth): route useApi through the same-origin proxy (SSR-safe fetch)"
```

---

### Task 5: Proxy smoke test (public path works logged-out)

**Files:** `server/api/__tests__` or a Vitest unit if feasible; otherwise a documented manual check (the full E2E is Phase 7).

- [ ] **Step 1:** With the API running, start the web (`npm run dev`) and confirm: `GET /api/species` returns data WITHOUT a session (public), and `GET /api/plants` returns `401` without a session. Document the commands in the plan output. (Automated E2E is Phase 7.)

- [ ] **Step 2: Commit** any test added.

```bash
git add -A
git commit -m "test(auth): proxy public-vs-protected smoke check"
```
