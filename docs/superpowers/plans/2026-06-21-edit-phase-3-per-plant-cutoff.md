# Edit Phase 3 — Per-plant day cutoff (API) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The "what counts as today" boundary stops using the owner's primary city and instead uses **each plant's place-city timezone**. Two call sites change; `isPrimary` stays in the schema (Moving still uses it). No migration.

**Architecture:** `PlantsService.getCare` already loads the plant's place-city for viability — fold that include into the initial fetch and use `plant.place.city.timezone` for the boundary (drops the now-redundant second fetch and the primary lookup). `CarePlanService.todaysTasks` switches from a single SQL cutoff to per-row filtering by each row's plant→place→city timezone. Comparisons use native `Date` objects (MariaDB date rule).

**Tech Stack:** NestJS, Prisma, Vitest.

**Repo:** `repos/my-plants-api`. Branch: `feature/edit-modules`.

---

### Task 1: `CarePlanService.todaysTasks` — per-plant cutoff

**Files:** Modify `src/care-plan/care-plan.service.ts`; Test `src/care-plan/care-plan.service.today.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest';
import { CarePlanService } from './care-plan.service.js';

it('todaysTasks applies each plant own place-city timezone', async () => {
  // now = 02:00Z on 2026-06-21. In UTC the local date is the 21st (tomorrow = 06-22);
  // in America/Mexico_City (UTC-6) it is still the 20th (tomorrow = 06-21).
  const now = new Date('2026-06-21T02:00:00Z');
  const dueOn = new Date(Date.UTC(2026, 5, 21)); // 2026-06-21 UTC midnight (a @db.Date value)
  const rows = [
    { plantId: 'a', task: 'WATER', nextDueOn: dueOn, plant: { place: { city: { timezone: 'UTC' } } } },
    { plantId: 'b', task: 'WATER', nextDueOn: dueOn, plant: { place: { city: { timezone: 'America/Mexico_City' } } } },
  ];
  const prisma = { dueCache: { findMany: async () => rows } } as any;
  const svc = new CarePlanService(prisma, {} as any);
  const out = await svc.todaysTasks('owner-1', now);
  // 'a' is due today in UTC; 'b' is "tomorrow" in Mexico City → excluded.
  expect(out.map((r) => r.plantId)).toEqual(['a']);
  expect(out[0]).not.toHaveProperty('plant'); // nested join data is stripped from the result
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run src/care-plan/care-plan.service.today.test.ts` → FAIL.

- [ ] **Step 3: Implement** — replace `todaysTasks` in `src/care-plan/care-plan.service.ts`:

```ts
// "Today" derives the day boundary from EACH plant's place-city timezone (not a single primary).
// Due dates are DATE granularity; we filter per row with native Date comparisons (MariaDB date rule).
async todaysTasks(ownerId: string, now: Date = new Date()): Promise<{ plantId: string; task: Task; nextDueOn: Date }[]> {
  const rows = await this.prisma.dueCache.findMany({
    where: { plant: { ownerId } },
    select: {
      plantId: true,
      task: true,
      nextDueOn: true,
      plant: { select: { place: { select: { city: { select: { timezone: true } } } } } },
    },
    orderBy: { nextDueOn: 'asc' },
  });
  return rows
    .filter((r) => r.nextDueOn < startOfTomorrowUtc(r.plant.place.city.timezone, now))
    .map((r) => ({ plantId: r.plantId, task: r.task, nextDueOn: r.nextDueOn }));
}
```

(`startOfTomorrowUtc` is already imported in this file.)

- [ ] **Step 4: Run to verify it passes** → PASS.

- [ ] **Step 5: Commit** — `git add src/care-plan/care-plan.service.ts src/care-plan/care-plan.service.today.test.ts && git commit -m "feat(care-plan): per-plant place-city timezone for the today cutoff"`

---

### Task 2: `PlantsService.getCare` — boundary from the plant's place-city

**Files:** Modify `src/plants/plants.service.ts`; Test `src/plants/plants.service.getcare-tz.test.ts`

- [ ] **Step 1: Write the failing test** (proves getCare no longer depends on a primary city)

