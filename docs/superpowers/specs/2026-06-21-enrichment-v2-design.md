# MVP Enrichment v2 — Editorial Voice, Climate-Driven Care, Misting & Friendly Naming

**Date:** 2026-06-21
**Status:** Design (pre-implementation)

## Goal

Build on the MVP enrichment (wave 1) with a second, coherent wave delivered as **one spec with
seven phases** and **one implementation plan per phase**, all implemented in the same session.
The deliverable is the running product with every feature in place.

The wave bundles three primary requirements plus two refinements requested during design:

- **R1. Editorial voice.** A new `editorial-writer` subagent in the knowledge engine turns the
  researcher's raw English brief into a polished, catchy blogpost in **both English and Spanish**,
  written in one consistent house voice. The `plant-researcher` stops writing Spanish and stops
  chasing style; it now returns a single raw, fact-complete English brief. This unifies the blog's
  tone across species curated in different sessions.
- **R2. Climate-driven watering.** Indoor temperature and ambient humidity now move the watering
  cycle (today the engine forces the temperature modulator neutral indoors and ignores humidity
  entirely). Backed by horticultural evidence: transpiration — and therefore how fast soil dries —
  rises with heat and falls with humidity.
- **R3. Misting cycle.** A sixth care cycle, species-dependent and humidity-gated. Evidence shows
  misting barely raises ambient humidity but is genuinely useful (leaf cleaning, some tropicals)
  and harmful to others (succulents, fuzzy leaves, tight crowns) — so it must be opt-in per species
  and modulated by the place's humidity.
- **Refinement A. Permissive indoor places.** Indoor temperature range and humidity become
  optional; when absent, the effective conditions fall back to the **real outdoor weather** (the
  only real reading available) rather than a comfort baseline, and the UI shows a gentle alert
  encouraging the owner to provide them.
- **Refinement B. Friendly naming.** The colloquial (common) name becomes the plant's primary name
  across the app, with the scientific name always shown in small italic parentheses. The scientific
  name remains the curation key; the common name is the human-facing one.

## Constraints (inherited, must hold)

- **100 % deterministic** care engine; no runtime AI. Owner-scoped, single-user today. All AI lives
  in the knowledge engine.
- **MariaDB date rule:** never compare date/time columns against ISO strings; day differences are
  computed on `@db.Date` values (UTC-midnight) as integer day counts. Bind native dates.
- **No new forks:** shared behaviour lives in exactly one place and is reused, never copied. The
  "primary common name" rule and the misting/viability mapping each live once.
- `db:insert` remains the only writer of the `species` table; this spec does not write species rows
  from the API.
- **`engines/` stays Prisma-free** (type-only Prisma imports are fine); pure functions take flat
  shapes.
- **Backward compatibility:** every new species-record field ships with a default so species already
  stored in the DB keep parsing without re-curation. New curations populate the real values.
- Local-only; no deploy. Internet is available at runtime (already used for weather).

## Repos touched & dependency order

Per the Multi-repo feature workflow, implement in dependency order:
`my-plants-species-schema` → `my-plants-knowledge-engine` → `my-plants-api` → `my-plants-web`,
then root docs. After any schema change, `pack-species-schema-and-install` into its consumers and
commit the lockfiles.

---

## R1 — Editorial-writer subagent (knowledge engine only)

This requirement touches **only** the knowledge engine's AI workflow. It does **not** change the
species schema, the API, the database, or the web app. The persistence contract is unchanged:
`db:insert` still receives `--brief-en` and `--brief-es`.

### R1.1 Platform constraint that fixes the data flow

In Claude Code a **subagent cannot invoke another subagent**. Therefore the only possible mechanic
is: the **operator** (the knowledge-engine orchestrator) invokes `plant-researcher`, receives its
output, then invokes `editorial-writer` with that output. The user's "Flow C" data semantics
(researcher writes a complete brief; editorial-writer restyles it) are preserved; only the
invocation is necessarily operator-relayed. Because the researcher emits a **complete** prose brief
(not loose data), the editorial-writer receives a fact-rich document and only needs to restyle —
this is what mitigates the data-loss risk.

### R1.2 The `editorial-writer` subagent

