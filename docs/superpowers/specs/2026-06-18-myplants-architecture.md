# MyPlants — Architecture Spec

**Date:** 2026-06-18
**Status:** Approved architecture (pre-planning)
**Companion to:** `2026-06-18-myplants-design.md` (conceptual design — the *what*). This
document is the *how*: stack, repository topology, module decomposition, data flow, and
the contracts that hold the two subsystems together. Together, both specs are the input
to the implementation plans (one plan per subsystem).

All technical choices below are decided here on purpose; the planning phase consumes them
without re-opening them.

---

## Guiding constraints (from the design)

1. **Two subsystems, one data contract.** The knowledge engine *produces* curated species
   data; the care app *consumes* it. The contract between them must have a single source of
   truth so it cannot drift.
2. **Single user now, modular for multi-user later.** Everything in the app is scoped by an
   owner from day one, even though only one owner exists.
3. **Deterministic care app in v1.** No runtime AI, no external AI keys in the app. AI lives
   only in the knowledge engine. (Future: AI photo diagnosis — kept out of v1.)
4. **Care is computed, never stored as a fixed calendar.** Scheduling, viability, and
   feedback adaptation are pure, testable computations.

---

## Language and runtime

- **TypeScript everywhere.** Consistent with the existing `retaxmaster-workspace`
  ecosystem and the user's full-stack TS background.
- **Node.js LTS.** Scripts run via `tsx` (matching `resume-optimizer`'s convention).

---

## Repository topology: a git workspace with subrepos (submodules)

MyPlants is a **git workspace with subrepos**, mirroring the existing
`retaxmaster-workspace` convention: a root git repository that holds shared docs, a
developer `CLAUDE.md`/`AGENTS.md`, workspace scripts, and a `repos/` directory whose
subsystems are **git submodules** — each its own independent repository.

```
my-plants/                       # root git repo (workspace)
  CLAUDE.md / AGENTS.md          # developer guide for the workspace
  README.md
  docs/                          # shared specs + plans (this file lives here)
  .code-workspace                # editor multi-root workspace
  .gitmodules                    # registers the subrepos below
  repos/
    my-plants-species-schema/    # SUBREPO: shared contract (Zod schema + types + validators)
    my-plants-knowledge-engine/  # SUBREPO: Claude research workspace (its own CLAUDE.md)
      .claude/agents/            #   research subagent(s)
      scripts/                   #   deterministic tools (validate, write record/brief, fetch)
      species/                   #   curated OUTPUT: <slug>/record.json + <slug>/brief.md
    my-plants-api/               # SUBREPO: NestJS backend
    my-plants-web/               # SUBREPO: Nuxt 3 frontend
```

All four submodules are public GitHub repositories under the `RetaxMaster` account, each
prefixed `my-plants-` (mirroring the workspace name; the term "care app" below is a
functional description, not a repo name).

**Keeping the shared contract from drifting across subrepos.** The species schema is a
contract shared by both subsystems, and the hardest-won lesson from past projects is that
*parallel copies of one surface drift apart*. Because the subsystems are independent repos,
`species-schema` is published and consumed as a **single versioned dependency** (a pinned
git dependency / internal package), never copy-pasted. There is exactly one definition of
the contract; consumers pin a version and a schema change is a deliberate version bump
applied to every consumer in the same change. This preserves the no-drift guarantee within
the subrepo model.

---

## The shared contract: `species-schema`

- A standalone **subrepo**, published and consumed as a single versioned dependency,
  exporting a **Zod schema** for a curated species record, the
  **TypeScript types** inferred from it, and validation helpers.
- Zod is chosen because it validates at runtime *and* derives static types from the same
  definition — one declaration is both the gate and the type. The knowledge engine uses it
  to validate before writing; the app uses it to validate on load. Single source of truth,
  zero drift.
- The schema encodes the design's care parameters and tolerances: watering (base interval +
  response to temperature/light/season, soil-dryness preference, drought tolerance), light
  (min/ideal/max), temperature (survival min / ideal range / max), humidity (min/ideal),
  fertilizing (active seasons, in-season frequency, dormancy), repotting (interval + signs),
  maintenance (pruning, rotation, leaf-cleaning, common pests), native climate/hardiness,
  and metadata (scientific name, common names, confidence, cited sources, brief reference).

---

## Subsystem 1 — Knowledge engine

A `resume-optimizer`-style workspace. A `CLAUDE.md` runbook teaches a fresh Claude the
species-onboarding workflow; it orchestrates a research subagent (non-deterministic) and
deterministic scripts.

