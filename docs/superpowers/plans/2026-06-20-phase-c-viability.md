# Phase C — Plant Viability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the viability semaphore for a plant in its current place by extracting one shared, pure viability builder (used by both Moving and the per-plant care endpoint) and adding a `viability` field to `GET /plants/:id/care`, rendered by the existing `ViabilityBadge` on the plant page.

**Architecture:** Phase C is a *no-fork extraction plus a field addition*. The plant→place→weather → `ViabilityInput` mapping that today lives inline inside `moving.service.ts` (lines ~38–60) is lifted into a single pure function `buildViability(record, place, weather)` in `engines/viability.ts`, which keeps the engines layer Prisma-free by accepting **flat shapes** instead of Prisma models. `moving.service.simulate` is refactored to call it (deleting its inline copy — one implementation only). The Phase-A care endpoint (`GET /plants/:id/care`) then computes the plant's viability against its own city weather using the very same builder, and the frontend renders the existing `ViabilityBadge` from the new `viability` field.

**Tech Stack:** NestJS (ESM, `.js` import specifiers) + Prisma + MariaDB (`repos/my-plants-api`); Vitest for unit tests (`npm test`); `@retaxmaster/my-plants-species-schema` (`LIGHT_LEVELS`, `parseSpeciesRecord`, `SpeciesRecord`); Nuxt 3 + Vue 3 + Nuxt UI (`repos/my-plants-web`, verified with `npm run build && npm run typecheck` — `npm run build` alone does NOT type-check because `nuxt.config.ts` sets `typescript.typeCheck: false`; `npm run typecheck` runs `nuxt typecheck` / `vue-tsc`, which does).

---

## Dependencies & assumptions (READ FIRST)

This plan **composes on top of Phase A and Phase B**, which are assumed already merged:

- **Phase A** added `GET /plants/:id/care` returning `{ plantId, tasks: [...] }` — owner-scoped, with server-computed `daysUntilDue`/`status` and a lazy on-demand recompute when the due cache is empty. The handler lives in a method named **`getCare(id)`** on a Phase-A service (the plant-care read service). **Assumption C-1:** that method already loads the plant owner-scoped and builds the `tasks` array; Phase C extends the *same* method to also load `place` + `city`, fetch weather, and attach `viability`. If Phase A placed the read model in `PlantsService.getCare` vs a dedicated `PlantCareReadService.getCare`, apply the edits to whichever class owns `getCare` — the method name and return shape are the contract, not the class name.
- **Phase B** generalized `WeatherService` so `forCity(cityId, lat, lng)` is a thin wrapper over `forLocation(key, lat, lng)`. The care endpoint uses **`forCity`** (the plant always has a saved city), so this plan is correct whether B landed or not.
- **Phase A frontend** rebuilt `pages/plants/[id].vue` into a care panel that calls `api.getPlantCare(id)`, and added a `PlantCare` type to `types/api.ts` with `viability` **optional**. Phase C makes `viability` **required** and renders the badge.

**Assumption C-2 (test fixture):** there is no shared `SpeciesRecord` test fixture in the repo. `buildViability` only reads `record.temperature.{survivalMinC,survivalMaxC,idealMinC,idealMaxC}`, `record.light.minimum`, and `record.humidity.minimumPct`. The unit test therefore constructs a minimal object with just those fields and casts it `as SpeciesRecord` (a pure-function test never validates the whole record — `parseSpeciesRecord` already guards that at the boundary).

**Shared contract (must match Phase A/B byte-for-byte):**

