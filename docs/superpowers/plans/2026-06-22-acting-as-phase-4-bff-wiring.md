# Acting As — Phase 4: BFF Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carry the impersonation state in the sealed BFF session and forward it to the API. Add `POST`/`DELETE /api/acting-as`, inject the `X-Act-As-Owner` header in the proxy, surface `actingAs` on the session, and add the `useApi` methods + types.

**Architecture:** Identity stays in the JWT (`secure.token`); the impersonation target + display label live as a top-level `actingAs` field on the `UserSession` (client-visible, so the banner reads it via `useUserSession()`). The proxy adds the header only when the session has `actingAs`. The API guard (Phase 1) honors it only for admins.

**Tech Stack:** Nuxt 3, Nitro server routes, nuxt-auth-utils, TypeScript.

**Reference:** spec §3, §5.1, §5.2. The verify gate for this repo is `npm run typecheck && npm run build` (use `NUXT_IGNORE_LOCK=1 npm run build` if the dev server is running). `nuxt build` does NOT typecheck — both are required. All commands run from `repos/my-plants-web/`.

---

### Task 1: Augment the session type

**Files:**
- Modify: `auth.d.ts`

- [ ] **Step 1:** Add `UserSession.actingAs` to the `#auth-utils` augmentation (top-level, client-visible — NOT under `secure`):

```ts
declare module '#auth-utils' {
  interface User {
    username: string;
    role: 'USER' | 'ADMIN';
  }

  interface SecureSessionData {
    token: string;
  }

  // The admin impersonation target. Top-level (not secure) so the client banner can read it via
  // useUserSession().session. Absent/null = not impersonating.
  interface UserSession {
    actingAs?: { ownerId: string; label: string } | null;
  }
}
```

- [ ] **Step 2 (verify):** `npm run typecheck` → PASS.

---

### Task 2: BFF routes — start & stop acting-as

**Files:**
- Create: `server/api/acting-as.post.ts`
- Create: `server/api/acting-as.delete.ts`

- [ ] **Step 1:** Create `server/api/acting-as.post.ts`. It is admin-gated, resolves the label **server-side** from the API `GET /owners` (so the client cannot spoof a label, and the owner is validated), then stores it in the session:

```ts
export default defineEventHandler(async (event) => {
  const session = await getUserSession(event);
  if (session.user?.role !== 'ADMIN') {
    throw createError({ statusCode: 403, statusMessage: 'Admin only' });
  }
  const body = await readBody<{ ownerId?: string }>(event);
  const ownerId = body?.ownerId?.trim();
  if (!ownerId) throw createError({ statusCode: 400, statusMessage: 'ownerId required' });

  const { apiBase } = useRuntimeConfig(event);
  const token = session.secure?.token;
  // Resolve the display label server-side; this also validates the owner exists & is admin-visible.
  const owners = await $fetch<{ ownerId: string; username: string; role: 'USER' | 'ADMIN' | null }[]>(
    `${apiBase}/owners`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  const target = owners.find((o) => o.ownerId === ownerId);
  if (!target) throw createError({ statusCode: 404, statusMessage: 'Unknown owner' });

  await setUserSession(event, { actingAs: { ownerId: target.ownerId, label: target.username } });
  return { actingAs: { ownerId: target.ownerId, label: target.username } };
});
```

- [ ] **Step 2:** Create `server/api/acting-as.delete.ts`. Clearing must REBUILD the session (because `setUserSession` merges via `defu` and cannot remove a field):

```ts
export default defineEventHandler(async (event) => {
  const session = await getUserSession(event);
  if (!session.user) throw createError({ statusCode: 401, statusMessage: 'Not authenticated' });
  // setUserSession merges (defu) and cannot delete a key — rebuild the session without `actingAs`,
  // preserving identity (user) and the sealed token (secure).
  await replaceUserSession(event, { user: session.user, secure: session.secure });
  return { actingAs: null };
});
```

