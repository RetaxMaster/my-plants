# Enrichment v2 — Phase 3: Watering engine (climate-driven) + permissive indoor places Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ambient humidity and indoor temperature move the watering cycle, governed by a single "real signal" concept; and let indoor places fall back to real outdoor weather when their temp range/humidity are not provided (with `humidityCharacter` becoming nullable).

**Architecture:** `engines/` stays pure (no Prisma). `effectiveConditions` becomes the single source of effective temp/humidity AND of whether each is a *real signal* or a *fallback baseline*. `computeNextDue` gains a humidity modulator and replaces its `isOutdoor`/`weatherAvailable` guards with the signal flags. `CarePlanService` passes the new inputs. Prisma makes `Place.humidityCharacter` nullable.

**Tech Stack:** TypeScript, NestJS, Prisma, Vitest. Remember the MariaDB date rule (bind native dates; never compare against ISO strings).

**Repo:** `repos/my-plants-api`.

---

### Task 1: `effectiveConditions` returns signals + outdoor fallback (nullable humidity)

**Files:**
- Modify: `repos/my-plants-api/src/engines/indoor-climate.ts`
- Test: `repos/my-plants-api/src/engines/indoor-climate.test.ts`

- [ ] **Step 1: Write the failing tests** — add to `indoor-climate.test.ts`:

```ts
it('indoor with no range, not climate-controlled, falls back to raw outdoor temp (real signal)', () => {
  const e = effectiveConditions(
    { indoor: true, climateControlled: false, humidityCharacter: 'NORMAL', indoorTempMinC: null, indoorTempMaxC: null },
    { tempC: 33, humidityPct: 40 },
  );
  expect(e.tempC).toBe(33);
  expect(e.tempSignal).toBe(true);
});

it('indoor climate-controlled with no range stays at the comfort baseline (no temp signal)', () => {
  const e = effectiveConditions(
    { indoor: true, climateControlled: true, humidityCharacter: 'NORMAL', indoorTempMinC: null, indoorTempMaxC: null },
    { tempC: 33, humidityPct: 40 },
  );
  expect(e.tempC).toBe(21);
  expect(e.tempSignal).toBe(false);
});

it('indoor with a null humidityCharacter falls back to outdoor humidity (real signal)', () => {
  const e = effectiveConditions(
    { indoor: true, climateControlled: false, humidityCharacter: null, indoorTempMinC: 20, indoorTempMaxC: 22, },
    { tempC: 25, humidityPct: 70 },
  );
  expect(e.humidityPct).toBe(70);
  expect(e.humiditySignal).toBe(true);
});

it('indoor with null humidity and no weather uses the 50% baseline (no humidity signal)', () => {
  const e = effectiveConditions(
    { indoor: true, climateControlled: false, humidityCharacter: null, indoorTempMinC: 20, indoorTempMaxC: 22 },
    null,
  );
  expect(e.humidityPct).toBe(50);
  expect(e.humiditySignal).toBe(false);
});

it('outdoor with weather is a real signal for both', () => {
  const e = effectiveConditions(
    { indoor: false, climateControlled: false, humidityCharacter: null, indoorTempMinC: null, indoorTempMaxC: null },
    { tempC: 30, humidityPct: 45 },
  );
  expect(e).toEqual({ tempC: 30, humidityPct: 45, tempSignal: true, humiditySignal: true });
});
```

> Existing tests in this file that assert the old damped indoor behaviour (`21 + 0.4·(outdoor−21)`) must be **updated/removed** — that branch is replaced by the raw-outdoor fallback. Read the file and adjust those assertions to the new chain.

- [ ] **Step 2: Run to verify it fails** — `cd repos/my-plants-api && npx vitest run src/engines/indoor-climate.test.ts` → FAIL.

- [ ] **Step 3: Implement** — replace the contents of `indoor-climate.ts` with:

```ts
export interface PlaceClimateInput {
  indoor: boolean;
  climateControlled: boolean;
  humidityCharacter: 'DRY' | 'NORMAL' | 'HUMID' | null;
  indoorTempMinC: number | null;
  indoorTempMaxC: number | null;
}

export interface Weather {
  tempC: number;
  humidityPct: number;
}

export interface EffectiveConditions {
  tempC: number;
  humidityPct: number;
  tempSignal: boolean; // true when tempC is a real reading (not a comfort baseline)
  humiditySignal: boolean; // true when humidityPct is a real reading (not a baseline)
}

const COMFORT_BASELINE_C = 21;
const INDOOR_HUMIDITY_BASELINE = 50;
const HUMID_INDOOR = 65;
const DRY_INDOOR = 35;

function indoorHumidity(character: 'DRY' | 'NORMAL' | 'HUMID'): number {
  if (character === 'HUMID') return HUMID_INDOOR;
  if (character === 'DRY') return DRY_INDOOR;
  return INDOOR_HUMIDITY_BASELINE;
}

// Classify an effective humidity percentage into a band. Thresholds align to the indoor mapping
// (DRY≈35, NORMAL≈50, HUMID≈65). Single source used by the misting schedule (Phase 4).
export function humidityBand(humidityPct: number): 'DRY' | 'NORMAL' | 'HUMID' {
  if (humidityPct < 42) return 'DRY';
  if (humidityPct > 58) return 'HUMID';
  return 'NORMAL';
}

// The effective temp/humidity for a place, plus whether each is a REAL signal. Indoor places with
// no provided data fall back to the real outdoor weather (the only real reading); a comfort
// baseline (climate-controlled, or nothing available) is NOT a signal, so modulators stay neutral.
export function effectiveConditions(
  place: PlaceClimateInput,
  weather: Weather | null,
): EffectiveConditions {
  if (!place.indoor) {
    if (weather) return { tempC: weather.tempC, humidityPct: weather.humidityPct, tempSignal: true, humiditySignal: true };
    return { tempC: COMFORT_BASELINE_C, humidityPct: INDOOR_HUMIDITY_BASELINE, tempSignal: false, humiditySignal: false };
  }

  // Indoor temperature.
  let tempC: number;
  let tempSignal: boolean;
  if (place.indoorTempMinC !== null && place.indoorTempMaxC !== null) {
    tempC = (place.indoorTempMinC + place.indoorTempMaxC) / 2;
    tempSignal = true;
  } else if (place.climateControlled) {
    tempC = COMFORT_BASELINE_C;
    tempSignal = false;
  } else if (weather) {
    tempC = weather.tempC; // raw outdoor fallback
    tempSignal = true;
  } else {
    tempC = COMFORT_BASELINE_C;
    tempSignal = false;
  }

  // Indoor humidity.
  let humidityPct: number;
  let humiditySignal: boolean;
  if (place.humidityCharacter) {
    humidityPct = indoorHumidity(place.humidityCharacter);
    humiditySignal = true;
  } else if (weather) {
    humidityPct = weather.humidityPct; // raw outdoor fallback
    humiditySignal = true;
  } else {
    humidityPct = INDOOR_HUMIDITY_BASELINE;
    humiditySignal = false;
  }

  return { tempC, humidityPct, tempSignal, humiditySignal };
}
```

- [ ] **Step 4: Run to verify it passes** — `npx vitest run src/engines/indoor-climate.test.ts` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/engines/indoor-climate.ts src/engines/indoor-climate.test.ts
git commit -m "feat: effectiveConditions returns signals + raw outdoor fallback; humidityBand helper; nullable humidityCharacter"
```

---

### Task 2: Humidity modulator + signal-gated temperature in `computeNextDue`

**Files:**
- Modify: `repos/my-plants-api/src/engines/scheduling.ts`
- Test: `repos/my-plants-api/src/engines/scheduling.test.ts`

- [ ] **Step 1: Write the failing tests** — update the shared `base` fixture and the two now-obsolete temperature tests, and add humidity tests. New `base` (note: `effective` now carries signals; `isOutdoor`/`weatherAvailable` are gone; `humiditySensitivity`/`idealHumidityPct` are added):

```ts
const base: ScheduleInput = {
  baseIntervalDays: 10,
  droughtTolerance: 'medium',
  temperatureSensitivity: 'high',
  lightSensitivity: 'low',
  humiditySensitivity: 'high',
  reduceInDormancy: true,
  idealMinC: 18,
  idealMaxC: 27,
  idealHumidityPct: 60,
  idealLightRank: 2,
  anchor: new Date('2026-06-01'),
  adjustment: 1,
  effective: { tempC: 22, humidityPct: 60, tempSignal: true, humiditySignal: true },
  placeLightRank: 2,
  season: 'summer',
  reduceSeason: 'winter',
};
```

Replace the obsolete `'ignores outdoor heat for an indoor plant'` and `'is neutral on temperature when outdoor weather is unavailable'` tests with signal-based ones, and add humidity cases:

```ts
it('shortens for indoor heat when there is a real temperature signal', () => {
  const due = computeNextDue({ ...base, effective: { tempC: 33, humidityPct: 60, tempSignal: true, humiditySignal: true } });
  const days = Math.round((due.getTime() - base.anchor.getTime()) / 86_400_000);
  expect(days).toBeLessThan(10);
});