```ts
import { describe, expect, it } from 'vitest';
import { AsyncLocalStorage } from 'node:async_hooks';
import { ClsService } from 'nestjs-cls';
import { OwnerService } from '../owner/owner.service.js';
import { PlantsService } from './plants.service.js';
// reuse the `record` constant from plants.service.ownership.test.ts

const plantWithTz = (timezone: string) => ({
  id: 'p1', ownerId: 'owner-1', placeId: 'place-a', speciesSlug: 'dracaena-trifasciata', nickname: 'Sansa',
  acquiredOn: new Date('2026-01-01'),
  species: { scientificName: 'Dracaena trifasciata', record },
  place: { indoor: true, lightType: 'BRIGHT_INDIRECT', climateControlled: false, humidityCharacter: null, indoorTempMinC: null, indoorTempMaxC: null, city: { id: 'c1', latitude: 10, longitude: 20, timezone } },
});
// NOTE: these fake prismas have NO `city` delegate — if getCare still called city.findFirst it would throw.
const runGetCare = (timezone: string) => {
  const prisma = {
    plant: { findFirst: async () => plantWithTz(timezone) },
    dueCache: { findMany: async () => [{ task: 'WATER', nextDueOn: new Date(Date.UTC(2026, 5, 21)) }] },
  } as any;
  const cls = new ClsService(new AsyncLocalStorage());
  const owner = new OwnerService(cls);
  const weather = { forCity: async () => ({ tempC: 20, humidityPct: 50, seasonalLowC: 10, seasonalHighC: 30 }) } as any;
  const svc = new PlantsService(prisma, owner, {} as any, weather);
  return cls.run(async () => { cls.set('actor', { userId: 'u', username: 'n', ownerId: 'owner-1', role: 'USER', jti: 'j', exp: 9e9 }); return svc.getCare('p1'); });
};

it('getCare computes the boundary from the plant place-city (no primary lookup)', async () => {
  const out = await runGetCare('UTC');
  expect(out.plantId).toBe('p1');
  expect(out.tasks[0].task).toBe('WATER');
  expect(['overdue', 'today', 'upcoming']).toContain(out.tasks[0].status);
  expect(out.viability).toHaveProperty('level');
});

it('getCare feeds the place-city timezone into the boundary (proven: an invalid tz throws)', async () => {
  // If getCare hardcoded 'UTC' or used the primary, an invalid place-city tz would be ignored.
  // Because the boundary is built from plant.place.city.timezone, an invalid zone makes
  // Intl.DateTimeFormat throw a RangeError — a deterministic proof of the wiring.
  await expect(runGetCare('Not/AZone')).rejects.toThrow();
});
```

- [ ] **Step 2: Run to verify it fails** — FAIL (current getCare calls `city.findFirst`, absent in the fake → throws).

- [ ] **Step 3: Implement** — in `getCare`, fold the place-city include into the first fetch and drop the primary lookup + the redundant `full` fetch:
  - Change the initial fetch to:
    ```ts
    const plant = await this.prisma.plant.findFirst({
      where: { id, ...this.owner.ownerFilter() },
      include: { species: true, place: { include: { city: true } } },
    });
    if (!plant) throw new NotFoundException(`Unknown plant: ${id}`);
    ```
  - Replace the primary-city boundary block with:
    ```ts
    const startOfToday = startOfTodayUtc(plant.place.city.timezone);
    ```
  - Delete the separate `const full = await this.prisma.plant.findUniqueOrThrow(...)` and use `plant` in its place (`const record = parseSpeciesRecord(plant.species.record); const { city } = plant.place;` and `plant.place.*` in `buildViability`).

- [ ] **Step 4: Run to verify it passes** — `npx vitest run src/plants/plants.service.getcare-tz.test.ts` → PASS. Then `npm test` (full suite) → green.

- [ ] **Step 5: Commit** — `git add src/plants/plants.service.ts src/plants/plants.service.getcare-tz.test.ts && git commit -m "feat(plants): getCare boundary from the plant place-city timezone"`

---

### Task 3: Update the stale comment

**Files:** Modify `src/common/time/local-date.ts`

- [ ] **Step 1:** Change the header comment from "All day boundaries use the owner's primary-city timezone." to: "All day boundaries use the timezone of each plant's place-city (Moving still uses the primary flag, but the day cutoff does not)."

- [ ] **Step 2: Commit** — `git add src/common/time/local-date.ts && git commit -m "docs(time): clarify per-plant place-city day boundary"`