```ts
// engines/viability.ts — already present, unchanged:
type ViabilityLevel = 'good' | 'caution' | 'poor';
interface ViabilityResult { level: ViabilityLevel; reasons: string[] }

// NEW pure builder (this plan, Task 1):
function buildViability(
  record: SpeciesRecord,
  place: {
    indoor: boolean;
    climateControlled: boolean;
    humidityCharacter: 'DRY' | 'NORMAL' | 'HUMID';
    indoorTempMinC: number | null;
    indoorTempMaxC: number | null;
    lightType: 'LOW' | 'MEDIUM' | 'BRIGHT_INDIRECT' | 'DIRECT';
  },
  weather: { tempC: number; humidityPct: number; seasonalLowC: number; seasonalHighC: number } | null,
): ViabilityResult;

// Care endpoint response after this plan:
// { plantId: string;
//   tasks: { task; nextDueOn; daysUntilDue; status }[];
//   viability: { level: 'good'|'caution'|'poor'; reasons: string[] } }
```

**Repo conventions to respect:**
- ESM everywhere: relative imports end in `.js` even for `.ts` files.
- `engines/` stays **Prisma-free** — `buildViability` must accept flat shapes, never a Prisma `Plant`/`Place`.
- Owner scoping: the care endpoint must keep returning not-found for a plant outside the current owner.
- MariaDB date rule: no `toISOString()` comparisons (this plan adds no date comparisons; `daysUntilDue` was computed in Phase A — untouched here).
- Commit in English, Conventional Commits.

All API commands run **inside `repos/my-plants-api`**; all web commands run **inside `repos/my-plants-web`**.

---

## Task 1: Pure shared viability builder

Extract the plant→place→weather → `ViabilityInput` mapping into one pure function. This is the single source of truth both Moving and the care endpoint will call.

**Files:**
- Modify: `repos/my-plants-api/src/engines/viability.ts` (append `buildViability` after `assessViability`, ~line 55)
- Test: `repos/my-plants-api/src/engines/viability.test.ts` (append a new `describe('buildViability', …)` block)

- [ ] **Step 1: Write the failing tests**

Append this block to `repos/my-plants-api/src/engines/viability.test.ts` (and add `buildViability` to the existing top import — see Step 3 note):

```ts
import type { SpeciesRecord } from '@retaxmaster/my-plants-species-schema';

// Minimal record: buildViability only reads temperature/light.minimum/humidity.minimumPct.
const record = {
  temperature: { survivalMinC: 10, survivalMaxC: 35, idealMinC: 18, idealMaxC: 27 },
  light: { minimum: 'medium' as const },
  humidity: { minimumPct: 30 },
} as unknown as SpeciesRecord;

const outdoorMediumLight = {
  indoor: false,
  climateControlled: false,
  humidityCharacter: 'NORMAL' as const,
  indoorTempMinC: null,
  indoorTempMaxC: null,
  lightType: 'MEDIUM' as const, // rank 1 == minimum 'medium' (rank 1)
};

describe('buildViability', () => {
  it('maps light type to its rank and humidity from effectiveConditions', () => {
    // Outdoor place: effective humidity is the passed weather humidity (45 < 30? no -> ok).
    const r = buildViability(record, outdoorMediumLight, {
      tempC: 22, humidityPct: 45, seasonalLowC: 16, seasonalHighC: 28,
    });
    expect(r.level).toBe('good');
    expect(r.reasons).toEqual([]);
  });

  it('flags caution when the place light rank is below the species minimum', () => {
    const r = buildViability(record, { ...outdoorMediumLight, lightType: 'LOW' }, {
      tempC: 22, humidityPct: 45, seasonalLowC: 16, seasonalHighC: 28,
    });
    expect(r.level).toBe('caution');
    expect(r.reasons.join(' ')).toMatch(/light/i);
  });

  it('flags caution on low humidity using the indoor DRY character, not raw weather', () => {
    // Indoor + DRY -> effectiveConditions yields 35%? No: DRY indoor == 35, above 30 -> ok.
    // Force below minimum by raising the species minimum.
    const dryRecord = { ...record, humidity: { minimumPct: 40 } } as unknown as SpeciesRecord;
    const indoorDry = { ...outdoorMediumLight, indoor: true, humidityCharacter: 'DRY' as const };
    const r = buildViability(dryRecord, indoorDry, {
      tempC: 22, humidityPct: 80, seasonalLowC: 16, seasonalHighC: 28,
    });
    // 80% raw weather would pass; DRY indoor 35% is what must be used -> below 40 -> caution.
    expect(r.level).toBe('caution');
    expect(r.reasons.join(' ')).toMatch(/humidity/i);
  });

  it('falls back to ideal min/max for seasonal lo/hi when weather is null', () => {
    // weather null -> seasonalLowC=idealMinC=18, seasonalHighC=idealMaxC=27 (within survival) -> good.
    const r = buildViability(record, { ...outdoorMediumLight, indoor: true }, null);
    expect(r.level).toBe('good');
  });

  it('flags poor when the seasonal low is below the survival minimum', () => {
    const r = buildViability(record, outdoorMediumLight, {
      tempC: 5, humidityPct: 45, seasonalLowC: 4, seasonalHighC: 28,
    });
    expect(r.level).toBe('poor');
    expect(r.reasons.join(' ')).toMatch(/survival minimum/i);
  });

  it('flags poor when the seasonal high is above the survival maximum', () => {
    const r = buildViability(record, outdoorMediumLight, {
      tempC: 40, humidityPct: 45, seasonalLowC: 20, seasonalHighC: 40,
    });
    expect(r.level).toBe('poor');
    expect(r.reasons.join(' ')).toMatch(/survival maximum/i);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd repos/my-plants-api && npm test -- viability`
