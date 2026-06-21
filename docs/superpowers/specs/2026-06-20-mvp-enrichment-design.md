# MVP Enrichment — Care Loop, Environment Setup, Plant Viability & Blog

**Date:** 2026-06-20
**Status:** Design (pre-implementation)

## Goal

Enrich the MyPlants MVP with four coherent areas, delivered as **one spec with four phases
(A–D)** and **one implementation plan per phase**. All four phases are implemented in the same
session; the deliverable is the running product with every feature in place.

- **A. Care loop** — the engine learns from *early* waterings, and the owner can mark any task
  done (and postpone) directly from the plant page.
- **B. Environment setup** — cities are chosen from a geocoded city bank instead of hand-typed
  coordinates; places capture every environmental factor the engine already supports.
- **C. Plant viability** — the viability semaphore is shown for a plant in its current place.
- **D. Blog** — a reader section that renders each curated species' Spanish brief.

Plus two cross-cutting additions requested during design:
- City search also powers the **Moving** view (what-if against any searched city).
- A **startup recompute** runs when the API boots (the app lives off locally and is turned on to
  test), after applying any due moves.

## Constraints (inherited, must hold)

- **100 % deterministic** care engine; no runtime AI. Owner-scoped, single-user today.
- **MariaDB date rule:** never compare date/time columns against ISO strings; day differences are
  computed on `@db.Date` values (UTC-midnight) as integer day counts. Bind native dates.
- **No new forks:** shared behaviour (viability mapping, the city-search UI, the geocoding
  client) lives in exactly one place and is reused, never copied.
- `db:insert` remains the only writer of the `species` table; this spec does not write species.
- Local-only; no deploy. Internet is available at runtime (already used for weather).

---

## Phase A — Care loop (learning + mark-done)

### A.1 Learning policy (the product decision)

The scheduling engine already exposes an `earlyLateRatio` lever (observed interval ÷ scheduled
interval) that is currently hard-wired to `1` (inert). This phase feeds it real data under a
deliberately asymmetric, safety-biased policy:

