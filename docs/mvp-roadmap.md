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

## Phase 6 — Authentication / login wall (done, 2026-06-21)

A login-gated deployment prerequisite across the full stack:

- **API:** JWT auth (signed, 30-day TTL) + server-side revocation blocklist (`revoked_tokens` table). `users` table 1:1 with `Owner` + `UserRole` (USER/ADMIN). The `owner` seam (`OwnerService.currentOwnerId()`) now resolves the per-request actor from `nestjs-cls` (AsyncLocalStorage) instead of the old hardcoded `"default"` owner. Ownership enforced per operation kind (reads widen for ADMIN; per-owner sweeps derive scope from the target resource; creation stamps the actor's `ownerId`). System jobs (`applyAllDueMoves`, `recomputeAll`) are owner-agnostic and never read the CLS actor. Users created only via `npm run user:create`.
- **Web (BFF):** The browser talks only to the Nuxt server (Nitro); the JWT is sealed in an `httpOnly` session cookie under `nuxt-auth-utils`' server-only `secure` key (never exposed to browser JS); Nitro proxies all API calls attaching the bearer. Login page, logout action, global route guard, and SSR cookie forwarding via `useRequestFetch()`.
- **Public surface:** `POST /auth/login`, `GET /species`, `GET /species/:slug/brief`. Everything else is protected, including `GET /cities/search`.

Migration **0006** adds `users` and `revoked_tokens`. New env vars: `JWT_SECRET`, `JWT_EXPIRES_IN` (API); `NUXT_SESSION_PASSWORD`, `NUXT_API_BASE` (web).

## Phase 7 — Editing + per-plant cutoff + honest Moving (done, 2026-06-21)

Editing surfaces and honest location semantics (no DB migration — all fields already existed):

- **Plant editing:** `PATCH /plants/:id` (nickname/place) with a read-only `GET /plants/:id/viability-preview` so the web shows the projected viability semaphore before confirming a move. A place change recomputes the plant.
- **Place editing:** `PATCH /places/:id` (name/climateControlled); a climate-controlled change recomputes every plant in the place.
- **Per-plant day cutoff:** the "today" boundary now derives from each plant's place-city timezone instead of the owner's primary city. `isPrimary` stays, used only by Moving.
- **Honest Moving:** `simulate`/`apply` scope to the plants/places at the current (primary) city; `apply` resolves the old primary per-move (chain-safe) and repoints only its outdoor places.
- **Web:** edit modals on the plant detail page (with preview) and the places list.
- **Frontend redesign:** the web UI was rebuilt on an in-house design system imported from Claude Design (CSS tokens + reusable Vue components), replacing Nuxt UI/Tailwind. Adds light/dark mode, a responsive auth-aware nav (desktop top row, mobile bottom bar + More), and self-hosted fonts/icons (offline). i18n deferred (strings stay English in place).

## Phase 8 — Admin "Acting As" + honest-moving fallback (done, 2026-06-22)

Two pre-existing backend defects surfaced during the Phase 7 frontend-redesign QA (B7, B8), now fixed (no DB migration — no schema change):

- **B7 — effective-owner model + admin "Acting As":** the old "ADMIN sees everything" (`OwnerService.ownerFilter()` returned `{}` for admins, leaking every owner's rows and showing multiple primary cities) is **removed**. Owner scoping is centralized on a single concept, the **effective owner** (`actingAsOwnerId ?? ownerId`), so admins now default to their own resources. Cross-owner reach comes **only** from explicit impersonation: the target lives in the BFF sealed session, the Nuxt proxy forwards it as `X-Act-As-Owner`, and the `JwtAuthGuard` honors it only for a real ADMIN token (validates the owner exists → 403 otherwise; the gating role is always the real token role). New admin-only `GET /owners` picker; `GET /auth/me` now reports `actingAs`. Web: an admin-only `/admin/owners` page + account-menu "Switch user" entry (neither renders for a USER), a persistent "Acting as &lt;user&gt;" banner, and "Stop acting as"; start/stop hard-reload so every owner-scoped page refetches.
- **B8 — honest-moving fallback:** `POST /moving/simulate` no longer returns `[]` when the primary city holds none of the owner's plants — it falls back to all the owner's plants, and each result carries `placeCityName` + `inPrimaryCity` so the UI warns per off-primary plant. Normal behavior (primary has plants → only those) is unchanged. `POST /care-plan/recompute` is re-scoped to the effective owner; the all-owners recompute remains only in the startup/cron path, never over HTTP.

## What's next — production deployment

The login wall is the last prerequisite for a public deployment. **Production deployment is the
next milestone and still needs `docs/deploy.md`** — that document is not defined yet and must
be authored before any deploy work begins (per the workspace constitution). It must cover:
HTTPS/domain setup, production secrets, CORS finalization, where the app runs, migration
gating, and service restart procedure. Do NOT improvise a deploy flow without that doc.

## Deferred (not in the MVP)

- AI photo diagnosis inside the feedback loop.
- Postman collection (the Markdown API collection now lives in `docs/api/README.md`; a Postman export is still deferred).
- Multi-user self-service (the seam exists; real multi-tenancy comes later — single real user for now).
- Production deploy flow (see above — needs `docs/deploy.md` first).
