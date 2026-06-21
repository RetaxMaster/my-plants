# User Authentication & Login Wall — Design Spec

**Date:** 2026-06-21
**Status:** Approved (pending Codex review gate)
**Repos touched:** `my-plants-api` (auth, guard, scoping, script, migration), `my-plants-web` (BFF proxy, login, route guard), root docs.

---

## 1. Purpose & context

MyPlants is being prepared to live on the public internet so its single owner (Carlos) can reach it
from anywhere. The system must **not** be open to whoever finds the URL. This feature adds an
authentication **login wall**: every owner-scoped surface requires a logged-in user; only the blog
(reference content) stays public.

This is explicitly **single-real-user** software. The user/role layer exists purely to gate access on
the internet, not to onboard other people. There is no self-service registration: users are created
by an operator script. The design nonetheless implements proper per-user ownership and an admin role,
because the data model was built for it from day one and doing it correctly is cheap.

**The system was pre-wired for this.** An `Owner` table already anchors every resource
(`City`, `Place`, `Plant`, `ScheduledMove` all carry `ownerId`), and every service funnels through a
single seam — `OwnerService.currentOwnerId()` — which today returns a hardcoded `"default"` owner.
Replacing that seam with "the owner carried by the authenticated request" is the bulk of the backend
work; **no resource table changes**.

### Goals

- A real login wall: unauthenticated requests to owner-scoped routes are rejected (API) / redirected
  to `/login` (web). The blog is reachable without logging in.
- Users created via an `npm` script on the API (`username` + `password`, password bcrypt-hashed,
  `role` ∈ {USER, ADMIN}).
- Bearer-token (JWT) auth between web and API, with a 30-day TTL and **real logout** (server-side
  revocation via a blocklist).
- The web stores the token using a **BFF** strategy: an `httpOnly` cookie the browser JS cannot read,
  with the Nuxt server (Nitro) proxying all API calls and attaching the bearer.
- **Resource ownership enforced**: a USER can only see/modify their own resources; an ADMIN bypasses
  ownership and can act on any resource (the single exception to ownership).

### Non-goals (explicitly out of scope)

- **Deployment** (HTTPS, domain, production secrets/CORS, where it runs). The login wall is a
  *prerequisite* for deploying, but the deploy flow itself is a separate effort and must be defined in
  `docs/deploy.md` first (per the workspace constitution; we do not improvise a deploy flow here).
- Self-service signup, password reset/change flows, email, refresh tokens, "remember me", MFA.
- Per-user UI for managing other users. Multi-tenant niceties beyond ownership enforcement.
- Rate-limiting / brute-force protection on login. (Noted as a possible small add-on in §12; not
  included by default given a single user and the BFF same-origin posture.)

---

## 2. Decisions (chosen during brainstorming)

| # | Decision | Choice | Rationale |
|---|---|---|---|
| D1 | Identity model vs existing `Owner` | **Separate `users` table, 1:1 with `Owner`** | Keeps credentials/role separate from resource ownership; one new table + FK, no churn on resource tables. |
| D2 | Token type | **JWT (signed) + revocation blocklist** | Stateless identity (userId/role travel signed in the token); blocklist enables true logout despite the 30-day TTL. |
| D3 | Web token storage | **Full BFF proxy via Nitro** | Token lives only in a sealed `httpOnly` cookie; browser never holds it (XSS-resistant); no browser↔API CORS in production. |
| D4 | Password hashing | **bcrypt** | Standard, well-supported one-way hashing in Node. |
| D5 | Request→service identity propagation | **`nestjs-cls` (AsyncLocalStorage)** | A per-request store any service can read, so we don't thread an actor argument through every method signature. |

> Tradeoff note for D2: because logout must revoke despite a 30-day TTL, the guard checks the blocklist
> on **every** request (a DB read per request). JWT's payoff here is that `userId`/`ownerId`/`role`
> arrive signed inside the token, so we never need a per-request user lookup — only a `jti` blocklist
> check.

### 2.1 New dependencies (none present today — must be added)