- **Watered late → do nothing.** Treated as forgetfulness/procrastination, not a signal.
  (Lengthening the rhythm is already the Postpone button's job.)
- **Watered early → shorten, with reduced strength.** Treated as the owner's instinct that the
  plant needed water sooner — a weak but real signal.
- **Postponed cycles are excluded** from punctuality learning (the postpone path already adapts
  them; counting them again would double-count).
- **Deadband + minimum samples** prevent reacting to noise or to a single data point.
- **WATER only** in v1. The other tasks are fixed/seasonal cadences where punctuality is not a
  meaningful signal.
- The learned multiplier stays bounded to **[0.5, 2.0]**.

Over-watering risk introduced by "early → shorten" is mitigated by the existing **symptom** path
(`yellow-leaves-wet-soil` etc. lengthen the interval), which remains the corrective backstop.

### A.2 Capturing what was scheduled, and the exact ordering

Today the scheduled interval per cycle is lost (the due cache is overwritten on recompute). We
persist it at DONE time in the care event's existing `payload` JSON column (**no migration**).

`feedback.service.record` must run this **exact combined sequence** for a **DONE** on **WATER**.
The current handler is create-event → delete-override → recompute; the adherence reads MUST be
inserted **before the override is deleted**, because an active override is precisely the signal
that the cycle was postponed (deleting it first would make every cycle look eligible — the exact
double-count A.1 forbids):

1. **Read (before any write):** `previousAnchor` = `occurredOn` of the most recent **prior** DONE
   for `(plant, WATER)` (tie-break `createdAt desc` for same-day events), else `acquiredOn`;
   `scheduledDueOn` = current `DueCache.nextDueOn` for `(plant, WATER)`; `hadOverride` = an active
   `TaskOverride` exists for `(plant, WATER)`.
2. Compute `observedDays = dayDiff(occurredOn, previousAnchor)` and `scheduledDays =
   dayDiff(scheduledDueOn, previousAnchor)`. `eligible = !hadOverride && scheduledDays >= 1 &&
   observedDays >= 1`. If there is no due-cache row, or the guards fail (same-day or back-dated
   DONE making `observedDays < 1`), set `adherence = null` — skip; do not stamp a bogus cycle.
3. **Create** the care event with payload `{ ...clientPayload, adherence }` (merge any client
   payload). Doing this after step 1 keeps `previousAnchor` uncontaminated by the new event.
4. **Delete** the override (existing DONE behaviour).
5. **Adapt** (A.3/A.4) — **only if the just-closed cycle is eligible** (`adherence != null`):
   compute the early signal over the recent window (whose newest entry is therefore *this* cycle)
   and upsert the multiplier. If the closed cycle is **ineligible, skip adapt entirely** —
   otherwise `cycles[0]` would be a prior eligible cycle that already fired its nudge on an earlier
   DONE, re-applying it (the exact double-count the convergent design removes). This guard
   guarantees **exactly one nudge per eligible cycle**.
6. **Recompute** the plant (existing behaviour).

`dayDiff(a, b)` is a **new** helper added to `common/time/local-date.ts`: the integer day count
between two `@db.Date` (UTC-midnight) values, `round((a − b) / 86_400_000)`. Unit-tested; never
touches `toISOString` (MariaDB rule).

`payload.adherence = { previousAnchorOn, scheduledDueOn, observedDays, scheduledDays, eligible }`.

### A.3 The early signal (pure, testable, convergent)

Extract a pure function `computeEarlyRatio(cycles, { deadband, minSamples })` into the engines
layer (e.g. `engines/punctuality.ts`) so it is unit-testable without a database. Input `cycles`
are the recent **eligible** adherence records for `(plant, WATER)` — the most recent **5** DONE
WATER events whose payload carries an eligible `adherence`, **newest first**. Behaviour:

- A cycle is **early** when `observedDays < scheduledDays · (1 − deadband)` (ratio `< 1 −
  deadband`). `deadband = 0.1`.
- **Confidence gate:** act only if at least `minSamples = 2` of the recent cycles are early (never
  react to a single early watering).
- If the gate passes **and the newest cycle is early**, return that **newest** cycle's ratio
  (`observedDays / scheduledDays`, `< 1`). Otherwise return `1` (no change).

The returned ratio is the **newest** cycle's, measured against the schedule that was in effect for
that cycle (which already reflects the current multiplier) — **not** a re-applied average of older
cycles. The window serves only as a confidence gate, never as a value re-summed every event. This
is what makes the loop converge (see A.4). Late/on-time cycles never push the cadence.

### A.4 Engine change (`engines/adaptation.ts`) — a convergent loop

`nextAdjustment` applies an **early-only, reduced-gain** cadence nudge:

- `cadenceNudge = ratio < 1 ? (ratio − 1) · EARLY_GAIN : 0`, `EARLY_GAIN = 0.15` (reduced from the
  previous symmetric `0.3`).
- `postponeNudge` unchanged. Result `clamp(current + postponeNudge + cadenceNudge, 0.5, 2)`.

**Why this converges (and does NOT ratchet to the 0.5 floor):** the nudge is driven by the
*newest* cycle's ratio against the *current* schedule, applied once per DONE. As the multiplier
shrinks, the predicted interval shrinks, so a consistently-early owner's next observed interval
eventually matches the schedule → the cycle stops being early (ratio enters the deadband) → no
further nudge. The loop settles at the owner's real rhythm. The earlier framing (average a sliding
window and re-add it each event) would re-count the same cycles and slide the multiplier to the
floor — **explicitly rejected**.

Call sites:
- **POSTPONE path** (`feedback.service.adapt`): unchanged — `earlyLateRatio = 1` (no cadence) plus
  the recent-postpone count (lengthening preserved).
- **DONE path** (new, WATER only): runs **only when the just-closed cycle is eligible** (the A.2
  step-5 guard — exactly one nudge per eligible cycle). `recentPostpones = 0` (postpones already
  applied on their own events); `earlyLateRatio` = the A.3 value. The **non-pure glue** — fetch
  recent DONE WATER events, parse + filter `eligible` payloads **in JS** (not via MySQL JSON-path,
  which is brittle) — lives in `feedback.service`; the scoring stays the pure A.3 function. Persist
  the multiplier, then recompute.

### A.5 Mark-done UI (frontend)

`/plants/:id` becomes a **care panel** fed by a new read endpoint `GET /plants/:id/care`
(see API contract). For each applicable task it shows the next-due date + status
(overdue/today/in N days) and two actions:

- **Done** — posts `{ task, type: 'DONE', occurredOn }` to the existing feedback endpoint.
  `occurredOn` **defaults to today**; an optional date picker allows back-dating ("I watered it
  yesterday"). The owner never has to set the date for the common case.
- **Postpone** — posts `{ task, type: 'POSTPONED', occurredOn: today, postponeToOn }`.

After any action the panel refetches `GET /plants/:id/care`.

---

## Phase B — Environment setup (cities bank + rich places)

### B.1 City bank via Open-Meteo Geocoding

New endpoint `GET /cities/search?q=<query>` proxies the **Open-Meteo Geocoding API** (free, no API
key — the same provider already used for weather). It returns candidates with enough context to
disambiguate:

`[{ name, country, admin1, latitude, longitude, timezone }]`

- Implemented as a geocoding client in the weather module's style, with graceful failure (returns
  an empty list on network error; the endpoint never throws). Request `language=es`, a small
  `count` (~10).
- The **cities create form** is rebuilt: type a query → pick a candidate → `POST /cities` with
  `{ name, latitude, longitude, timezone }`. The manual latitude/longitude/timezone inputs are
  removed. The stored `name` is a friendly display string (e.g. `"Guadalajara, Jalisco, Mexico"`).
- "Make primary" is unchanged.
- The search UI is a **single reusable component** (used here and in Moving — no fork).

### B.2 Rich places form

The API DTO already accepts every supported field; only the form is incomplete. Rebuild the
places create form:

- **Required:** `name`, `cityId`, `indoor` (indoor/outdoor), `lightType`.
- **Optional, shown only when `indoor = true`** (outdoor places use real weather, so these are
  ignored by the engine): `climateControlled`, `humidityCharacter`, `indoorTempMinC`,
  `indoorTempMaxC`.
- No new environmental factors are introduced (that would require engine changes — out of scope).

---

## Phase C — Plant viability on the plant page

### C.1 Shared viability builder (no fork)

Extract the plant→place→weather → `ViabilityInput` mapping currently inlined in
`moving.service.ts` into a single shared helper (e.g. `engines/viability.ts` gains a
`buildViability(record, place, weather)` or a small `viability` service). Both the Moving
simulation and the new per-plant care endpoint consume it. `assessViability` (the pure rule)
stays as-is.

### C.2 Per-plant care endpoint

`GET /plants/:id/care` returns the read model that powers the plant page:

```
{
  plantId: string,
  tasks: {
    task: Task,
    nextDueOn: string,        // YYYY-MM-DD
    daysUntilDue: number,     // <0 overdue, 0 today, >0 upcoming — computed server-side
    status: 'overdue' | 'today' | 'upcoming'
  }[],                        // applicable tasks, ordered by nextDueOn asc
  viability: { level: 'good'|'caution'|'poor', reasons: string[] }
}
```

- `daysUntilDue` / `status` are computed **on the backend** against the owner's primary-city
  timezone (`startOfTodayUtc(tz)` vs `nextDueOn`), so the client never subtracts a UTC-midnight
  date from a local `now` (avoids the off-by-one near midnight). The frontend just renders.
- Tasks come from the due cache, ordered `nextDueOn asc`. If the cache is **empty** for the plant
  (e.g. created before any recompute — `plants.service.create` does not recompute), the endpoint
  **recomputes that plant on demand** before reading, so the page is never spuriously empty.
- Viability is computed against the plant's **own** city weather (current place), reusing the
  shared builder. The frontend renders the existing `ViabilityBadge` at the top of `/plants/:id`.
- The endpoint is **owner-scoped** (like `plants.service.get` / `recomputePlant`) — a plant id
  outside the current owner yields a not-found.

---

## Phase D — Blog

### D.1 Expose the brief

New endpoint `GET /species/:slug/brief` → `{ slug, scientificName, commonNames, briefEs, briefEn }`.
`slug`, `scientificName`, `briefEs`, `briefEn` are columns on the `species` table; **`commonNames`
is NOT a column** — it lives inside the `record` JSON, so the endpoint reads it via
`parseSpeciesRecord(row.record).commonNames`. The existing `GET /species/:slug` (which returns the
care *record*) is unchanged. The list endpoint `GET /species` (slug + scientificName) already
exists.

### D.2 Blog pages

- `/blog` — lists supported species from `GET /species` (scientific name, link to detail).
- `/blog/:id` — fetches `GET /species/:slug/brief` and renders **`briefEs` as plain text**,
  preserving line breaks (`white-space: pre-wrap`). **No Markdown parsing** in this iteration
  (the raw text being present is enough for now).
- A **"Blog"** link is added to the app nav.

---

## Cross-cutting: Moving with city search

