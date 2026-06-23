# Architecture — MyPlants

This is the living architecture overview. The full rationale lives in
`docs/superpowers/specs/2026-06-18-myplants-architecture.md`; this doc is the quick map kept
in sync as the system evolves.

## Two subsystems, one data contract

MyPlants is two systems of different nature joined only by a shared data contract:

1. **Knowledge engine** (`repos/my-plants-knowledge-engine`) — its product is *data*: the
   curated truth about each species. Its AI authoring is a **two-step flow**: the
   `plant-researcher` subagent gathers the facts and emits one raw English brief (informational
   completeness, no style chasing); the operator then hands that brief + the structured record to a
   new `editorial-writer` subagent, which restyles it into a polished English brief and a fluent
   Spanish transcreation in one house voice (no web access, so it can only reshape given facts,
   never invent them). The persistence contract is unchanged — `db:insert` still receives
   `--brief-en` and `--brief-es`.
2. **Care app** — its product is *a daily experience*: what to do and when. Split into
   `repos/my-plants-api` (NestJS) and `repos/my-plants-web` (Nuxt 3).
3. **Shared contract** (`repos/my-plants-species-schema`) — a Zod schema + inferred types +
   validators; the single source of truth for the curated species-record shape. As of **v0.4.0**
   it carries `watering.humiditySensitivity` (low/medium/high, drives the humidity modulator), a
   `misting` section (`benefit` = beneficial | tolerated | avoid, `baseFrequencyDays`, free-text
   `note`), and a `primaryCommonName(record)` helper that is the single home of the display-name
   rule (returns `commonNames[0] ?? scientificName`). Every new field ships with a Zod default, so
   species already stored in the DB keep parsing without re-curation (backward-compatible).

## Repository topology

A Git multirepo orchestrator: the workspace root pins submodule commits and holds docs +
scripts only. The four submodules live under `repos/` as public GitHub repos under
`RetaxMaster`. The shared schema is consumed as a packed dependency (the dependency-order
rule), never copy-pasted — see `docs/multirepo-submodules.md`.

## Stack

| Area | Stack |
|---|---|
| Language | TypeScript everywhere (Node.js LTS) |
| Shared schema | Zod (validates at runtime + derives static types) |
| Knowledge engine | `tsx` scripts + Vitest; a two-step authoring flow driven by its own `CLAUDE.md` — `plant-researcher` writes ONE raw, fact-complete **English** brief, then an `editorial-writer` subagent rewrites it into polished English + Spanish in one consistent house voice |
| API | NestJS, Prisma ORM over **local MariaDB** (no Docker) |
| Web | Nuxt 3 + Vue 3 + an in-house design system imported from Claude Design (CSS tokens + Vue components under `components/ui/`; light/dark via `@nuxtjs/color-mode`; self-hosted fonts via `@nuxt/fonts`; icons via `@nuxt/icon` + local heroicons). No Nuxt UI / Tailwind. See `docs/frontend-design-system.md`. |
| Weather | Open-Meteo (free, no API key) |

## Care app modules (NestJS)

Domain modules, each an independently testable unit; the engines are **pure services**
(no I/O) so they are deterministic and unit-testable:

- `owner` — the multi-user seam (everything scoped by `ownerId`; v1 has one owner).
- `species` — read-only access to seeded curated records (record JSON + bilingual brief).
- `cities` / `weather` — location anchor + Open-Meteo integration. `cities` also exposes a
  geocoding search proxy over Open-Meteo (free, no key) so the UI never asks for raw coordinates.
  `weather` is generalized to fetch by arbitrary location (`forLocation(key, lat, lng)`), with
  `forCity` as a thin wrapper — this lets the moving simulation price an unsaved destination.
- `places` — user-built environment profiles; resolves effective conditions (hybrid indoor model
  with a real-signal/outdoor-fallback chain — see `docs/care-engine.md`). The indoor temperature
  range and `Place.humidityCharacter` are now **optional/nullable**; when absent the place falls
  back to real outdoor weather, and the create form nudges the owner to supply them.
