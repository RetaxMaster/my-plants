# Architecture — MyPlants

This is the living architecture overview. The full rationale lives in
`docs/superpowers/specs/2026-06-18-myplants-architecture.md`; this doc is the quick map kept
in sync as the system evolves.

## Two subsystems, one data contract

MyPlants is two systems of different nature joined only by a shared data contract:

1. **Knowledge engine** (`repos/my-plants-knowledge-engine`) — its product is *data*: the
   curated truth about each species.
2. **Care app** — its product is *a daily experience*: what to do and when. Split into
   `repos/my-plants-api` (NestJS) and `repos/my-plants-web` (Nuxt 3).
3. **Shared contract** (`repos/my-plants-species-schema`) — a Zod schema + inferred types +
   validators; the single source of truth for the curated species-record shape.

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
| Knowledge engine | `tsx` scripts + Vitest; a `plant-researcher` subagent driven by its own `CLAUDE.md` |
| API | NestJS, Prisma ORM over **local MariaDB** (no Docker) |
| Web | Nuxt 3 + Vue 3 + Nuxt UI |
| Weather | Open-Meteo (free, no API key) |

## Care app modules (NestJS)

Domain modules, each an independently testable unit; the engines are **pure services**
(no I/O) so they are deterministic and unit-testable:

- `owner` — the multi-user seam (everything scoped by `ownerId`; v1 has one owner).
- `species` — read-only access to seeded curated records.
- `cities` / `weather` — location anchor + Open-Meteo integration.
- `places` — user-built environment profiles; resolves effective conditions (hybrid indoor model).
- `plants` — plant instances (species + place + pot + history).
- `scheduling` — the scheduling engine (due dates = base × modulators), recomputed by a cron.
- `viability` — the informative compatibility semaphore.
- `feedback` — action/postpone/symptom ingestion + plan adaptation.
- `moving` — what-if simulation + scheduled city switch.
- `notifications` — surfaces due tasks (v1: in-app, behind a channel interface).

## One data store (local MariaDB)

- **Curated species knowledge** lives in the `species` table — the structured `record` (JSON)
  plus the human-readable `brief` (Markdown), both written by the knowledge engine's
  deterministic `db:insert` (the single writer). The DB is the **single source of truth**; the
  files Claude generates during research are ephemeral drafts, never committed. Before
  researching, the engine runs `db:get` (dedupe by deterministic slug) and, if the species
  already exists, enriches the stored record + brief instead of duplicating it.
- **App transactional data:** the same local MariaDB via Prisma, assembled from separate `DB_*`
  env vars (never a connection string). Date/time handling follows the MariaDB rule in the
  constitution.

## Build order

`my-plants-species-schema` → `my-plants-knowledge-engine` → `my-plants-api` → `my-plants-web`.
See `docs/mvp-roadmap.md`.