New file `repos/my-plants-knowledge-engine/.claude/agents/editorial-writer.md`.

- **Role:** a professional editorial writer. **Input:** the raw English brief + the structured
  species record (as a factual anchor). **Output:** two Markdown documents — a polished English
  brief and a transcreated Spanish brief — in one consistent house voice.
- **Tools:** minimal and **no web access** (`Read` only). Without web tools it cannot introduce new
  facts; it can only reshape what it is given.
- **House-voice style guide lives in its system prompt** — the single home for "the voice": warm,
  curious, knowledgeable, engaging; a hook intro, scannable sections, fun facts, and a short
  cultivars section when the record has cultivars; consistent rhythm.
- **Anti-hallucination rule (mandatory in the prompt):** every claim must trace to the provided raw
  brief or record. The writer may reorder, add narrative hooks, and make it entertaining, but must
  **never invent care numbers or facts not present**. The Spanish is a fluent, natural transcreation
  (not a literal translation).

### R1.3 Changes to `plant-researcher`

- Stops emitting Spanish and stops optimizing for "catchy". It now returns the record + **one raw
  English brief** optimized for *informational completeness*, not style.
- Continues to be the source of truth for all facts. Also learns to populate the new record fields
  introduced by R2/R3 and the friendly-naming guidance (see R2.4, R3.5, Refinement B).

### R1.4 Changes to the operator workflow (`CLAUDE.md` / `AGENTS.md` of the knowledge engine)

Insert a step between research and persistence: after the researcher returns the record + raw
English brief, the operator invokes `editorial-writer` with that brief + record, receives the
polished EN + ES briefs, and writes those as the drafts that go to `db:insert`. Step numbering and
the enrich-mode notes are updated accordingly. (If the knowledge engine has an `AGENTS.md` mirror,
keep it byte-for-byte in sync.)

---

## R2 — Climate-driven watering (API engine)

### R2.1 Product decision: temperature and humidity drive watering

Warmer, drier air → faster transpiration → soil dries sooner → water sooner. Cooler, more humid
air → slower drying → water later. This holds indoors as much as outdoors. The current engine only
applies the temperature modulator outdoors and never applies humidity; this phase closes both gaps.

### R2.2 The unifying concept: "real signal"

Replace the ad-hoc `isOutdoor` / `weatherAvailable` guards with a single idea: **a modulator acts
only when there is a real environmental reading; otherwise it stays neutral (×1).**

`effectiveConditions` is extended to return, alongside the effective values, whether each value is
a *real signal* or a *fallback baseline*:

- **Temperature signal** is real when: outdoor with weather available; **or** indoor with an
  explicit temp range; **or** indoor without a range, not climate-controlled, with weather
  available (falls back to outdoor — see Refinement A). It is **not** a real signal (→ neutral)
  when the value is a comfort baseline (climate-controlled without a range, or no weather at all).
- **Humidity signal** is real when: indoor with a provided `humidityCharacter`; **or** indoor
  without one but with weather available (falls back to outdoor — see Refinement A); **or** outdoor
  with weather available. It is **not** a real signal when it is the 50 % fallback baseline.

The scheduling engine consumes these booleans: a modulator whose signal is false returns `1`.

### R2.3 The humidity modulator

A new modulator in `engines/scheduling.ts`, symmetric to the temperature one:

- Deviation = `idealHumidityPct − effectiveHumidityPct` (positive = drier than the species ideal).
- Drier than ideal → shorten the interval (multiplier `< 1`); more humid → lengthen (`> 1`).
- Weighted by the new `humiditySensitivity` (low/medium/high) using the existing `SENS_WEIGHT`
  table, scaled by a humidity factor so a large humidity gap (tens of percentage points) moves the
  cycle meaningfully but bounded. The multiplier is clamped to a sane band (mirroring the existing
  light/temperature clamps). The exact constant is fixed in the plan (target: a ~30-point gap at
  `high` sensitivity shifts the interval on the order of ~15 %).

The temperature modulator drops its `isOutdoor` guard and instead respects the temperature signal
boolean, using `effective.tempC` (which is now correct indoors too).

### R2.4 Schema change: `humiditySensitivity`