- [ ] **Step 3 (verify the API):** Confirm `replaceUserSession` is exported by the installed nuxt-auth-utils: `grep -rl "replaceUserSession" node_modules/nuxt-auth-utils/dist`. **If it is NOT present**, instead use `await setUserSession(event, { actingAs: null });` here and make the proxy/me checks treat only a truthy `actingAs.ownerId` as active (they already do, in Tasks 3–4). Pick one approach and keep it consistent.

- [ ] **Step 4 (verify):** `npm run typecheck` → PASS.

---

### Task 3: Proxy forwards the header

**Files:**
- Modify: `server/api/[...].ts`

- [ ] **Step 1:** After the `Authorization` header is set, add the act-as header when the session carries it. Replace the header-building block:

```ts
  // Build a clean header set: never forward the incoming Host/Cookie to NestJS.
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (session.actingAs?.ownerId) headers['x-act-as-owner'] = session.actingAs.ownerId;
  const contentType = getRequestHeader(event, 'content-type');
  if (contentType) headers['content-type'] = contentType;
```

(The `session` is already loaded at the top of this handler; just read `session.actingAs`.)

- [ ] **Step 2 (verify):** `npm run typecheck && NUXT_IGNORE_LOCK=1 npm run build` → PASS.

- [ ] **Step 3: Commit.**

```bash
git add auth.d.ts server/api/acting-as.post.ts server/api/acting-as.delete.ts server/api/[...].ts
git commit -m "feat(web): BFF acting-as routes + proxy X-Act-As-Owner header"
```

---

### Task 4: `me` passthrough + `useApi` + types

**Files:**
- Modify: `server/api/auth/me.get.ts`
- Modify: `types/api.ts`
- Modify: `composables/useApi.ts`

- [ ] **Step 1:** Update `server/api/auth/me.get.ts` to include `actingAs` (the banner primarily uses `useUserSession().session`, but keep this endpoint consistent):

```ts
export default defineEventHandler(async (event) => {
  const session = await getUserSession(event);
  if (!session.user) {
    throw createError({ statusCode: 401, statusMessage: 'Not authenticated' });
  }
  return { user: session.user, actingAs: session.actingAs ?? null };
});
```

- [ ] **Step 2:** In `types/api.ts`, add the owner-summary type and extend `PlantViability` with the two fields the API now returns:

```ts
export interface OwnerSummary {
  ownerId: string;
  username: string;
  role: 'USER' | 'ADMIN' | null;
}
```

In the existing `PlantViability` interface, add the two fields:

```ts
export interface PlantViability {
  plantId: string; nickname: string | null; speciesSlug: string;
  speciesScientificName: string; speciesCommonName: string;
  level: ViabilityLevel; reasons: string[];
  placeCityName: string;
  inPrimaryCity: boolean;
}
```

- [ ] **Step 3:** In `composables/useApi.ts`, import `OwnerSummary` (add it to the type import list at the top) and add three methods to the returned object. `listOwners` goes through the proxy (real API endpoint); `actAs`/`stopActingAs` hit the BFF routes directly (like `logout` does):

```ts
    listOwners: () => api<OwnerSummary[]>('/owners'),
    actAs: (ownerId: string) =>
      $fetch<{ actingAs: { ownerId: string; label: string } }>('/api/acting-as', { method: 'POST', body: { ownerId } }),
    stopActingAs: () =>
      $fetch<{ actingAs: null }>('/api/acting-as', { method: 'DELETE' }),
```

- [ ] **Step 4 (verify):** `npm run typecheck && NUXT_IGNORE_LOCK=1 npm run build` → PASS.

- [ ] **Step 5: Commit.**

```bash
git add server/api/auth/me.get.ts types/api.ts composables/useApi.ts
git commit -m "feat(web): me actingAs passthrough + useApi listOwners/actAs/stopActingAs"
```