- `plants` — plant instances (species + place + pot + history); also serves the per-plant care
  read model (today's tasks + viability) used by the web plant page.
- `scheduling` — the scheduling engine (due dates = base × modulators), recomputed by a cron and
  on app boot.
- `viability` — the informative compatibility semaphore. The actual computation is one shared pure
  function, `buildViability`, used by **both** the moving simulation and the per-plant care read
  model — a single source of truth, never forked.
- `feedback` — action/postpone/symptom ingestion + plan adaptation (now including convergent
  early-watering learning — see `docs/care-engine.md`).
- `moving` — what-if simulation + scheduled city switch, both keyed by raw coordinates.
- `notifications` — surfaces due tasks (v1: in-app, behind a channel interface).

### Startup recompute hook

On app boot the API first applies any **due scheduled moves**; then — **only if zero moves were
applied** — it recomputes the whole garden once (a move already recomputes everything, so this
avoids doing it twice). The daily 05:00 cron is unchanged; the boot hook just makes a freshly
started instance immediately consistent.

## HTTP API surface

Owner-scoped endpoints resolve the single v1 owner server-side; public reference endpoints are not
owner-scoped. Dates are `YYYY-MM-DD` strings, and the "today" day boundary is computed **per plant**
from the timezone of that plant's place-city (not a single primary city). The `isPrimary` flag still
exists, used only by Moving as the garden's "current location".

**Friendly naming:** the colloquial common name is the **primary human-facing name** across the app,
shown with the scientific name in small italic parentheses (e.g. **Lengua de suegra**
*(Dracaena trifasciata)*). The scientific name stays the curation key; the common name is what the
owner reads. To avoid per-card N+1 lookups, the API includes both the **primary common name** and
the **scientific name** (derived once via the schema's `primaryCommonName` helper) on every naming
surface the web reads: the **plant list**, **plant detail**, the **species list**, and the **moving
simulation** response. Today/care payloads are intentionally not enriched (they cross-reference
list/detail, so adding the fields would only be never-read bloat).

| Method & path | Auth | Scope | Purpose |
|---|---|---|---|
| `POST /auth/login` | public | — | `{ username, password }` → `{ token, user: { username, role } }`. |
| `POST /auth/logout` | bearer | — | Revokes the caller's current token (`jti` added to blocklist). |
| `GET /auth/me` | bearer | — | Returns `{ username, role, actingAs: { ownerId } \| null }` of the current actor (`actingAs` reports the resolved impersonation state). |
| `GET /owners` | bearer | admin | Admin-only picker source for "Acting As" (403 for a USER). `[{ ownerId, username, role }]` (`role` is `null` for an owner with no linked user). Not owner-scoped — it *is* the picker; safety is the role gate. |
| `GET /species` | public | — | Lightweight catalog `{ slug, scientificName, commonName }[]` consumed by the blog index and the "add plant" dropdown. |
| `GET /species/:slug/brief` | public | — | `{ slug, scientificName, commonNames, briefEs, briefEn }`. `404` on unknown slug. |
| `GET /species/:slug` | bearer | — | Full curated record (care data). Protected to minimise the public surface. |
| `GET /plants/:id/care` | bearer | owner | Per-plant care read model: `{ plantId, tasks: [{ task, nextDueOn, daysUntilDue, status: 'overdue'\|'today'\|'upcoming' }], viability: { level: 'good'\|'caution'\|'poor', reasons: string[] } }`. Lazily recomputes the due cache if empty. |
| `PATCH /plants/:id` | bearer | owner | Body `{ nickname?, placeId? }`. Edits the plant's nickname (empty → cleared) and/or place. A place change recomputes the plant; the target place must belong to the plant's owner. |
| `GET /plants/:id/viability-preview?placeId=` | bearer | owner | Read-only projected viability of the plant as if it lived in the given place. Used by the web edit modal before confirming a move. Writes nothing. |
| `PATCH /places/:id` | bearer | owner | Body `{ name?, climateControlled? }`. A `climateControlled` change recomputes every plant in the place; a name-only change does not. |
| `GET /cities/search?q=` | bearer | — | Open-Meteo geocoding proxy → `CitySearchResult[]`. Not owner-scoped (public reference data) but still login-gated. Degrades to `[]` on error. |
| `POST /moving/simulate` | bearer | owner | Body `{ latitude, longitude }` → `PlantViability[]`, each carrying `placeCityName` + `inPrimaryCity`. Normally only the plants at the current (primary) city; **empty-primary fallback:** if the primary holds none of the owner's plants, it returns **all** the owner's plants (off-primary ones flagged `inPrimaryCity: false`) so the UI can warn per plant. Writes nothing. |
| `POST /moving/schedule` | bearer | owner | Body `{ name, latitude, longitude, timezone, moveOn }`. Find-or-creates the destination City, then schedules the move. |

## Authentication / login wall

All owner-scoped surfaces require a logged-in user. Only the blog (`/blog`, `/blog/:id`) and the minimal public API surface below are reachable without authentication.

### Identity model

A new `users` table holds credentials and role (`USER` / `ADMIN`); it is 1:1 with `Owner` via a unique `owner_id` FK. Resource tables (`City`, `Place`, `Plant`, `ScheduledMove`) are **unchanged** — they remain anchored to `Owner` rows as before. A new `revoked_tokens` table is the logout blocklist (indexed by `expires_at` so stale rows can be purged).

### Tokens

JWTs signed with `JWT_SECRET` (≥ 32 chars), TTL `JWT_EXPIRES_IN` (default `30d`). The signed payload carries `userId`, `ownerId`, `role`, and a unique `jti`. Because the TTL is long, **real logout** is achieved by inserting the `jti` into `revoked_tokens`; the global guard checks the blocklist on every request (one indexed DB read per request — no user lookup; `userId`/`ownerId`/`role` arrive signed in the token). Expired rows are purged opportunistically on login.

### Request → service identity (`nestjs-cls`)

`nestjs-cls` (AsyncLocalStorage) establishes a per-request store before guards run. The `JwtAuthGuard` (registered as `APP_GUARD` — default-deny) writes the validated actor `{ userId, ownerId, role, jti, exp }` into the CLS store and also attaches it to `req.user`. Every service reads the actor from CLS via `OwnerService`:

- `currentOwnerId()` — replaces the old hardcoded `"default"` lookup; returns the **effective owner** (see below); throws if called outside a request.
- `ownerFilter()` — always returns `{ ownerId: effectiveOwnerId }` (it **never** returns `{}` anymore — see the effective-owner model below).
- `currentRole()` — the **real** token role; drives admin-only gating and is **never** affected by impersonation.

### The effective-owner model + admin "Acting As"

The old "ADMIN sees everything" bypass — where `ownerFilter()` returned `{}` for an admin and reads leaked **every** owner's rows — is **gone** (it was the root cause of the B7 multiple-primaries defect: each owner contributed a primary city, so the admin's personal list showed several "Primary" badges). Owner scoping is now centralized around **one** concept, the **effective owner** — "whose data am I operating on right now":

```
effectiveOwnerId = actingAsOwnerId ?? ownerId
```

- **Default (not impersonating):** the effective owner is your own owner, so **everyone — including admins — defaults to seeing only their own resources.**
- **Acting as X:** the effective owner is X, so you read **and write** X's resources. Your **role never changes** while impersonating — you stay ADMIN, so you can stop or switch targets at any time.

Because `currentOwnerId()` and `ownerFilter()` both return the effective owner, every owner-scoped service (plants, places, cities, feedback, notifications, care-plan, moving) inherits the model without per-service edits. The **only** extra privilege an admin retains is the ability to set `actingAsOwnerId` (via the role-gated header below).

**How impersonation is carried (BFF sealed session + role-gated header):** identity stays in the JWT (unchanged); the "who am I viewing" state lives in the BFF's existing sealed server-side session as a top-level `actingAs` field (client-visible so the UI can render its banner). The Nuxt proxy forwards it to the API as an `X-Act-As-Owner: <ownerId>` request header. The `JwtAuthGuard` honors that header **only when the real token role is ADMIN** (a USER's header is ignored — no escalation), it validates that the target owner exists (a cheap PK lookup performed only while the header is present; unknown owner → controlled `ForbiddenException`/403, never a later FK/500 on the next create), and it stamps `actingAsOwnerId` onto the request actor. A fresh login always starts as yourself, "Stop acting as" returns you to yourself, and logout clears everything.