Expected: FAIL — `buildViability is not a function` / `buildViability is not exported` (the import in `viability.test.ts` cannot resolve it). The existing `assessViability` tests still pass.

- [ ] **Step 3: Write the minimal implementation**

First, extend the test file's existing top import so `buildViability` resolves. Change line 2 of `repos/my-plants-api/src/engines/viability.test.ts` from:

```ts
import { assessViability, type ViabilityInput } from './viability.js';
```

to:

```ts
import { assessViability, buildViability, type ViabilityInput } from './viability.js';
```

Then append `buildViability` to `repos/my-plants-api/src/engines/viability.ts`, after `assessViability` (after line 55). It imports the two helpers it composes and the schema bits it maps. Add these imports at the **top** of `viability.ts`:

```ts
import { LIGHT_LEVELS, type SpeciesRecord } from '@retaxmaster/my-plants-species-schema';
import { effectiveConditions } from './indoor-climate.js';
import { placeLightRank } from '../places/place-conditions.js';
import type { LightType } from '@prisma/client';
```

Then append the function:

```ts
export interface ViabilityPlace {
  indoor: boolean;
  climateControlled: boolean;
  humidityCharacter: 'DRY' | 'NORMAL' | 'HUMID';
  indoorTempMinC: number | null;
  indoorTempMaxC: number | null;
  lightType: LightType;
}

export interface ViabilityWeather {
  tempC: number;
  humidityPct: number;
  seasonalLowC: number;
  seasonalHighC: number;
}

// Maps a parsed species record + a flat place shape + (optional) weather into a ViabilityInput
// and assesses it. Flat shapes only — keeps the engines layer Prisma-free. The single source of
// truth for viability mapping; both moving.simulate and GET /plants/:id/care call it.
export function buildViability(
  record: SpeciesRecord,
  place: ViabilityPlace,
  weather: ViabilityWeather | null,
): ViabilityResult {
  const effective = effectiveConditions(
    {
      indoor: place.indoor,
      climateControlled: place.climateControlled,
      humidityCharacter: place.humidityCharacter,
      indoorTempMinC: place.indoorTempMinC,
      indoorTempMaxC: place.indoorTempMaxC,
    },
    weather ? { tempC: weather.tempC, humidityPct: weather.humidityPct } : null,
  );
  return assessViability({
    survivalMinC: record.temperature.survivalMinC,
    survivalMaxC: record.temperature.survivalMaxC,
    minLightRank: LIGHT_LEVELS.indexOf(record.light.minimum),
    minHumidityPct: record.humidity.minimumPct,
    seasonalLowC: weather?.seasonalLowC ?? record.temperature.idealMinC,
    seasonalHighC: weather?.seasonalHighC ?? record.temperature.idealMaxC,
    placeLightRank: placeLightRank(place.lightType),
    effectiveHumidityPct: effective.humidityPct,
  });
}
```

