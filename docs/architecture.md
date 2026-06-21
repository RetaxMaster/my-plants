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

| Method & path | Scope | Purpose |
|---|---|---|
| `GET /plants/:id/care` | owner | Per-plant care read model: `{ plantId, tasks: [{ task, nextDueOn, daysUntilDue, status: 'overdue'\|'today'\|'upcoming' }], viability: { level: 'good'\|'caution'\|'poor', reasons: string[] } }`. `status`/`daysUntilDue` are computed server-side; if the due cache is empty it lazily recomputes that plant on demand. |
| `GET /cities/search?q=` | public | Open-Meteo geocoding proxy → `CitySearchResult[]` (`{ name, country, admin1, latitude, longitude, timezone }`). Degrades to `[]` on any error. |
| `GET /species/:slug/brief` | public | `{ slug, scientificName, commonNames, briefEs, briefEn }` (`commonNames` read from the species `record` JSON, not a column). `404` on unknown slug. |
| `POST /moving/simulate` | owner | Body `{ latitude, longitude }` → `PlantViability[]` for the whole garden against that location (each entry carries the plant's common + scientific names for the friendly-naming rule). Writes nothing. |
| `POST /moving/schedule` | owner | Body `{ name, latitude, longitude, timezone, moveOn }`. Find-or-creates the owner's destination City by coordinates rounded to 4 decimals, then schedules the move. |

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