Add `humiditySensitivity: z.enum(SENSITIVITY).default('low')` to `wateringSchema`. The default is
deliberately **conservative** (`low`): a species not yet re-curated barely reacts to humidity until
the researcher assigns its real value. New curations always set it. The researcher prompt learns to
populate it (e.g. a calathea is `high`, a succulent `low`).

### R2.5 Wiring

`CarePlanService.dueForTask` passes `humiditySensitivity`, `idealHumidityPct`
(`record.humidity.idealPct`), the effective humidity, and the temperature/humidity signal booleans
into `computeNextDue`. No other cycle changes.

---

## R3 — Misting cycle (schema + knowledge engine + API + web)

### R3.1 Schema: the `misting` section

Add a new enum `MISTING_BENEFIT = ['beneficial', 'tolerated', 'avoid']` and a `mistingSchema`:

- `benefit: z.enum(MISTING_BENEFIT).default('avoid')` — default `avoid` so un-recurated species
  generate **no** misting task (safe).
- `baseFrequencyDays: z.number().int().positive().nullable().default(null)`.
- `note: z.string().min(1).nullable().default(null)` — free-text nuance (e.g. "avoid wetting the
  crown").
- **Refinement:** when `benefit !== 'avoid'`, `baseFrequencyDays` must be non-null; when
  `benefit === 'avoid'`, it must be null.

Add `misting: mistingSchema.default({ benefit: 'avoid', baseFrequencyDays: null, note: null })` to
`speciesRecordSchema` so records lacking the section still parse.

### R3.2 Prisma: the `MIST` task

Add `MIST` to the `Task` enum (Prisma migration). Because `DueCache`, `TaskOverride`,
`PlantTaskAdjustment`, and `CareEvent` are all keyed by `Task`, misting inherits Done / Postpone /
anchoring support automatically.

### R3.3 The misting schedule (humidity-graded)

A new pure function `computeMistingDue` in `engines/scheduling.ts` returning `Date | null`
(`null` = no task should exist). Inputs: `benefit`, `baseFrequencyDays`, an already-resolved
**effective humidity band** (`'DRY' | 'NORMAL' | 'HUMID'`), `adjustment`, `anchor`. Logic:

| `benefit`    | DRY                          | NORMAL        | HUMID      |
|--------------|------------------------------|---------------|------------|
| `beneficial` | base frequency **shortened** | base frequency| **null**   |
| `tolerated`  | base frequency               | **null**      | **null**   |
| `avoid`      | null                         | null          | null       |

**Why a band, not the raw `humidityCharacter`:** the engine must use the same effective humidity the
rest of the engine sees, including the outdoor fallback when `humidityCharacter` is null
(Refinement A). The raw place field does not carry that fallback. So a single shared helper
`humidityBand(humidityPct): 'DRY' | 'NORMAL' | 'HUMID'` (thresholds aligned to the indoor mapping —
DRY/NORMAL/HUMID ≈ 35/50/65 %, banded at ~42 % and ~58 %) classifies `effectiveConditions`'
already-fallback-resolved `humidityPct`. `CarePlanService` computes `effectiveConditions` once,
derives the band via `humidityBand`, and passes the band into `computeMistingDue`. This keeps the
engine pure (a flat band in, no weather/place coupling) and reuses the one fallback path (no fork).
The `adjustment` multiplier applies when a date is produced. "Shortened" and the exact factor are
fixed in the plan.

### R3.4 Service gating + stale-due cleanup

`CarePlanService` computes the misting due; if it is `null`, it **deletes** any existing `DueCache`
row for `MIST` (so moving a plant from a dry room to a humid one removes a now-irrelevant misting
reminder). This stale-due cleanup is generalized so any skipped task (also `ROTATE`/`CLEAN_LEAVES`
when the species lacks them) clears its stale cache rather than leaving an orphan. Misting uses the
**generic** feedback path (Done re-anchors, Postpone overrides); it does **not** participate in the
watering-only punctuality learning.

### R3.5 Researcher guidance

The `plant-researcher` populates the `misting` section: `benefit` from evidence (succulents/cacti/
fuzzy-leaved → `avoid`; broad-leaved tropicals that like it → `beneficial`; others → `tolerated`),
a `baseFrequencyDays` when applicable, and a `note` for nuance.

### R3.6 Web

A new task row for `MIST` with its label ("Mist leaves") and icon in the plant care panel
(`/plants/:id`) and in "Today's care". The generic Done / Postpone buttons already work for any
task. Note the web has a **closed `TaskCode` union** (`utils/tasks.ts`) and a `Task` type in
`types/api.ts`: `MIST` must be added to both, plus the `TASK_LABELS` (and any icon/colour) maps —
the union will reject `MIST` until updated. This is small but must be explicit in Phase 6.

---

## Refinement A — Permissive indoor places (fall back to outdoor + alert)

### A.1 Effective-conditions fallback chain (indoor)

`engines/indoor-climate.ts` — `effectiveConditions` for an **indoor** place:

**Temperature** (most precise → fallback):
1. Explicit min/max range → average (real signal).
2. No range, climate-controlled → 21 °C comfort baseline (not a real signal → neutral).
3. No range, not climate-controlled, weather available → **outdoor temperature** (real signal).
4. No range, no weather → 21 °C baseline (neutral).

**Humidity** (most precise → fallback):
1. `humidityCharacter` provided (DRY/NORMAL/HUMID → 35/50/65 %) → real signal.
2. Not provided, weather available → **outdoor humidity** (real signal).
3. Not provided, no weather → 50 % baseline (neutral).

Design decisions (confirmed with the user): the outdoor fallback uses the **raw** outdoor reading
(not a building-damped estimate) — less physically precise but honest and simple, with the UI alert
making clear it is an approximation. Climate-controlled places without a range stay at 21 °C (the
flag is itself a real signal that the room is held comfortable). The existing damped-tracking branch
(`21 + 0.4·(outdoor − 21)`) is replaced by branch 3 above.

### A.2 Prisma & DTO

`Place.humidityCharacter` changes from `@default(NORMAL)` to **nullable** (`HumidityCharacter?`) so
"not provided" is representable (Prisma migration; existing rows keep their value). `indoorTempMinC`
/`indoorTempMaxC` are already nullable. The place **create** DTO makes the indoor temp range and
humidity **optional**. Because place responses can now return `humidityCharacter: null`, the **web
`Place` type** (`types/api.ts`, currently requiring `HumidityCharacter`) must be updated to allow
`null` — this is web-side scope, not just the API DTO.

### A.3 Viability consistency

`buildViability` already routes through `effectiveConditions`; its `ViabilityPlace.humidityCharacter`
becomes nullable and the same outdoor fallback applies, so the semaphore and the schedule see the
same effective humidity.

### A.4 Web alert

The place **create** form shows an informational alert when the place is **indoor** and the
temperature range and/or humidity are missing, conveying: *providing these details improves your
plant's care.* The string is in **English**, consistent with the rest of the web app's UI (final
wording fixed in the plan). The fields are no longer required.

**Scope decision (no edit surface today):** the API exposes only list/create/get for places
(`PlacesController` has no update route), so the alert lives on the **create** form only. Adding a
place-edit surface is out of scope for this wave; if/when it exists, the same alert applies there.

---

## Refinement B — Friendly naming (common name primary)

### B.1 The display rule

Across the app, a plant/species is named as:

- **Primary label:** the plant's `nickname` if set; else the species' **primary common name**; else
  the scientific name (fallback).
- **Always shown** alongside the name: the scientific name in **small italic parentheses**, e.g.
  **Lengua de suegra** *(Dracaena trifasciata)*. When the primary label already is the common name,
  the suffix is just the italic scientific name in parentheses.

### B.2 Single source for "primary common name"

Add a helper `primaryCommonName(record): string` to `my-plants-species-schema` returning
`commonNames[0] ?? scientificName`. Both the API and any other consumer derive the primary name
through this one helper (no-fork rule).

### B.3 Data flow: the API exposes the names

Today plant-related responses carry only `speciesSlug`. To avoid per-card N+1 fetches on the web,
the API includes the **primary common name** and the **scientific name** on the responses the web
already uses: the plant list, plant detail, today's tasks, the plant care endpoint, the species
list, **and the Moving simulation response** (it is plant-facing and currently returns only
`nickname` + `speciesSlug`, so omitting it would leave the Moving page on the slug fallback and
violate B.1). These are derived from the species record via `primaryCommonName` +
`record.scientificName`.

### B.4 Researcher guidance

`plant-researcher` returns `commonNames` **ordered by recognizability** (most colloquial first) and
**always at least one**. No schema break: the schema keeps `commonNames` defaulting to `[]`, and the
helper falls back to the scientific name if the array is empty (covers any legacy record).

### B.5 Web rendering

The plant list, plant detail header, today's view, the add-plant species dropdown, and the blog use
the display rule from B.1, reading the common + scientific names now present on API responses.

---

## Phases (one implementation plan each)

1. **Contract (schema).** `humiditySensitivity` (+ default); `misting` section + `MISTING_BENEFIT`
   enum + refinements (+ defaults); `primaryCommonName` helper; tests. Bump version, pack, install
   into knowledge-engine and api, commit lockfiles.
2. **Knowledge engine (R1 + new fields + naming).** Add `editorial-writer` subagent; rewrite
   `plant-researcher` to emit one raw English brief and to populate `humiditySensitivity`, the
   `misting` section, and recognizability-ordered `commonNames`; update the operator workflow
   (`CLAUDE.md`/`AGENTS.md`) to insert the editorial step.
3. **API watering engine (R2 + Refinement A).** Humidity modulator + indoor temperature modulation
   via the "real signal" concept; indoor outdoor-fallback chain; `humidityCharacter` nullable
   (Prisma migration) + DTO optional; viability nullability; tests.
4. **API misting (R3).** `MIST` Prisma migration; `computeMistingDue`; service gating + generalized
   stale-due cleanup; generic feedback path for `MIST`; misting in the care endpoint; tests.
5. **API + Web friendly naming (Refinement B).** API exposes common + scientific names on the
   relevant responses **including the Moving simulation response**; `primaryCommonName` wired; web
   renders the display rule everywhere (list, detail, today, add-plant dropdown, blog, moving).
6. **Web misting + place alert.** `MIST` added to the web `TaskCode` union, the `Task` type in
   `types/api.ts`, and the `TASK_LABELS`/icon maps, with the task row in the care panel and today's
   view; web `Place` type updated to allow `humidityCharacter: null`; place create form makes the
   indoor fields optional and shows the informational alert.
7. **Docs + runnable + E2E.** Update `docs/care-engine.md`, `docs/architecture.md`, and the
   knowledge-engine docs; apply migrations; re-curate at least one species through the real
   knowledge-engine flow (exercising the new editorial voice + new fields); run the qa-engineer E2E
   pass and the full suite.

## Testing strategy

- **Schema:** unit tests for the new fields, defaults, and the misting refinement (benefit ↔
  baseFrequencyDays); backward-compat test that a record without the new sections still parses.
- **API engines (pure):** table-driven tests for the humidity modulator, indoor temperature
  modulation, the real-signal gating, the indoor outdoor-fallback chain, and the misting
  humidity-grade table (every benefit × DRY/NORMAL/HUMID cell, including the `null`/cleanup cases).
- **API integration:** care recompute produces/clears a `MIST` due correctly across humidity bands
  and on simulated moves; responses carry the common + scientific names.
- **Web:** `npm run build` + `npm run typecheck` (remember `nuxt build` does not typecheck); Vitest
  for the naming display rule if a pure helper is extracted.
- **E2E (qa-engineer, local only):** the blog reads in the new editorial voice; a misting task
  appears for a dry-placed beneficial species and disappears when moved to a humid place; the place
  alert shows when indoor data is omitted; common names render with the italic scientific suffix.

## Backward compatibility & migration notes

- New schema fields all default → stored species parse unchanged.
- Two Prisma migrations: `humidityCharacter` nullable (Refinement A) and `MIST` task enum (R3).
- To **see** humidity/misting/editorial voice in action, re-curate at least one species via the real
  flow in Phase 7 (no hand-forced DB state).

## Out of scope

- Misting does not participate in punctuality learning, and is not season/dormancy modulated
  (humidity-driven only).
- Temperature/humidity do not change fertilizing, repotting, rotation, or leaf-cleaning cadences
  (evidence ties those to season/mechanics, already modelled).
- No deploy flow; local-only.