> Note: importing `LightType` from `@prisma/client` into `engines/` is a **type-only** import — no Prisma runtime dependency, so the Prisma-free rule holds. The data passed in is still a flat object, never a Prisma model.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd repos/my-plants-api && npm test -- viability`
Expected: PASS — both the original `assessViability` block and the new `buildViability` block green.

- [ ] **Step 5: Commit**

```bash
cd repos/my-plants-api
git add src/engines/viability.ts src/engines/viability.test.ts
git commit -m "feat(api): add shared pure buildViability mapping in engines"
```

---

## Task 2: Refactor moving.service.simulate to use the shared builder (delete the inline copy)

Replace the inline mapping in `simulate` with a call to `buildViability`. Behaviour stays identical — this is the no-fork collapse.

**Files:**
- Modify: `repos/my-plants-api/src/moving/moving.service.ts:38-61` (the `plants.map(...)` block), plus imports at lines 2 & 7–9
- Verify: existing suite (`simulate` has no dedicated unit test; it is covered by build + the Task 4 manual check and Phase D E2E. The refactor is behaviour-preserving, so the guard here is the type-checking build.)

- [ ] **Step 1: Rewrite the `simulate` mapping to call `buildViability`**

In `repos/my-plants-api/src/moving/moving.service.ts`, replace the import on line 7:

```ts
import { assessViability, type ViabilityResult } from '../engines/viability.js';
```

with:

```ts
import { buildViability, type ViabilityResult } from '../engines/viability.js';
```

Delete the now-unused imports on lines 8–9:

```ts
import { effectiveConditions } from '../engines/indoor-climate.js';
import { placeLightRank } from '../places/place-conditions.js';
```

Remove `LIGHT_LEVELS` from the schema import on line 2 (only `parseSpeciesRecord` remains used here):

```ts
import { parseSpeciesRecord } from '@retaxmaster/my-plants-species-schema';
```

Then replace the entire `plants.map(...)` block (lines 38–61) with:

```ts
    return plants.map((plant) => {
      const record = parseSpeciesRecord(plant.species.record);
      const result = buildViability(
        record,
        {
          indoor: plant.place.indoor,
          climateControlled: plant.place.climateControlled,
          humidityCharacter: plant.place.humidityCharacter,
          indoorTempMinC: plant.place.indoorTempMinC,
          indoorTempMaxC: plant.place.indoorTempMaxC,
          lightType: plant.place.lightType,
        },
        weather
          ? {
              tempC: weather.tempC,
              humidityPct: weather.humidityPct,
              seasonalLowC: weather.seasonalLowC,
              seasonalHighC: weather.seasonalHighC,
            }
          : null,
      );
      return { plantId: plant.id, nickname: plant.nickname, speciesSlug: plant.speciesSlug, ...result };
    });