Remaining per-operation-kind rules (unchanged in spirit, now all keyed off the effective owner):

- **Reads (list/single):** `where: { ...ownerFilter(), ... }` — scoped to the effective owner.
- **Single-row mutations:** first resolve the target row with `ownerFilter()` (access check), then mutate by `id`.
- **Per-owner sweep mutations** (e.g., `makePrimary` resets all cities of one owner): derive the sweep scope from the **target resource's `ownerId`**, so a sweep only ever touches that owner's rows.
- **Creation:** the new resource is stamped with the effective owner's `ownerId`; create-time FK validation (e.g., a new plant's `placeId`) also checks against the effective owner to prevent cross-owner dangling relations.
- **`CarePlanController.recompute()`:** scopes to the **effective owner** (your own garden by default, the target's while acting-as). The all-owners recompute is **no longer reachable over HTTP** — it lives only in the startup/cron path (`applyAllDueMoves → recomputeAll`).

The admin-only `GET /owners` endpoint is the impersonation picker source: it is gated on the **real** role (403 for a USER) and is intentionally **not** owner-scoped (it *is* the picker), selecting only safe user fields (never `passwordHash`). `GET /auth/me` reports the resolved `actingAs` state.

**Frontend surfaces** (admin-only, rendered only for a real ADMIN session — a USER 404s on the page and never sees the menu entry): an `/admin/owners` picker page, an account-menu "Switch user" entry, a persistent "Acting as &lt;user&gt;" banner, and a "Stop acting as" control. Starting/stopping hard-reloads the app so every owner-scoped page refetches under the new effective owner.

Users are created only via `npm run user:create` (no HTTP signup).

### System jobs — no actor

System jobs (cron + startup boot hook) run outside any HTTP request and **never call `currentOwnerId()` / `ownerFilter()`**. `MovingService.applyAllDueMoves(now)` iterates `owner.findMany()` and calls `applyDueMovesForOwner(ownerId, now)` for each (per-owner timezone cutoff + `isPrimary` scoped to that owner; each move resolves the current primary **inside its own transaction** and repoints only that old-primary city's outdoor places, so a chain of due moves stays correct), then calls `recomputeAll()` once if any moves applied. `CarePlanService.recomputeAll()` already sweeps all plants with no owner filter. The cron and `StartupService` call `applyAllDueMoves` directly, never `applyDueMovesForOwner`. This is the **only** path that recomputes all owners — the HTTP `POST /care-plan/recompute` is scoped to the effective owner (see the effective-owner model above).

### Public vs protected surface

| Visibility | Endpoints |
|---|---|
| **Public (no auth)** | `POST /auth/login`; `GET /species` (lightweight catalog); `GET /species/:slug/brief` (blog article) |
| **Protected (bearer required)** | Everything else — `GET /species/:slug` (full record), `plants/*`, `places/*`, `cities/*` (including `GET /cities/search` — not owner-filtered, but login-gated), `care-plan/*`, feedback, `moving/*`, `auth/logout`, `auth/me`, and the admin-only `GET /owners` |

### Web BFF (browser ↔ Nitro only)

The browser never holds the JWT. `nuxt-auth-utils` seals the token inside an `httpOnly` session cookie under the **`secure`** sub-key (server-only; never serialized to the client). Nitro server routes handle login, logout, and a `me` check; a generic catch-all proxy (`server/api/[...].ts`) forwards every other request to the NestJS API, attaching `Authorization: Bearer <token>` from the session. When the session carries an `actingAs` target (set by the admin via `POST /api/acting-as` and cleared by `DELETE /api/acting-as`), the proxy also forwards `X-Act-As-Owner: <ownerId>`. The set/clear routes resolve the target label **server-side** and require a real ADMIN session; clearing rebuilds the session passing `actingAs: null` explicitly (the nuxt-auth-utils/h3 `defu` merge would otherwise let a stale `actingAs` survive), so a fresh login, a stop, and a logout all reliably drop impersonation. `useApi` targets the same-origin proxy (`/api${path}`) and uses `useRequestFetch()` during SSR so the sealed session cookie is forwarded on server-side renders.

## One data store (local MariaDB)

- **Curated species knowledge** lives in the `species` table — the structured `record` (JSON)
  plus the human-readable brief in both English and Spanish (`brief_en` / `brief_es`, Markdown),
  all written by the knowledge engine's deterministic `db:insert` (the single writer). The
  `record` includes an **informational `cultivars`** list (named varieties such as 'Massangeana'
  — identity/appearance for humans, never care overrides), so the deterministic care engine never
  branches on cultivar. The DB is the **single source of truth**; the files Claude generates
  during research are ephemeral drafts, never committed. Before researching, the engine reads the
  catalog (`db:list`) and one species' full data (`db:find`) to judge — critically — whether the
  species already exists, and if so enriches the stored record + brief instead of duplicating it.
- **App transactional data:** the same local MariaDB via Prisma, assembled from separate `DB_*`
  env vars (never a connection string). Date/time handling follows the MariaDB rule in the
  constitution. Recent migrations: **0004** makes `Place.humidityCharacter` nullable (so "not
  provided" is representable and the outdoor fallback can apply); **0005** adds a `MIST` value to
  the `Task` enum. Because `DueCache`, `TaskOverride`, `PlantTaskAdjustment`, and `CareEvent` are
  all keyed by `Task`, the misting cycle inherits Done/Postpone/anchoring support automatically.

## Build order

`my-plants-species-schema` → `my-plants-knowledge-engine` → `my-plants-api` → `my-plants-web`.
See `docs/mvp-roadmap.md`.
