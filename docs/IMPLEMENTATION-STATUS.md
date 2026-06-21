# MyPlants — Implementation Status & Handoff

**Date:** 2026-06-21
**State:** All four phases implemented and tested green; the **MVP-enrichment pass (phases A–D)** is
now implemented on top (branch `feature/mvp-enrichment` in the submodules). No DB schema changes, no
new migrations, no new env vars. Left **shut down** (nothing running).

## What exists

Four local subrepos under `repos/` (each a standalone git repo with full commit history):

| Repo | What it is | Status |
|---|---|---|
| `repos/my-plants-species-schema` | Shared Zod contract + types + `toSpeciesSlug` | ✅ 28 unit tests, builds to `dist/` |
| `repos/my-plants-knowledge-engine` | Claude-driven research workspace (runbook + scripts + `db:insert`) | ✅ 5 unit tests; 2 species curated |
| `repos/my-plants-api` | NestJS + Prisma/MariaDB deterministic care engine | ✅ 32 unit tests + e2e green |
| `repos/my-plants-web` | Nuxt 3 + Vue + Nuxt UI frontend | ✅ util tests + typecheck + build green |

**Curated data already in the DB:** 2 species — *Nephrolepis exaltata* (Boston fern) and
*Dracaena fragrans* (corn plant), both `confidence: high`, researched by Claudex via the
knowledge-engine runbook and inserted with `npm run db:insert`. **All instance data (cities/
places/plants) was wiped after testing**, so you start from a clean slate with the species ready.

## MVP-enrichment pass (phases A–D, 2026-06-21)

A cross-repo polish pass over the working MVP. **No DB schema changes, no new migrations, no new env
vars** — so the run/setup steps above are unchanged. What it added:

- **A — care loop.** The care engine now **learns from early waterings**: late/postponed waterings
  do not change the interval (that's what Postpone is for), early waterings shorten it with reduced
  gain (`EARLY_GAIN = 0.15`); the loop is convergent and confidence-gated (nudges only when at least
  `minSamples`, default 2, recent eligible cycles are early **and** the newest is early, using the
  newest cycle's ratio — not a re-applied average — so it settles at the owner's true rhythm).
  Adherence per cycle is persisted in the existing `CareEvent.payload` JSON (no migration), exactly
  one nudge per eligible cycle. Plus a **startup recompute hook** (apply due moves on boot, then
  recompute the garden only if none applied; the 05:00 cron stays).
- **B — environment.** `GET /cities/search?q=` (Open-Meteo geocoding proxy, free/no key, degrades to
  `[]` on error) + a reusable web `CitySearch` component (cities and moving use the Open-Meteo bank,
  no manual coordinates). The places form exposes the indoor-only optional environmental fields.
- **C — viability.** Viability rules extracted into one shared pure `buildViability` engine, used by
  **both** moving and the new `GET /plants/:id/care` read model; the plant page shows a viability
  badge. `WeatherService` generalized to `forLocation(key, lat, lng)` with `forCity` as a thin
  wrapper. `POST /moving/simulate` now takes `{ latitude, longitude }`; `POST /moving/schedule` takes
  `{ name, latitude, longitude, timezone, moveOn }` and find-or-creates the destination City by
  coordinates rounded to 4 decimals.
- **D — blog.** `GET /species/:slug/brief` → `{ slug, scientificName, commonNames, briefEs, briefEn }`
  (`commonNames` read from the species `record` JSON, `404` on unknown slug) + a web Blog section at
  `/blog` and `/blog/:id` rendering the Spanish brief as plain text (no Markdown parsing this
  iteration).

The full API surface and engine behavior are documented in `docs/architecture.md` and
`docs/care-engine.md`.

## Verified end-to-end (qa-engineer, real browser)

Create city → place → plant → see today's tasks → mark Done / Postpone → Moving simulation.
The core flow passed. Two QA findings were fixed: Moving now shows `speciesSlug` when a plant
has no nickname; CORS is restricted to the web origin. (Viability `reasons` is empty for a
"good" fit by design — reasons appear only for caution/poor.)

## How to run it (local; nothing is running now)

Prerequisites: local MariaDB up (it is), database `myplants`, user `myplants`, password `123`.

**Easiest — both services from the workspace root:**
```bash
./run.sh          # API (8000) + web (8001), prefixed output
```
The API loads its own `.env` automatically (via dotenv) — no manual `source` needed. Just make
sure `repos/my-plants-api/.env` exists (copy it from `.env.example` the first time).

**Or each service on its own:**
```bash
cd repos/my-plants-api && npm run build && node dist/main.js   # → http://localhost:8000
cd repos/my-plants-web && npm run dev                          # → http://localhost:8001
```

Open http://localhost:8001 and create a City → Place → Plant; the Today page shows the computed
care tasks. To stop: Ctrl-C on `./run.sh`, or `pkill -f "my-plants-api/dist/main"; pkill -f nuxt`
(the broader `dist/main` pattern matches both the `./run.sh`/watch launch and `node dist/main.js`).

**Env files (API):** `.env` holds the app config (`DB_*`, `PORT`, `DEFAULT_CITY_TZ`, `WEB_ORIGIN`)
and is loaded automatically. Prisma's composed `DATABASE_URL` is generated into `prisma/.env` by
`npm run prisma:env` (kept separate so it never clobbers the app's `.env`). Only `.env.example` is
tracked.

## Adding more species (knowledge engine)

Open a Claude session **inside `repos/my-plants-knowledge-engine`** (it has its own `CLAUDE.md`
runbook), give it a scientific name, and follow the workflow; its final step,
`set -a; source .env; set +a && npm run db:insert`, upserts into the `species` table. (Copy
`.env.example` → `.env` first; it already has the local DB creds.)

## Deliberate deviations from the plans (decided + documented)

- **GitHub submodules (done 2026-06-19).** The four product repos are public on GitHub under
  `RetaxMaster` and registered as git submodules of the `RetaxMaster/my-plants` workspace; the
  workspace pins each one's pushed commit. Clone with `git clone --recurse-submodules`.
- **Prisma `migrate deploy` (not `migrate dev`).** The `myplants` user lacks the global `CREATE`
  privilege Prisma's shadow DB needs; the migration SQL was generated with `prisma migrate diff`
  and applied with `migrate deploy`. `package.json` reflects this (`prisma:migrate` = deploy;
  `prisma:migrate:dev` kept for when global CREATE is granted).
- **Vitest e2e uses `unplugin-swc`** so NestJS decorator metadata is emitted (esbuild drops it).
- **CORS** is restricted to `http://localhost:8001` (env `WEB_ORIGIN`). **No auth yet** —
  intentional for single-user local v1; real auth arrives with multi-user (roadmap).

## Deferred (roadmap, unchanged)

AI photo diagnosis; multi-user accounts (+ auth); email/push notification channels; the
production deploy flow (`docs/deploy.md` intentionally absent); the `docs/api/` + Postman
collection (create once you want to publish the API surface).