- **Non-deterministic tool:** a `.claude/agents/` **research subagent** that gathers from
  configured trusted APIs + public web (Claude's web-reading tools), critically evaluates
  source veracity, cross-checks, flags uncertainty, and synthesizes a draft record + brief.
  Like `resume-optimizer`'s curator, it is treated as handling untrusted web content and is
  hardened against prompt injection (it classifies content, never obeys it).
- **Deterministic scripts (`scripts/`, run via `tsx`):**
  - `validate` — validate a species record against `species-schema` (the gate before save).
  - `save` / writer — write `species/<slug>/record.json` + `species/<slug>/brief.md`.
  - fetch helpers for the configured trusted APIs.
- **Output artifacts:** `species/<slug>/record.json` (the curated row) and
  `species/<slug>/brief.md` (the informative blogpost). Committed to the repo — the curated
  knowledge is version-controlled and reviewable in diffs.
- **Entry point:** operator gives a scientific name and triggers research; the workflow ends
  by validating and saving both artifacts.

---

## Subsystem 2 — Care app

### Stack

- **Backend — NestJS (`my-plants-api`).** NestJS's first-class **module system** maps
  directly onto the design's domain modules and gives clean, injectable boundaries — exactly
  the structure needed so multi-user is an additive change rather than a rewrite. It also
  ships `@nestjs/schedule` for the recompute cron and is the natural home for the future
  runtime-AI module without disturbing the rest.
- **Frontend — Nuxt 3 + Vue 3 (`my-plants-web`)** with **Nuxt UI** for accessible components
  and **`<script setup>` + TypeScript**. PWA-capable, which leaves the door open for push
  notifications later. Talks to the API over REST.
- **Persistence — Prisma ORM over local MariaDB (no Docker).** A MariaDB server running
  directly on the host (not containerized). Prisma uses its MySQL provider, which is
  MariaDB-compatible. The same engine scales to multi-user later with no migration.
  - **Connection via separate env vars, never a connection string.** The config exposes
    `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, and `DB_NAME` as independent variables.
    The Prisma `DATABASE_URL` is **assembled internally at bootstrap** from those parts
    (built in config and passed to `PrismaClient` via a `datasources` URL override) — the
    connection string is never authored or stored by hand.
  - **MariaDB date/time guard (critical for the date-heavy scheduling engine).** Never
    compare date/time columns against `toISOString()` strings: MariaDB ignores the trailing
    `Z` and may parse them in the session timezone, silently shifting due-date thresholds by
    the UTC offset. Bind native `Date` objects (let the ORM stringify them in the connection
    timezone) or use the DB's own `NOW()`. The connection timezone is fixed explicitly.
- **Weather — Open-Meteo.** Free, no API key required (keeps the app secret-free and
  deterministic), and exposes temperature/humidity by latitude/longitude with forecast and
  historical data — everything the scheduling and viability engines need.
- **Notifications (v1) — in-app.** The web surfaces "today's tasks." Delivery is behind a
  `NotificationChannel` interface so email/push are additive later.

### Two data stores, by nature of the data

- **Curated species knowledge** = the file-based `record.json` + `brief.md` produced by the
  engine (version-controlled, PR-reviewable, slow-growing). A deterministic **seed/sync**
  step loads these records into the app DB so the app can query species uniformly; the
  committed files remain the source of truth, the DB rows are a read cache.
- **App transactional data** (owners, plants, places, cities, care history, feedback,
  schedules) = local MariaDB via Prisma — mutable, per-owner, queried constantly.

### NestJS module decomposition

Each module is a clear, independently testable unit. Domain engines are **pure services**
(no I/O) so they are deterministic and unit-testable.

- **`owner`** — the multi-user seam. Every record carries an `ownerId`; v1 resolves a single
  default owner. Auth is stubbed behind an interface so real accounts drop in later.
- **`species`** — read-only access to the seeded curated records (the contract boundary).
- **`cities`** — a plant garden's anchor location (lat/lon) for weather.
- **`weather`** — Open-Meteo integration with caching; supplies outdoor temperature/humidity
  and seasonal context.
- **`places`** — CRUD for user-built environment profiles (indoor/outdoor, light type,
  climate-controlled, humidity character, optional indoor temperature range). Resolves a
  place's effective conditions by combining declared traits with weather (hybrid indoor
  model).
- **`plants`** — plant instances (species + place + pot + acquisition date + history).
- **`scheduling`** — the **scheduling engine** (pure service): computes next-due dates per
  task from species parameters × modulators (place/weather/season). A `@nestjs/schedule`
  cron recomputes daily and on weather refresh.
- **`viability`** — the **viability semaphore** (pure service): compares place + city climate
  against species tolerances → an informative compatibility level. Never blocks.
- **`feedback`** — ingests action logs, postponements, and symptom check-ins, and applies
  **plan adaptation** (pure service): one-off postpone shifts the date; repeated postpones or
  consistent early/late actions nudge the base interval; symptoms map to adjustments.
- **`moving`** — reuses `viability` + `weather` for the "what-if" simulator (target city →
  recomputed compatibility + care deltas) and the scheduled move (switch city + variables on
  the chosen date, then recompute the whole garden).
- **`notifications`** — surfaces due tasks; `NotificationChannel` interface (v1: in-app).

### Engine purity and testing

- The scheduling, viability, and adaptation engines are pure functions of their inputs (no
  DB, no clock reads passed in as parameters) → fully unit-testable in isolation.
- Test layers: unit tests for the pure engines, contract tests for `species-schema`, and e2e
  tests for the API. Mirrors `resume-optimizer`'s test discipline.

---

## End-to-end data flow

1. **Onboarding (engine):** scientific name → research subagent drafts → `validate` →
   `species/<slug>/{record.json,brief.md}` committed.
2. **Seed (app):** deterministic sync loads curated records into the app DB (validated by
   `species-schema` on the way in).
3. **Setup (app):** owner defines cities and builds places; registers plant instances
   (species + place). Viability semaphore informs on registration.
4. **Daily runtime (app):** scheduling cron recomputes due dates from species params +
   place/weather; the web surfaces today's tasks; the owner logs actions / postpones /
   reports symptoms; the feedback engine adapts the plan.
5. **Moving (app):** what-if simulation any time; a scheduled move switches the climate
   context and recomputes the garden on the move date.

---

## Build order

1. `species-schema` (the contract everything depends on).
2. `knowledge-engine` (produces the data the app needs) — its own implementation plan.
3. `my-plants-api` + `my-plants-web` — its own implementation plan(s).

## Out of scope (v1)

- Runtime AI in the care app (incl. photo diagnosis).
- Real multi-user accounts (seam only).
- Email/push notification channels (interface only).
- Native mobile apps.