it('is neutral on temperature when there is no temperature signal', () => {
  const due = computeNextDue({ ...base, effective: { tempC: 33, humidityPct: 60, tempSignal: false, humiditySignal: true } });
  const days = Math.round((due.getTime() - base.anchor.getTime()) / 86_400_000);
  expect(days).toBe(10);
});

it('shortens the interval when the air is drier than ideal', () => {
  const dry = computeNextDue({ ...base, effective: { tempC: 22, humidityPct: 30, tempSignal: true, humiditySignal: true } });
  const days = Math.round((dry.getTime() - base.anchor.getTime()) / 86_400_000);
  expect(days).toBeLessThan(10);
});

it('lengthens the interval when the air is more humid than ideal', () => {
  const humid = computeNextDue({ ...base, effective: { tempC: 22, humidityPct: 85, tempSignal: true, humiditySignal: true } });
  const days = Math.round((humid.getTime() - base.anchor.getTime()) / 86_400_000);
  expect(days).toBeGreaterThan(10);
});

it('is neutral on humidity when there is no humidity signal', () => {
  const due = computeNextDue({ ...base, effective: { tempC: 22, humidityPct: 30, tempSignal: true, humiditySignal: false } });
  const days = Math.round((due.getTime() - base.anchor.getTime()) / 86_400_000);
  expect(days).toBe(10);
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run src/engines/scheduling.test.ts` → FAIL (type errors + assertions).

- [ ] **Step 3: Implement** — in `scheduling.ts`: (a) update `ScheduleInput`, (b) add the humidity modulator, (c) gate temp on the signal, (d) multiply by humidity.

Replace the `ScheduleInput` interface's `isOutdoor`/`weatherAvailable` lines and add the two new fields:

```ts
export interface ScheduleInput {
  baseIntervalDays: number;
  droughtTolerance: DroughtTolerance;
  temperatureSensitivity: Sensitivity;
  lightSensitivity: Sensitivity;
  humiditySensitivity: Sensitivity;
  reduceInDormancy: boolean;
  idealMinC: number;
  idealMaxC: number;
  idealHumidityPct: number;
  idealLightRank: number; // 0..3 (low..direct)
  anchor: Date;
  adjustment: number; // per-plant learned multiplier (>0)
  effective: EffectiveConditions; // carries tempSignal/humiditySignal
  placeLightRank: number; // 0..3
  season: Season;
  reduceSeason: Season;
}
```

Replace `tempModulator` and add `humidityModulator`:

```ts
// Hotter than ideal → drink sooner; colder → slower. Only when there's a real temperature signal.
function tempModulator(input: ScheduleInput): number {
  if (!input.effective.tempSignal) return 1;
  const { tempC } = input.effective;
  let deviation = 0;
  if (tempC > input.idealMaxC) deviation = -(tempC - input.idealMaxC);
  else if (tempC < input.idealMinC) deviation = input.idealMinC - tempC;
  return clamp(1 + deviation * SENS_WEIGHT[input.temperatureSensitivity] * 0.1, 0.5, 1.6);
}

// Drier than ideal → drink sooner; more humid → slower. Only with a real humidity signal.
// Humidity is in percentage points, so a small factor keeps a tens-of-points gap bounded.
function humidityModulator(input: ScheduleInput): number {
  if (!input.effective.humiditySignal) return 1;
  const deviation = input.idealHumidityPct - input.effective.humidityPct; // + = drier than ideal
  return clamp(1 - deviation * SENS_WEIGHT[input.humiditySensitivity] * 0.04, 0.7, 1.4);
}
```

Update `computeNextDue` to multiply by humidity:

```ts
  const raw =
    input.baseIntervalDays *
    input.adjustment *
    tempModulator(input) *
    lightModulator(input) *
    humidityModulator(input) *
    seasonModulator(input);
```

- [ ] **Step 4: Run to verify it passes** — `npx vitest run src/engines/scheduling.test.ts` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/engines/scheduling.ts src/engines/scheduling.test.ts
git commit -m "feat: humidity modulator + signal-gated indoor temperature in watering schedule"
```

---

### Task 3: Prisma migration — `humidityCharacter` nullable

**Files:**
- Modify: `repos/my-plants-api/prisma/schema.prisma` (line ~72)
- Create: a migration under `repos/my-plants-api/prisma/migrations/`

- [ ] **Step 1: Edit the model** — change in `schema.prisma`:

```prisma
  humidityCharacter HumidityCharacter? @map("humidity_character")
```

(remove `@default(NORMAL)`; add `?`).

- [ ] **Step 2: Create the migration**

Run: `cd repos/my-plants-api && set -a; source .env; set +a && npx prisma migrate dev --name humidity_character_nullable`
Expected: a new migration is created and applied; `npx prisma generate` runs. Existing rows keep their `NORMAL` value (column becomes nullable, no data loss).

> If the local DB is not running, start it per `docs/local-development.md` first — do not skip the migration (it must be real).

- [ ] **Step 3: Verify the client type** — `npx tsc --noEmit` may surface that `place.humidityCharacter` is now `HumidityCharacter | null`; that is expected and is consumed correctly by Task 1's `PlaceClimateInput`. Fix any call sites that assumed non-null by passing the value through (they already accept `null` after Task 1 / Task 5).

- [ ] **Step 4: Commit**

```bash
git add prisma/schema.prisma prisma/migrations
git commit -m "feat: make Place.humidityCharacter nullable (permissive indoor places)"
```

---

### Task 4: Wire the new inputs through `CarePlanService` + nullable humidity in viability

**Files:**
- Modify: `repos/my-plants-api/src/care-plan/care-plan.service.ts`
- Modify: `repos/my-plants-api/src/engines/viability.ts` (`ViabilityPlace.humidityCharacter` nullable)
- Test: `repos/my-plants-api/src/engines/viability.test.ts` (adjust types if needed)

- [ ] **Step 1: Make viability accept a nullable humidity character.** In `viability.ts`, change `ViabilityPlace`:

```ts
export interface ViabilityPlace {
  indoor: boolean;
  climateControlled: boolean;
  humidityCharacter: 'DRY' | 'NORMAL' | 'HUMID' | null;
  indoorTempMinC: number | null;
  indoorTempMaxC: number | null;
  lightType: LightType;
}
```

`buildViability` already routes through `effectiveConditions`, which now handles `null` — no further change there. Run `npx vitest run src/engines/viability.test.ts` and fix any fixture that needs the field present (pass `humidityCharacter: 'NORMAL'` or `null` as appropriate).

- [ ] **Step 2: Update `CarePlanService.recomputePlant`** — `effectiveConditions` now returns signals; pass the `effective` object straight through and drop the old `isOutdoor`/`weatherAvailable` plumbing. Change the `dueForTask` call and the WATER branch.

In `recomputePlant`, the `effective` computation is unchanged except its result now carries signals. Update the `dueForTask` call to drop `weatherAvailable`/`isOutdoor`:

```ts
      const due = this.dueForTask(task, record, {
        effective,
        placeLightRank: placeLightRank(place.lightType),
        season,
        anchor,
        adjustment,
      });
```

Update the `dueForTask` signature/ctx type (remove `weatherAvailable`, `isOutdoor`) and the WATER branch to add humidity + drop the removed fields:

```ts
  private dueForTask(
    task: Task,
    record: SpeciesRecord,
    ctx: {
      effective: EffectiveConditions;
      placeLightRank: number;
      season: Season;
      anchor: Date;
      adjustment: number;
    },
  ): Date {
    if (task === 'WATER') {
      return computeNextDue({
        baseIntervalDays: record.watering.baseIntervalDays,
        droughtTolerance: record.watering.droughtTolerance,
        temperatureSensitivity: record.watering.temperatureSensitivity,
        lightSensitivity: record.watering.lightSensitivity,
        humiditySensitivity: record.watering.humiditySensitivity,
        reduceInDormancy: record.watering.reduceInDormancy,
        idealMinC: record.temperature.idealMinC,
        idealMaxC: record.temperature.idealMaxC,
        idealHumidityPct: record.humidity.idealPct,
        idealLightRank: lightRank(record.light.ideal),
        anchor: ctx.anchor,
        adjustment: ctx.adjustment,
        effective: ctx.effective,
        placeLightRank: ctx.placeLightRank,
        season: ctx.season,
        reduceSeason: 'winter',
      });
    }
    // ...FERTILIZE / REPOT / ROTATE / CLEAN_LEAVES unchanged...
  }
```

(The `place.humidityCharacter` passed into `effectiveConditions` is now `HumidityCharacter | null` from Prisma — it flows straight in since `PlaceClimateInput.humidityCharacter` accepts `null`.)

- [ ] **Step 2b: Verify the full API build/typecheck**

Run: `cd repos/my-plants-api && npm run build && npx tsc --noEmit`
Expected: PASS. Fix any residual call sites (e.g. `plants.service.ts` / `moving.service.ts` already pass `humidityCharacter` through; with the nullable type they compile unchanged).

- [ ] **Step 3: Add an integration-ish test for indoor humidity moving the schedule.** Use the existing care-plan test harness pattern (read `src/care-plan/*.test.ts` if present, else add a focused engine-level assertion already covered by Task 2). If a service test exists, add: an indoor place with `humidityCharacter: 'DRY'` and a humidity-sensitive species waters sooner than the same place with `'HUMID'`.

- [ ] **Step 4: Run the full API suite**

Run: `cd repos/my-plants-api && npm test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/care-plan/care-plan.service.ts src/engines/viability.ts src/engines/viability.test.ts
git commit -m "feat: wire humidity + signal-gated temperature into care recompute; nullable humidity in viability"
```

---

### Task 5: Place create DTO — indoor fields optional

**Files:**
- Modify: `repos/my-plants-api/src/places/create-place.dto.ts`
- Modify: `repos/my-plants-api/src/places/places.service.ts` (`PlaceInput.humidityCharacter` already optional; ensure null is accepted)

- [ ] **Step 1: Read the current DTO** — `cat src/places/create-place.dto.ts`. Ensure `humidityCharacter`, `indoorTempMinC`, `indoorTempMaxC` are **optional** (`@IsOptional()`), and `humidityCharacter` permits the enum or absence. They are already typed optional in `PlaceInput`; make the DTO validators optional if they are not.

- [ ] **Step 2: Confirm create still works with omitted indoor fields** — the service does `prisma.place.create({ data: { ...input, ownerId } })`; with `humidityCharacter` absent, Prisma now stores `null` (column nullable). No service change needed beyond accepting the optional input.

- [ ] **Step 3: Build + typecheck**

Run: `cd repos/my-plants-api && npm run build && npx tsc --noEmit`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/places/create-place.dto.ts src/places/places.service.ts
git commit -m "feat: make indoor temp range + humidity optional on place creation"
```

---

## Self-Review

- **Spec coverage:** R2.2 real-signal concept ✓ Task 1+2; R2.3 humidity modulator ✓ Task 2; R2.5 wiring ✓ Task 4; Refinement A.1 outdoor fallback ✓ Task 1; A.2 nullable + optional DTO ✓ Tasks 3 & 5; A.3 viability consistency ✓ Task 4.
- **engines/ stays Prisma-free:** `indoor-climate.ts` and `scheduling.ts` import no Prisma runtime; `humidityCharacter` flows in as a string-union/null.
- **Type consistency:** `EffectiveConditions` shape (with signals) is used identically in scheduling, care-plan, viability, and Phase 4's misting. `humidityBand` defined here is consumed in Phase 4.
- **MariaDB date rule:** all due dates remain native `Date` via `addDays`; no ISO-string comparisons added.
- **Obsolete tests:** the old indoor-damping and `isOutdoor`/`weatherAvailable` tests are explicitly rewritten in Tasks 1 & 2.