The Moving view stops being limited to saved cities; it uses the same reusable `CitySearch`
component. The persistence model: **simulate without saving, persist only on schedule.**

- `POST /moving/simulate` accepts a **geocoded target** `{ latitude, longitude }` — no
  `targetCityId`, and **no `timezone`** (simulate only needs coordinates to fetch weather;
  timezone is irrelevant to viability). Returns the same `PlantViability[]`. **Writes nothing.**
- `POST /moving/schedule` accepts the geocoded selection `{ name, latitude, longitude, timezone,
  moveOn }`, **finds-or-creates** the owner's `City`: match on `ownerId` + coordinates **rounded
  to 4 decimals** (floats are never compared for exact equality), create if absent; then create
  the `ScheduledMove`. Persistence happens only on this commit step. A scheduled destination
  therefore appears in `/cities` and becomes primary when the move applies — **intended** (a real
  move needs a real city).
- **Weather by coordinates (no fork):** generalize `WeatherService` to `forLocation(key, lat,
  lng)` reusing the same cache `Map`/TTL; `forCity(cityId, …)` becomes a thin wrapper with
  `key = cityId`, and ad-hoc targets use `key = "<lat>,<lng>"`. Do **not** copy the fetch+cache
  logic. (Note: ad-hoc keys make the in-memory cache unbounded across distinct searched
  coordinates — acceptable for local single-user; add simple eviction only if it ever matters.)
- `MovingController` `SimulateDto` / `ScheduleDto` and the frontend `useApi.simulateMove` /
  `scheduleMove` (today keyed by `targetCityId`) are updated to the new bodies.

## Cross-cutting: Startup recompute

A startup hook (`OnApplicationBootstrap` in a small startup provider) runs when the API boots:

1. `applyDueMoves(now)` — applies any move whose date arrived while the app was off (this already
   recomputes the whole garden when it applies at least one move).
2. If no move was applied, `recomputeAll()` — so the owner always sees up-to-date due dates on
   boot.

This mirrors the existing 05:00 daily cron; the cron stays.

---

## API contract additions (summary)

Backend (NestJS):
- `GET /cities/search?q=` → `CitySearchResult[]`.
- `GET /plants/:id/care` → `PlantCare`.
- `GET /species/:slug/brief` → `SpeciesBrief`.
- `POST /moving/simulate` body changes to `{ latitude, longitude }`.
- `POST /moving/schedule` body changes to `{ name, latitude, longitude, timezone, moveOn }`.

Frontend (`types/api.ts` + `useApi`):
- Types: `CitySearchResult { name, country, admin1, latitude, longitude, timezone }`,
  `PlantCare { plantId, tasks: { task, nextDueOn, daysUntilDue, status }[], viability: { level,
  reasons } }`, `SpeciesBrief { slug, scientificName, commonNames, briefEs, briefEn }`.
- Client: `searchCities(q)`, `getPlantCare(id)`, `getSpeciesBrief(slug)`; updated `simulateMove`
  and `scheduleMove` signatures.
- Reusable `CitySearch` component (cities form + moving); rebuilt plant detail, places form,
  cities form; new `/blog` and `/blog/[id]` pages; nav gains "Blog".

## Testing strategy

- **Unit (pure):** `computeEarlyRatio` (early-only, deadband, min-samples confidence gate, returns
  newest-cycle ratio not a re-applied average); `nextAdjustment` (early reduced gain, ratio ≥ 1 →
  no change, postpone path preserved) **plus a convergence test** — a consistently-early waterer's
  multiplier settles and does NOT slide to the 0.5 floor; the shared viability builder mapping; the
  new `dayDiff` helper on `@db.Date` UTC-midnight values per the MariaDB rule.
- **Backend behaviour:** adherence capture stamps the payload and is skipped for postponed cycles;
  DONE path moves the multiplier only on eligible early cycles. Geocoding client degrades to an
  empty list on failure.
- **Web:** `npm run build` (build + typecheck) stays green.
- **E2E / live QA:** after implementation, delegate to the `qa-engineer` subagent — exercise:
  mark-done from the plant page (default today + back-dated), the viability badge, city search in
  both cities and moving, the rich places form, and the blog pages.

## Phasing & deliverable

Implementation order: **A → B → C → D**, then the two cross-cutting items (Moving search depends
on B's city-search component and the geocoding endpoint; startup recompute is independent). One
implementation plan per phase. The session deliverable is the full product, left locally runnable
via `./run.sh`, with the suite green and an E2E pass.
