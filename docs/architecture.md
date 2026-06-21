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
| Web | Nuxt 3 + Vue 3 + Nuxt UI |
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
owner-scoped. Dates are `YYYY-MM-DD` strings computed in the owner's primary-city timezone.

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
| `GET /auth/me` | bearer | — | Returns `{ username, role }` of the current actor. |
| `GET /species` | public | — | Lightweight catalog `{ slug, scientificName, commonName }[]` consumed by the blog index and the "add plant" dropdown. |
| `GET /species/:slug/brief` | public | — | `{ slug, scientificName, commonNames, briefEs, briefEn }`. `404` on unknown slug. |
| `GET /species/:slug` | bearer | — | Full curated record (care data). Protected to minimise the public surface. |
| `GET /plants/:id/care` | bearer | owner | Per-plant care read model: `{ plantId, tasks: [{ task, nextDueOn, daysUntilDue, status: 'overdue'\|'today'\|'upcoming' }], viability: { level: 'good'\|'caution'\|'poor', reasons: string[] } }`. Lazily recomputes the due cache if empty. |
| `GET /cities/search?q=` | bearer | — | Open-Meteo geocoding proxy → `CitySearchResult[]`. Not owner-scoped (public reference data) but still login-gated. Degrades to `[]` on error. |
| `POST /moving/simulate` | bearer | owner | Body `{ latitude, longitude }` → `PlantViability[]` for the whole garden. Writes nothing. |
| `POST /moving/schedule` | bearer | owner | Body `{ name, latitude, longitude, timezone, moveOn }`. Find-or-creates the destination City, then schedules the move. |

## Authentication / login wall

All owner-scoped surfaces require a logged-in user. Only the blog (`/blog`, `/blog/:id`) and the minimal public API surface below are reachable without authentication.

### Identity model

A new `users` table holds credentials and role (`USER` / `ADMIN`); it is 1:1 with `Owner` via a unique `owner_id` FK. Resource tables (`City`, `Place`, `Plant`, `ScheduledMove`) are **unchanged** — they remain anchored to `Owner` rows as before. A new `revoked_tokens` table is the logout blocklist (indexed by `expires_at` so stale rows can be purged).

### Tokens

JWTs signed with `JWT_SECRET` (≥ 32 chars), TTL `JWT_EXPIRES_IN` (default `30d`). The signed payload carries `userId`, `ownerId`, `role`, and a unique `jti`. Because the TTL is long, **real logout** is achieved by inserting the `jti` into `revoked_tokens`; the global guard checks the blocklist on every request (one indexed DB read per request — no user lookup; `userId`/`ownerId`/`role` arrive signed in the token). Expired rows are purged opportunistically on login.

### Request → service identity (`nestjs-cls`)

`nestjs-cls` (AsyncLocalStorage) establishes a per-request store before guards run. The `JwtAuthGuard` (registered as `APP_GUARD` — default-deny) writes the validated actor `{ userId, ownerId, role, jti, exp }` into the CLS store and also attaches it to `req.user`. Every service reads the actor from CLS via `OwnerService`:

- `currentOwnerId()` — replaces the old hardcoded `"default"` lookup; throws if called outside a request.
- `ownerFilter()` — returns `{ ownerId }` for USER, `{}` for ADMIN (the admin bypass for reads/single-row lookups only — see ownership rules below).

### Ownership enforcement + admin bypass

The rule is per operation kind; a blind `where: {}` swap is unsafe for sweep and create operations:

- **Reads (list/single):** `where: { ...ownerFilter(), ... }` — a USER sees only their rows; an ADMIN sees all.
- **Single-row mutations:** first resolve the target row with `ownerFilter()` (access check), then mutate by `id`.
- **Per-owner sweep mutations** (e.g., `makePrimary` resets all cities of one owner): derive the sweep scope from the **target resource's `ownerId`**, not from `ownerFilter()`, so an ADMIN acting on someone's data only sweeps that owner's rows.
- **Creation:** the new resource is stamped with the actor's `ownerId`; create-time FK validation (e.g., a new plant's `placeId`) also checks against the actor's `ownerId` to prevent cross-owner dangling relations.
- **`CarePlanController.recompute()`:** USER recomputes only their own garden; ADMIN may recompute all.

Users are created only via `npm run user:create` (no HTTP signup).

### System jobs — no actor

System jobs (cron + startup boot hook) run outside any HTTP request and **never call `currentOwnerId()` / `ownerFilter()`**. `MovingService.applyAllDueMoves(now)` iterates `owner.findMany()` and calls `applyDueMovesForOwner(ownerId, now)` for each (per-owner timezone cutoff + `isPrimary` scoped to that owner), then calls `recomputeAll()` once if any moves applied. `CarePlanService.recomputeAll()` already sweeps all plants with no owner filter. The cron and `StartupService` call `applyAllDueMoves` directly, never `applyDueMovesForOwner`.

### Public vs protected surface

| Visibility | Endpoints |
|---|---|
| **Public (no auth)** | `POST /auth/login`; `GET /species` (lightweight catalog); `GET /species/:slug/brief` (blog article) |
| **Protected (bearer required)** | Everything else — `GET /species/:slug` (full record), `plants/*`, `places/*`, `cities/*` (including `GET /cities/search` — not owner-filtered, but login-gated), `care-plan/*`, feedback, `moving/*`, `auth/logout`, `auth/me` |

### Web BFF (browser ↔ Nitro only)

The browser never holds the JWT. `nuxt-auth-utils` seals the token inside an `httpOnly` session cookie under the **`secure`** sub-key (server-only; never serialized to the client). Nitro server routes handle login, logout, and a `me` check; a generic catch-all proxy (`server/api/[...].ts`) forwards every other request to the NestJS API, attaching `Authorization: Bearer <token>` from the session. `useApi` targets the same-origin proxy (`/api${path}`) and uses `useRequestFetch()` during SSR so the sealed session cookie is forwarded on server-side renders.

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
