# MVP Roadmap — MyPlants

Build order follows the dependency chain: the contract first, then its producers, then the
consumers. Each phase is its own spec → plan → implementation cycle.

## Phase 1 — `my-plants-species-schema` (the contract)

The shared Zod schema + inferred types + validators. Nothing else can be built correctly
until the curated species-record shape is fixed. Delivers a buildable, tested package
consumed by everything downstream.

## Phase 2 — `my-plants-knowledge-engine` (produces the data)

The Claude-driven research workspace: `CLAUDE.md` runbook + `plant-researcher` subagent +
deterministic `validate`/`save` scripts. Delivers the ability to turn a scientific name into
a validated `record.json` + `brief.md`, and a starting set of curated species.

## Phase 3 — `my-plants-api` (the deterministic care engine)

NestJS + Prisma over local MariaDB. Owner seam, species seeding, cities/weather, places,
plants, and the pure engines: scheduling, viability semaphore, feedback adaptation, moving.
Delivers the full care logic over an API.

## Phase 4 — `my-plants-web` (the daily experience)

Nuxt 3 + Vue + Nuxt UI. Today's tasks, plant/place management, feedback capture, the
viability semaphore, and the moving module — consuming the API.

## Phase 5 — MVP enrichment (done, 2026-06-21)

A cross-repo polish pass over the working MVP, in four sub-phases (no DB schema changes, no new
migrations, no new env vars):

- **A — care loop:** convergent early-watering learning (the `earlyLateRatio` signal is now active;
  see `docs/care-engine.md`), the mark-Done flow with today-default + optional back-date, and a
  startup recompute hook (apply due moves on boot, then recompute the garden if none applied).
- **B — environment:** an Open-Meteo geocoding city-search proxy (`GET /cities/search`) and a
  reusable `CitySearch` web component, so cities + moving never ask for raw coordinates; the places
  form exposes the indoor-only optional environmental fields.
- **C — viability:** the viability rules extracted into one shared pure `buildViability` engine used
  by both moving and the new per-plant care read model (`GET /plants/:id/care`), surfaced as a
  viability badge on the plant page.
- **D — blog:** a species brief endpoint (`GET /species/:slug/brief`) and a web Blog section
  (`/blog`, `/blog/:id`) that renders the Spanish brief as plain text (no Markdown parsing this
  iteration).

## Deferred (not in the MVP)

- AI photo diagnosis inside the feedback loop.
- Multi-user accounts (the seam exists from Phase 3; real accounts come later).
- `docs/api/` + Postman collection (created once the API is real and functional).
- Production deploy flow.