```

> The inline `effectiveConditions` + `assessViability` calls are now gone — there is exactly one mapping implementation (in `engines/viability.ts`). `weather` is the `CurrentWeather | null` already fetched at line 32; `buildViability` does the ideal-fallback internally, so the old `weather?.seasonalLowC ?? record...` expressions are no longer needed here.

- [ ] **Step 2: Verify it compiles (no inline copy left, types align)**

Run: `cd repos/my-plants-api && npm run build`
Expected: PASS — clean `nest build`. If you left any of the now-unused imports (`effectiveConditions`, `placeLightRank`, `LIGHT_LEVELS`) behind, remove them for hygiene — the API `tsconfig.json` has no `noUnusedLocals`, so the build won't fail on an unused import, but keep imports clean.

- [ ] **Step 3: Run the full API suite (no regressions)**

Run: `cd repos/my-plants-api && npm test`
Expected: PASS — all engine tests (including Task 1's `buildViability`) green; nothing in moving relied on the deleted inline path.

- [ ] **Step 4: Commit**

```bash
cd repos/my-plants-api
git add src/moving/moving.service.ts
git commit -m "refactor(api): make moving.simulate use shared buildViability (no fork)"
```

---

## Task 3: Add `viability` to `GET /plants/:id/care`

Extend the Phase-A `getCare` method to load the plant's place + city, fetch that city's weather, build viability with the shared function, and include it in the response. Keep owner scoping.

**Files:**
- Modify: the Phase-A care read service — the class that owns `getCare(id)` (see Assumption C-1). Path is `repos/my-plants-api/src/plants/plants.service.ts` **if** Phase A added `getCare` there, otherwise the dedicated `repos/my-plants-api/src/plants/plant-care.service.ts`. Inspect which file defines `async getCare(` and edit that one.
- Modify (if needed): the owning module's providers/imports so `WeatherService` is injectable (it lives in `WeatherModule`, which exports `WeatherService`).
- Verify: `npm run build` + a focused manual `curl` check (the read path is integration-heavy — DB + live weather; the pure mapping it depends on is already unit-tested in Task 1).

- [ ] **Step 1: Locate the `getCare` method and its dependencies**

Run: `cd repos/my-plants-api && grep -rn "async getCare" src/`
Expected: one hit — note the file and class. Confirm the class constructor already injects `PrismaService` (Phase A needed it to read the due cache). If `WeatherService` is **not** already injected, add it to the constructor and ensure the owning module imports `WeatherModule`:

In that service's module file, add `WeatherModule` to `imports` if absent:

```ts
import { WeatherModule } from '../weather/weather.module.js';
// ...
@Module({ imports: [/* existing… */ WeatherModule], /* … */ })
```

- [ ] **Step 2: Extend `getCare` to compute and attach viability**

Add these imports at the top of the `getCare` service file (skip any already present):

```ts
import { parseSpeciesRecord } from '@retaxmaster/my-plants-species-schema';
import { buildViability } from '../engines/viability.js';
import { WeatherService } from '../weather/weather.service.js';
```

Ensure the constructor injects weather (alongside the existing Phase-A deps):

```ts
constructor(
  private readonly prisma: PrismaService,
  private readonly owner: OwnerService,
  private readonly weather: WeatherService,
  // …any other Phase-A deps such as CarePlanService for the lazy recompute…
) {}
```

Inside `getCare(id)`, **after** the Phase-A owner-scoped lookup + lazy recompute + tasks build, load the plant with its species/place/city and compute viability, then add it to the returned object. The plant is already known to belong to the owner (Phase A's not-found guard ran). Insert before the `return`:

```ts
    // Viability of the plant in its CURRENT place, against its own city's weather.
    const full = await this.prisma.plant.findUniqueOrThrow({
      where: { id },
      include: { species: true, place: { include: { city: true } } },
    });
    const record = parseSpeciesRecord(full.species.record);
    const { city } = full.place;
    const weather = await this.weather.forCity(city.id, city.latitude, city.longitude);
    const viability = buildViability(
      record,
      {
        indoor: full.place.indoor,
        climateControlled: full.place.climateControlled,
        humidityCharacter: full.place.humidityCharacter,
        indoorTempMinC: full.place.indoorTempMinC,
        indoorTempMaxC: full.place.indoorTempMaxC,
        lightType: full.place.lightType,
      },
      weather
        ? {
            tempC: weather.tempC,
            humidityPct: weather.humidityPct,
            seasonalLowC: weather.seasonalLowC,
            seasonalHighC: weather.seasonalHighC,
          }
        : null,
    );
```

Then change the existing `return { plantId, tasks }` to include `viability`:

```ts
    return { plantId: id, tasks, viability };
```

> `viability` is `{ level, reasons }` — exactly the `ViabilityResult` shape. `forCity` returns `null` on weather failure and never throws (the scheduler relies on that), so the endpoint degrades to the ideal-temperature fallback rather than erroring.

- [ ] **Step 3: Verify it compiles**

Run: `cd repos/my-plants-api && npm run build`
Expected: PASS. If it fails with `Property 'forCity' does not exist` you forgot to inject `WeatherService` / import `WeatherModule` (Step 1).

- [ ] **Step 4: Run the full API suite**

Run: `cd repos/my-plants-api && npm test`
Expected: PASS — no regressions (the care endpoint has no DB-backed unit test; the pure builder it calls is covered by Task 1).

- [ ] **Step 5: Manual smoke check against a running stack**

This read path touches the DB and live weather, so verify it end-to-end once. With MariaDB up and at least one seeded plant, start the API and curl the endpoint (replace `<id>` with a real plant id from `GET /plants`):

```bash
cd repos/my-plants-api && npm run start &
sleep 4
curl -s localhost:8000/plants/$(curl -s localhost:8000/plants | node -e 'process.stdin.once("data",d=>process.stdout.write(JSON.parse(d)[0].id))')/care | node -e 'process.stdin.once("data",d=>console.log(JSON.stringify(JSON.parse(d),null,2)))'
```

Expected: JSON with `plantId`, a `tasks` array, **and** `"viability": { "level": "good|caution|poor", "reasons": [...] }`. Then stop the server (`kill %1`). If `viability` is absent, Step 2's `return` was not updated.

- [ ] **Step 6: Commit**

```bash
cd repos/my-plants-api
git add src/plants/
git commit -m "feat(api): include plant viability in GET /plants/:id/care"
```

---

## Task 4: Render the viability badge on the plant page

Make the `PlantCare` type's `viability` required and render the existing `ViabilityBadge` at the top of the plant detail page using the new field.

**Files:**
- Modify: `repos/my-plants-web/types/api.ts` (the Phase-A `PlantCare` interface — make `viability` required)
- Modify: `repos/my-plants-web/pages/plants/[id].vue` (Phase-A care panel — add the badge at the top)
- Reuse (unchanged): `repos/my-plants-web/components/ViabilityBadge.vue`
- Verify: `npm run build && npm run typecheck` (build + a separate type-check pass — `npm run build` alone does NOT type-check, see Step 3) + a focused manual page check

- [ ] **Step 1: Make `viability` required on `PlantCare`**

In `repos/my-plants-web/types/api.ts`, find the Phase-A `PlantCare` interface. It currently has `viability` optional, e.g.:

```ts
export interface PlantCareTask { task: TaskCode; nextDueOn: string; daysUntilDue: number; status: 'overdue' | 'today' | 'upcoming' }
export interface PlantCare {
  plantId: string;
  tasks: PlantCareTask[];
  viability?: { level: ViabilityLevel; reasons: string[] }; // <- optional after Phase A
}
```

Change the `viability` line to required (drop the `?`):

```ts
  viability: { level: ViabilityLevel; reasons: string[] };
```

> `ViabilityLevel` (`'good' | 'caution' | 'poor'`) already exists at the top of `types/api.ts` — reuse it, do not redeclare.

- [ ] **Step 2: Render `ViabilityBadge` at the top of the plant page**

In `repos/my-plants-web/pages/plants/[id].vue`, the Phase-A page fetches the care model (e.g. `const { data: care } = await useAsyncData(...);` via `api.getPlantCare(id)`). Add the badge near the top of the rendered panel, bound to `care.viability`. Insert it just under the heading block, guarded by `v-if="care"`:

```vue
    <ViabilityBadge
      v-if="care"
      class="mt-3"
      :level="care.viability.level"
      :reasons="care.viability.reasons"
    />
```

`ViabilityBadge` is auto-imported by Nuxt (it lives in `components/`), takes `level` (required) and `reasons` (optional string array), and renders a colored `UBadge` plus a bullet list of reasons — no further wiring needed.

> If Phase A named the care ref something other than `care` (e.g. `plantCare`), bind to that name instead; the contract is "render `ViabilityBadge` from the care model's `viability`".

- [ ] **Step 3: Build + typecheck the web app**

Run: `cd repos/my-plants-web && npm run build && npm run typecheck`
Expected: both PASS. Note: `npm run build` does NOT catch TypeScript type errors here (`nuxt.config.ts` sets `typescript.typeCheck: false`); the type errors below are caught by `npm run typecheck` (which runs `nuxt typecheck` / `vue-tsc`), so this step must run it. A `npm run typecheck` failure like `Object is possibly 'undefined'` on `care.viability` means the `v-if="care"` guard is missing; a `npm run typecheck` failure that `viability` could be `undefined` means Step 1 (making it required) was not applied.

- [ ] **Step 4: Manual page check**

With the API running (from Task 3) and the web dev server up, open a plant detail page and confirm the badge renders with a level and, when applicable, reasons:

```bash
cd repos/my-plants-web && npm run dev
```

Expected: at `http://localhost:8001/plants/<id>` (web), the top of the page shows the viability badge (green "Good fit" / amber "Caution" / red "Poor fit") matching the `viability` returned by the care endpoint, with any reasons listed beneath it. Stop the dev server when done.

> A deeper, real-user verification of this badge (alongside mark-done, city search, places form, blog) is delegated to the `qa-engineer` subagent in the spec's E2E pass — not part of this plan's steps.

- [ ] **Step 5: Commit**

```bash
cd repos/my-plants-web
git add types/api.ts pages/plants/\[id\].vue
git commit -m "feat(web): render viability badge on the plant page"
```

---

## Self-Review

**Spec coverage (Phase C, sections C.1 + C.2):**
- C.1 "Shared viability builder (no fork)" → Task 1 (extract pure `buildViability` into `engines/viability.ts`, flat shapes, unit-tested) + Task 2 (refactor `moving.simulate` to call it, delete the inline copy → one implementation). ✓
- C.2 "Per-plant care endpoint gains `viability`" → Task 3 (load plant+place+city, fetch that city's weather via `forCity`, call `buildViability`, return `{ plantId, tasks, viability }`, owner scoping preserved via the Phase-A guard). ✓
- C.2 "frontend renders the existing `ViabilityBadge` at the top of `/plants/:id`" + "`viability` now required in `PlantCare`" → Task 4. ✓
- Testing strategy: pure builder gets full unit tests (light rank, humidity from `effectiveConditions`, seasonal fallback to ideal min/max on null weather, survival thresholds); endpoint verified with `npm run build` (API `nest build` type-checks) and the badge with `npm run build && npm run typecheck` (web `npm run build` does NOT type-check — `typescript.typeCheck: false` — so the type guard is `npm run typecheck`) + focused manual checks. ✓

**Out of scope (correctly NOT here):** `daysUntilDue`/`status` computation and the lazy recompute (Phase A); `forLocation` weather generalization and the `simulate` body change to coords (Phase B); the moving controller DTO change (cross-cutting Moving). This plan only *adds* the `viability` field and *extracts* the shared builder, composing on A and B.

**Placeholder scan:** every code step shows real code; commands have expected output; no TBD/TODO. The two intentional conditional points (which class owns `getCare`; the care ref name in `[id].vue`) are framed as "inspect, then apply to whichever" with the contract stated — these are Phase-A coupling facts, not placeholders.

**Type consistency:** `buildViability(record, place, weather)` signature is identical in Task 1 (definition), Task 2 (moving call), and Task 3 (care call). `ViabilityResult` = `{ level, reasons }` is reused, never redeclared. The web `PlantCare.viability` shape (`{ level: ViabilityLevel; reasons: string[] }`) matches the API `ViabilityResult`. `forCity(cityId, lat, lng)` matches the real `WeatherService` signature. `CurrentWeather` exposes `tempC`, `humidityPct`, `seasonalLowC`, `seasonalHighC` (the fields read in Tasks 2 & 3), consistent with the original inline mapping.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-20-phase-c-viability.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. **REQUIRED SUB-SKILL:** superpowers:subagent-driven-development.
2. **Inline Execution** — execute tasks in this session with checkpoints. **REQUIRED SUB-SKILL:** superpowers:executing-plans.