- **`my-plants-api`:** `@nestjs/jwt` (sign/verify), `bcrypt` + `@types/bcrypt` (hashing), `nestjs-cls`
  (per-request actor store). Added to `package.json`.
- **`my-plants-web`:** `nuxt-auth-utils` (sealed `httpOnly` session cookie), added to `dependencies`
  **and** to Nuxt `modules` in `nuxt.config.ts`; it requires a `NUXT_SESSION_PASSWORD` env (≥32 chars).

These installs are part of the implementation plan, not assumed pre-existing.

---

## 3. Data model (Prisma + migration)

Two new tables; **zero changes** to resource tables.

### 3.1 `User` (1:1 with `Owner`)

```prisma
enum UserRole {
  USER
  ADMIN
}

model User {
  id           String   @id @default(cuid())
  username     String   @unique
  passwordHash String   @map("password_hash")
  role         UserRole @default(USER)
  ownerId      String   @unique @map("owner_id")   // 1:1
  owner        Owner    @relation(fields: [ownerId], references: [id])
  createdAt    DateTime @default(now()) @map("created_at")
  @@map("users")
}
```

Back-relation added to `Owner`:

```prisma
model Owner {
  // ...existing fields...
  user User?
}
```

### 3.2 `RevokedToken` (the logout blocklist)

```prisma
model RevokedToken {
  jti       String   @id                       // the JWT's unique id
  expiresAt DateTime @map("expires_at")         // == the token's own exp; lets us purge stale rows
  @@index([expiresAt])
  @@map("revoked_tokens")
}
```

### 3.3 Migration `0006_add_users_and_revoked_tokens`

Hand-authored SQL applied with `npm run prisma:migrate` (= `prisma migrate deploy`). We do **not** use
`prisma migrate dev`: the scoped DB user lacks the global `CREATE` privilege Prisma's shadow database
needs (documented project convention — see `docs/IMPLEMENTATION-STATUS.md`). SQL outline:

```sql
CREATE TABLE `users` (
  `id`            VARCHAR(191) NOT NULL,
  `username`      VARCHAR(191) NOT NULL,
  `password_hash` VARCHAR(191) NOT NULL,
  `role`          ENUM('USER','ADMIN') NOT NULL DEFAULT 'USER',
  `owner_id`      VARCHAR(191) NOT NULL,
  `created_at`    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE INDEX `users_username_key`(`username`),
  UNIQUE INDEX `users_owner_id_key`(`owner_id`),
  PRIMARY KEY (`id`),
  CONSTRAINT `users_owner_id_fkey` FOREIGN KEY (`owner_id`) REFERENCES `owners`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `revoked_tokens` (
  `jti`        VARCHAR(191) NOT NULL,
  `expires_at` DATETIME(3)  NOT NULL,
  INDEX `revoked_tokens_expires_at_idx`(`expires_at`),
  PRIMARY KEY (`jti`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

---

## 4. Backend — authentication

### 4.1 New env vars (`src/config/env.ts` + `.env.example`)

Add to the auth env schema:

- `JWT_SECRET` — `z.string().min(32)` (required; signing secret; never committed — only `.env.example`
  carries a placeholder).
- `JWT_EXPIRES_IN` — `z.string().min(1).default('30d')` (token TTL; default fulfills the 30-day rule,
  overridable).

The DB connection stays assembled from the separate `DB_*` vars (unchanged).

**Split env validation so Prisma scripts don't require auth secrets (addresses the script-coupling
risk).** Today `scripts/write-prisma-env.ts` (run by `prisma:generate`/`prisma:migrate`) calls the
single `loadEnv()`. If we make `JWT_SECRET` required on that one schema, migrations would refuse to run
without auth secrets present — wrong coupling. Refactor into two schemas: a **`loadDbEnv()`** (the
`DB_*` vars only) used by the Prisma scripts and `database-url` assembly, and the full **`loadEnv()`**
(DB + `PORT`/`DEFAULT_CITY_TZ` + `JWT_*`) used by the running app at bootstrap. The app keeps validating
auth secrets at startup; the Prisma tooling only ever needs DB vars.

### 4.2 `AuthModule`

- **`AuthService`**
  - `login(username, password)`: look up the user by `username`; `bcrypt.compare` the password; on
    success sign a JWT with payload `{ sub: userId, ownerId, role, jti }` and `expiresIn = JWT_EXPIRES_IN`.
    `jti` is a fresh unique id (cuid/uuid). Returns `{ token, user: { username, role } }`. On failure
    throws `UnauthorizedException` (generic message — never reveal which of username/password was wrong).
  - `logout(jti, exp)`: insert `{ jti, expiresAt: new Date(exp * 1000) }` into `revoked_tokens`
    (idempotent — ignore duplicate-key). Binds a native `Date` (MariaDB date rule: never compare/store
    date columns via ISO strings).
  - `verify(token)`: `jwt.verify` (signature + expiry) then check `revoked_tokens` for the `jti`; reject
    if present. Returns the validated payload.
  - `purgeExpired()` (lazy/opportunistic): delete `revoked_tokens` rows with `expiresAt < NOW()` (use
    the DB's `NOW()` / a bound native `Date`). Called on login; a cron is unnecessary at this scale.
- **`AuthController`**
  - `POST /auth/login` — `@Public()`; body `{ username, password }` → `{ token, user }`.
  - `POST /auth/logout` — protected; revokes the caller's current token (reads `jti`/`exp` from the
    validated payload). Returns `{ ok: true }`. **Already-expired tokens:** because the global guard
    protects this route, an expired/invalid token never reaches the handler (the guard returns `401`
    first). That is fine — an expired token is already unusable, so there is nothing to revoke. The web
    BFF treats logout as "always clear the local session; revoke upstream only on success" (see §6.2),
    so a `401` from the backend logout still logs the user out locally.
  - `GET /auth/me` — protected; returns `{ username, role }` of the current actor.

Use `@nestjs/jwt` (`JwtModule`) for sign/verify. **This repo has no `@nestjs/config`/`ConfigService`** —
config is exposed through the custom `ENV` provider (a `Symbol`) in `config.module.ts`
(`{ provide: ENV, useFactory: () => loadEnv() }`). Wire `JwtModule` via `JwtModule.registerAsync({ inject: [ENV], useFactory: (env) => ({ secret: env.JWT_SECRET, signOptions: { expiresIn: env.JWT_EXPIRES_IN } }) })`,
and inject `ENV` wherever auth code needs secrets — not a non-existent `ConfigService`.

### 4.3 Global guard + `@Public()`

- `@Public()` = `SetMetadata('isPublic', true)`, applied to public handlers.
- `JwtAuthGuard` registered globally via `APP_GUARD` (default-deny: everything is protected unless
  marked `@Public()`):
  1. If the handler/class is `@Public()`, allow.
  2. Extract the bearer from `Authorization: Bearer <token>`; missing/malformed → `401`.
  3. `AuthService.verify(token)`; invalid/expired/revoked → `401`.
  4. On success, populate the CLS store with the actor `{ userId, ownerId, role, jti, exp }` and also
     attach it to `req.user`. Allow.

### 4.4 Request→service identity (`nestjs-cls`)

`ClsModule.forRoot({ global: true, middleware: { mount: true } })` establishes a per-request
AsyncLocalStorage context before guards run. The guard writes the actor into it. A thin `ActorService`
(or the refactored `OwnerService`) exposes:

- `currentActor(): { userId, ownerId, role } | null` — the request actor, or `null` outside a request.
- `currentOwnerId(): string` — the actor's `ownerId` (replaces the old hardcoded `"default"` lookup);
  throws if there is no actor.
- `currentRole(): UserRole` — throws if there is no actor.
- `ownerFilter(): { ownerId: string } | {}` — `{}` when the actor is **ADMIN**, `{ ownerId }` otherwise.
  This encodes the admin bypass **for row-selection reads/single-row lookups only** — see §4.5 for the
  important limits on where `{}` is safe.

Reading the actor when none is set is a programming error in a request path and throws. **System jobs
(no request) are a first-class, explicit path — not an error — see §4.4a.**

### 4.4a System jobs (no HTTP request → no actor)

Two code paths run outside any request and must NOT depend on the CLS actor:

- **Startup** (`StartupService.onApplicationBootstrap`) → `MovingService.applyDueMoves()` then (only if
  zero moves applied) `CarePlanService.recomputeAll()`.
- **Daily cron** (`MovingCron.daily` → `applyDueMoves`; and the 05:00 care recompute).

**Important — current code is NOT all-owner-safe (this MUST be refactored):**

- `CarePlanService.recomputeAll()` already sweeps *all* plants (`plant.findMany()` with no owner
  filter) — fine for a system job as-is.
- `MovingService.applyDueMoves()` is **owner-scoped today**: it calls `currentOwnerId()`
  (`moving.service.ts:104`) and everything it does is bound to that one owner — the due-moves query
  (`where: { ownerId, ... }`), the timezone cutoff (reads *that owner's* primary city), the `isPrimary`
  reset (`updateMany where ownerId`), and the outdoor-place repoint (`updateMany where ownerId`). Since
  it is invoked only from the cron and startup (no request → no actor), and `currentOwnerId()` throws
  without an actor, **the cron and every app boot would crash**.

Rule / required refactor: `applyDueMoves` must become a genuinely **owner-agnostic, all-owners** job.
Split it into:

- `applyDueMovesForOwner(ownerId, now)` — the current body, but taking `ownerId` as a parameter instead
  of reading `currentOwnerId()` (each owner keeps its own timezone cutoff, `isPrimary` reset, and
  repoint scoped to that `ownerId`). It applies the moves but **does not** call `recomputeAll()` itself.
- `applyAllDueMoves(now)` — iterates `owner.findMany()` and calls `applyDueMovesForOwner` for each,
  summing the count; then, **once** at the end, calls `recomputeAll()` a single time if the total > 0
  (avoids a redundant global recompute per owner — the old body recomputed inside the per-owner path).

The cron and `StartupService` call `applyAllDueMoves` (never the actor). General rule for system jobs:
they **never** call `currentOwnerId()`/`ownerFilter()`; they either sweep all rows (`recomputeAll`) or
iterate owners explicitly (`applyAllDueMoves`), resolving any per-owner anchor (timezone, primary city)
inside the loop. Request-entry methods that *also* want a system-wide sweep (see `recompute` in §4.5)
gate that on role; the jobs call the all-owners form directly.

### 4.5 Ownership enforcement + admin bypass (service refactor)

The existing uniform pattern (`const ownerId = await this.owner.currentOwnerId(); where: { ownerId }`)
is updated across every owner-scoped service — **Plants, Places, Cities, CarePlan, Feedback, Moving**
(and any owner-scoped read model). Note `InAppNotificationsService.pending()` (`notifications.service.ts`)
also calls `currentOwnerId()`; it is latent today (no controller/cron invokes it) and is an inherently
**per-actor** read ("my pending tasks") — it stays scoped to the actor's own `ownerId` with no admin
bypass; just don't lose it in the refactor. **The admin bypass is NOT a blind `where: {}` swap** — that is unsafe
for two real patterns in this codebase (per-owner sweeps and create-time FK validation). The rules,
by operation kind:

- **Reads — list/get** (`findMany`/`findFirst`): `where: { ...ownerFilter() }` (and
  `{ id, ...ownerFilter() }` for one). A USER sees only their rows; an ADMIN sees all. Safe because the
  filter only *widens what is selected*.
- **Single-row mutation by id** (update/postpone/feedback on an existing row): first resolve the target
  row with `{ id, ...ownerFilter() }` (USER must own it; ADMIN may load anyone's). Then mutate that
  specific row by its `id`. The effect is confined to the one targeted row.
- **Per-owner "sweep" mutations** — operations that write *all rows of an owner*, not one row — MUST
  derive the owner from the **target resource**, never from `ownerFilter() = {}`. The concrete case is
  `CitiesService.makePrimary(id)`: it clears `isPrimary` across the owner's cities before setting one.
  Rule: load the target city (with `ownerFilter()` for the access check), then run the reset scoped to
  **that city's `ownerId`** (`where: { ownerId: city.ownerId }`), so an ADMIN making someone's city
  primary only resets *that* owner's cities — never everyone's. The same `create`-with-`isPrimary`
  reset (in `CitiesService.create`) is scoped to the new city's owner (the actor) for the same reason.
- **Creation**: the new resource is owned by the actor (`ownerId: currentOwnerId()`). **Create-time FK
  validation uses the new resource's owner, NOT `ownerFilter()`** — e.g., a new plant's `placeId` must
  belong to the same `ownerId` the plant will get; a new place's `cityId` likewise. This prevents an
  ADMIN from accidentally creating an owner-A plant pointing at an owner-B place (a cross-owner
  dangling relation). If an ADMIN ever needs to create *on behalf of* another owner, that is an
  explicit future feature (an `actingOwnerId` parameter), out of scope here.
- **Request methods that expose a system-wide sweep** — `CarePlanController.recompute()` calls
  `recomputeAll()` (all plants). Gate by role: a **USER** recomputes only their own garden (a new
  `recomputeOwner(ownerId)` that filters plants by owner); an **ADMIN** may recompute all
  (`recomputeAll()`). The owner-agnostic `recomputeAll()` stays for system jobs (§4.4a).

`cities/search` is **not owner-scoped** (it proxies public geocoding reference data, not the owner's
saved cities) but it is **still authenticated** (no `@Public()`): "not owner-filtered" ≠ "open without
login". The existing in-code comment that calls it "public reference data" is about *ownership*, not
*auth*; it will be clarified during implementation.

Net effect: "a USER never touches another user's resources; an ADMIN is the single exception" is a
structural property of the data-access layer — and the exception is implemented per operation kind, so
it never silently widens a per-owner sweep or a create-time FK check.

### 4.6 CORS / main.ts

With the BFF, the browser only talks to Nitro (same origin); Nitro→API is server-to-server (no CORS).
The existing `WEB_ORIGIN` CORS allowance is kept (defensive; harmless) and the stale "v1 has no auth"
comment is updated. No browser-facing CORS relaxation is introduced.

---

## 5. User registration script (`my-plants-api`)

`npm run user:create -- --username <u> --password <p> [--role admin|user] [--adopt-default]`

- Implemented as a standalone `tsx` script (`scripts/create-user.ts`) following the existing script
  convention (loads `.env`, builds Prisma env the same way as `prisma:*` scripts).
- Validates: username non-empty and unique; password meets a minimum length; role ∈ {user, admin}
  (default `user`).
- bcrypt-hashes the password (cost factor ~12).
- In a single transaction: creates an `Owner` (name defaults to the username) **or**, with
  `--adopt-default`, links the user to the pre-existing `"default"` owner so local seed/E2E data stays
  visible under the new account; then creates the `User` row.
- Convenience: `npm run user:list` prints `username | role | createdAt` (no password material).

The script is the **only** way users are created (no HTTP signup endpoint).

---

## 6. Frontend — BFF (Nuxt 3 / Nitro)

The browser only ever calls the Nuxt server (same origin). The JWT lives in a **sealed `httpOnly`
cookie** managed by `nuxt-auth-utils` (idiomatic Nuxt session sealing; requires a
`NUXT_SESSION_PASSWORD` env). The browser's JS cannot read it.

### 6.1 `runtimeConfig` change

```ts
runtimeConfig: {
  apiBase: process.env.NUXT_API_BASE ?? 'http://localhost:8000', // SERVER-ONLY: internal NestJS base
  // public.apiBase is removed — the browser no longer addresses NestJS directly.
}
```

### 6.2 Nitro server routes (`server/`)

- `server/api/auth/login.post.ts` — receives `{ username, password }`, calls `POST {apiBase}/auth/login`,
  and on success seals the session as **`setUserSession(event, { user: { username, role }, secure: { token } })`**.
  **Critical:** the JWT goes under the **`secure`** key, NOT at the session root. `nuxt-auth-utils`
  exposes the *decrypted* session to the client (via its session endpoint / `useUserSession()`) for
  everything **except** the `secure` sub-object, which is server-only. Putting `token` at the root would
  leak it to the browser and defeat the whole BFF/`httpOnly` purpose. The handler returns only
  `{ user }`. On failure returns `401`.
- `server/api/auth/logout.post.ts` — reads the session token and calls `POST {apiBase}/auth/logout` with
  the bearer to revoke it upstream, but **always clears the local session cookie regardless of the
  upstream result** (a `401`/error from an already-expired token still logs the user out locally).
  Returns `{ ok: true }`.
- `server/api/auth/me.get.ts` — returns the session `user` (or `401` if no session). Used by the route
  guard / UI. Reads from the sealed session (populated at login), so it needs no backend call.
- `server/api/[...].ts` — **generic proxy**: forwards method + path + **query string** + body to
  `{apiBase}/<path>`, reading the token from `session.secure.token` and attaching
  `Authorization: Bearer <token>` when a session exists (omitted when there is none, so public endpoints
  like `species/*` still work for logged-out blog visitors). It **must not forward the incoming `Host`
  or `Cookie` headers** to the upstream (only set `Authorization`); it must preserve `Content-Type` and
  the body across all methods (GET has no body). It propagates the upstream status (notably surfaces
  `401`). The more specific `auth/*` routes take precedence over this catch-all by Nitro routing.

### 6.3 `useApi` change

`useApi` now targets the same-origin proxy: every call becomes `\`/api${path}\`` instead of
`\`${publicApiBase}${path}\``. No call-site changes; the request surface is identical.

**SSR cookie forwarding (critical).** Most pages fetch through `useAsyncData` during server-side render
(e.g. `pages/index.vue`, `pages/blog/index.vue`, plant pages). A plain `$fetch('/api/...')` invoked on
the Nitro server does **not** carry the incoming browser's session cookie, so the proxy would see no
session and return `401` during SSR. Fix: in `useApi`, use Nuxt's **`useRequestFetch()`** (which clones
the incoming request's cookies/headers) instead of the global `$fetch` when running on the server, so
the sealed session cookie reaches the proxy during SSR. **Capture it in setup scope**, not lazily
inside an async handler — `useRequestFetch()`/`useRequestEvent()` only have the request event available
synchronously during setup. So `useApi` does `const fetcher = import.meta.server ? useRequestFetch() : $fetch`
at the top and closes over `fetcher`; this matters because several call sites invoke the returned API
methods inside click handlers (after an `await`), where calling the composable directly would fail. On
the client, the same-origin `$fetch` naturally sends the cookie. The blog (public) works either way
since the proxy omits the bearer when no session exists.

### 6.4 Route protection + login page

- `middleware/auth.global.ts` — on navigation, if there is no session and the target route is not
  public, redirect to `/login` (preserving intended destination). Public web routes: `/login`,
  `/blog`, `/blog/[id]`.
- `pages/login.vue` — username/password form → `POST /api/auth/login` → on success redirect to the
  intended page (default `/`). Shows a generic error on failure.
- App chrome gains a **logout** action (calls `POST /api/auth/logout` then redirects to `/login`).
- A `401` from the proxy mid-session (e.g., token revoked/expired) clears the session and bounces to
  `/login`.

---

## 7. Public vs protected surface

**Public (no auth) — minimal surface, only what the public blog needs:**

- API: `POST /auth/login`; `GET /species` (lightweight catalog); `GET /species/:slug/brief` (the
  article).
- Web: `/login`, `/blog`, `/blog/[id]`.

**Why exactly these `species` endpoints:** `GET /species` returns a *lightweight reference catalog*
(`{ slug, scientificName, commonName }` only — no owner data) consumed by the **blog index** (public)
and the **"add plant" dropdown** (protected) — the blog cannot consume a protected endpoint, while a
protected page consuming a public reference endpoint is fine. `GET /species/:slug/brief` is the blog
article. We deliberately keep the **full record** endpoint `GET /species/:slug` **protected**: it
returns the entire curated `record` (care data), the blog does not need it, and no current web caller
uses it publicly — so it stays behind auth to minimize the public surface.

**Protected (auth required):** everything else — `GET /species/:slug` (full record), `plants/*`,
`places/*`, `cities/*` (**including `GET /cities/search`** — not owner-filtered, but still
login-gated), `care-plan/*`, `plants/:id/feedback`, `moving/*`, `auth/logout`, `auth/me`.

---

## 8. Data migration / existing local data

Today's local DB has a `"default"` owner holding E2E seed data (Boston fern, the dry/humid/null places,
plants). After this change, `currentOwnerId()` no longer auto-creates `"default"`; it reads the actor.
To keep local data visible, create your account with `--adopt-default`, which links your `User` to the
existing `"default"` owner. In production you start from a clean DB, so this is a non-issue there.

---

## 9. Testing

**API (Vitest + supertest):**

- Guard: valid token → allowed; missing/malformed/invalid-signature/expired/revoked → `401`; `@Public()`
  route → allowed without a token.
- Auth: login with correct vs incorrect password; logout adds `jti` to the blocklist and a subsequent
  request with that token is rejected; `me` returns the actor.
- `ownerFilter()`: returns `{ ownerId }` for USER and `{}` for ADMIN.
- Ownership: a USER cannot read/mutate another owner's plant/place/city (404/forbidden via scoping);
  an ADMIN can; creation always attaches the actor's `ownerId`.
- Tests are env-hermetic (set/restore `JWT_SECRET` etc. around assertions per the testing rule).

**Web:** the Nitro proxy attaches the bearer when a session exists and omits it otherwise; the global
middleware redirects unauthenticated navigation to `/login` while leaving `/blog` reachable;
`npm run typecheck` and `npm run build` are green.

**E2E (qa-engineer, local only):** no session → owner-scoped page redirects to `/login` and the API
returns `401`; after login → access works; logout → the old token is rejected; the blog renders
without logging in.

---

## 10. Security notes

- `JWT_SECRET` and `NUXT_SESSION_PASSWORD` are secrets: only `.env.example` placeholders are committed;
  real values never logged or echoed.
- Session cookie is `httpOnly`, `SameSite=Lax`, and `Secure` in production (the `Secure`/domain specifics
  are finalized with the deploy flow, which is out of scope here).
- bcrypt cost factor ~12; passwords never logged; login errors are generic (no user enumeration).
- Tokens never appear in the browser, in logs, or in error payloads. In the web session this is enforced
  by storing the JWT under the `nuxt-auth-utils` **`secure`** key (server-only; never serialized to the
  client), per §6.2 — not at the session root.

---

## 11. Backward compatibility

- Resource tables are unchanged; existing rows keep working (re-pointed to an owner via `--adopt-default`
  locally, or absent in a fresh prod DB).
- The public reference endpoints behave identically; only their access policy is formalized as public.
- `OwnerService.currentOwnerId()` keeps its name/signature for consumers but now resolves the actor from
  CLS instead of the hardcoded `"default"`, minimizing churn at call sites.

---

## 12. Possible small add-on (not included by default)

- **Login rate-limiting** (e.g., a simple per-username/IP throttle) to blunt brute force. Given a single
  user behind a BFF, it is optional; can be added if desired.

---

## 13. Build / workflow order

Per the multi-repo dependency order, this feature does **not** touch `my-plants-species-schema` or
`my-plants-knowledge-engine`. Order of work: **`my-plants-api`** (schema/migration → auth/guard/CLS →
service scoping → registration script → env) → **`my-plants-web`** (BFF proxy → login/logout/me →
route guard → `useApi`) → **root docs** (architecture, local-development, roadmap). Branch per affected
repo (`feature/user-auth`); follow the Multi-repo feature workflow for merge/push/pointer-bump
(gated on explicit user approval, as always).
