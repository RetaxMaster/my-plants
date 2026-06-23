# Acting As — Phase 3: Simulate Empty-Primary Fallback + Recompute Re-scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix B8 — when the primary city has none of the owner's plants, `simulate` falls back to all owner plants, and each result carries its place-city name + an `inPrimaryCity` flag so the UI can warn. Also re-scope `POST /care-plan/recompute` to the effective owner (consistency with the effective-owner model).

**Architecture:** Two extra fields on `PlantViability`, a conditional second query in `MovingService.simulate`, and a one-line change to the recompute controller. All owner scoping already flows through `currentOwnerId()` (Phase 1), so acting-as composes for free.

**Tech Stack:** NestJS, Prisma, Vitest.

**Reference:** spec §4.5, §4.6. All commands run from `repos/my-plants-api/`.

---

### Task 1: Extend `PlantViability` + simulate fallback

**Files:**
- Modify: `src/moving/moving.service.ts`
- Modify: `src/moving/moving.service.simulate-scope.test.ts`

- [ ] **Step 1: Rewrite the scope test with the new behavior and fields.** Replace the entire body of `src/moving/moving.service.simulate-scope.test.ts` with:

```ts
import { describe, expect, it } from 'vitest';
import { AsyncLocalStorage } from 'node:async_hooks';
import { ClsService } from 'nestjs-cls';
import { OwnerService } from '../owner/owner.service.js';
import { MovingService } from './moving.service.js';

// A complete VALID species record (re-validated by parseSpeciesRecord).
const record = {
  scientificName: 'Dracaena trifasciata',
  commonNames: ['Snake plant', 'Mother-in-law tongue'],
  watering: { baseIntervalDays: 14, soilDrynessBeforeWatering: 'mostly-dry', droughtTolerance: 'high', temperatureSensitivity: 'low', lightSensitivity: 'low', reduceInDormancy: true },
  light: { minimum: 'low', ideal: 'bright-indirect', maximum: 'direct' },
  temperature: { survivalMinC: 5, idealMinC: 18, idealMaxC: 27, survivalMaxC: 35 },
  humidity: { minimumPct: 30, idealPct: 45 },
  fertilizing: { activeSeasons: ['spring', 'summer'], inSeasonFrequencyDays: 30, reduceInDormancy: true },
  repotting: { typicalIntervalMonths: 36, signs: ['Roots out of drainage holes'] },
  maintenance: { pruning: 'Remove damaged leaves.', rotationDays: 30, leafCleaningDays: 30, commonPests: ['mealybugs'] },
  nativeClimate: { description: 'West African dry tropics.', koppen: 'Aw', hardinessMinC: 7, hardinessMaxC: 40 },
  metadata: { confidence: 'high', sources: [{ title: 'RHS', url: 'https://www.rhs.org.uk/plants/dracaena', accessedAt: '2026-06-18' }] },
};

const placeFields = { indoor: false, climateControlled: false, humidityCharacter: null, indoorTempMinC: null, indoorTempMaxC: null, lightType: 'BRIGHT_INDIRECT' };
const cityName = (id: string) => (id === 'c-primary' ? 'Primary City' : id === 'c-other' ? 'Other City' : id);
const plant = (id: string, cityId: string) => ({
  id, ownerId: 'o1', nickname: id, speciesSlug: 'dracaena-trifasciata',
  species: { record }, place: { ...placeFields, cityId, city: { id: cityId, name: cityName(cityId) } },
});

// `primaryId` is the city id findFirst resolves for the primary (or null = no primary).
function makePrisma(primaryId: string | null, all: any[]) {
  return {
    city: { findFirst: async ({ where }: any) => (where.isPrimary && primaryId ? { id: primaryId, timezone: 'UTC' } : null) },
    plant: {
      findMany: async ({ where }: any) =>
        where.place?.cityId ? all.filter((p) => p.place.cityId === where.place.cityId) : all,
    },
  } as any;
}

function svcWith(prisma: any) {
  const cls = new ClsService(new AsyncLocalStorage());
  const owner = new OwnerService(cls);
  const weather = { forLocation: async () => ({ tempC: 20, humidityPct: 50, seasonalLowC: 10, seasonalHighC: 30 }) } as any;
  const svc = new MovingService(prisma, owner, weather, {} as any);
  const run = <T>(fn: () => Promise<T>) => cls.run(async () => { cls.set('actor', { userId: 'u', username: 'n', ownerId: 'o1', role: 'USER', jti: 'j', exp: 9e9 }); return fn(); });
  return { svc, run };
}

describe('MovingService.simulate scoping', () => {
  it('primary WITH plants: returns only primary-city plants, all flagged inPrimaryCity', async () => {
    const all = [plant('p1', 'c-primary'), plant('p2', 'c-other')];
    const { svc, run } = svcWith(makePrisma('c-primary', all));
    const out = await run(() => svc.simulate(1, 2));
    expect(out.map((p) => p.plantId)).toEqual(['p1']);
    expect(out[0].inPrimaryCity).toBe(true);
    expect(out[0].placeCityName).toBe('Primary City');
  });

  it('empty primary: falls back to ALL plants, flagging off-primary ones (bug B8)', async () => {
    const all = [plant('p1', 'c-other'), plant('p2', 'c-other')]; // none in the primary
    const { svc, run } = svcWith(makePrisma('c-empty', all));
    const out = await run(() => svc.simulate(1, 2));
    expect(out.map((p) => p.plantId).sort()).toEqual(['p1', 'p2']);
    expect(out.every((p) => p.inPrimaryCity === false)).toBe(true);
    expect(out[0].placeCityName).toBe('Other City');
  });

  it('no primary: simulates all owner plants, all inPrimaryCity true', async () => {
    const all = [plant('p1', 'c-primary'), plant('p2', 'c-other')];
    const { svc, run } = svcWith(makePrisma(null, all));
    const out = await run(() => svc.simulate(1, 2));
    expect(out.map((p) => p.plantId).sort()).toEqual(['p1', 'p2']);
    expect(out.every((p) => p.inPrimaryCity === true)).toBe(true);
  });
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `npm test -- simulate-scope` → Expected: FAIL (`inPrimaryCity`/`placeCityName` undefined; no empty-primary fallback).

- [ ] **Step 3: Implement.** In `src/moving/moving.service.ts`:

  (a) Add the two fields to the `PlantViability` interface:

```ts
export interface PlantViability extends ViabilityResult {
  plantId: string;
  nickname: string | null;
  speciesSlug: string;
  speciesScientificName: string;
  speciesCommonName: string;
  placeCityName: string;   // the plant's place-city name (for the off-primary warning)
  inPrimaryCity: boolean;  // false → "not in your current city" (drives the UI warning)
}
```

  (b) Replace the plant-loading block inside `simulate(...)` (the `const primary = ...` / `const where = ...` / `const plants = ...` lines) with:

```ts
    const primary = await this.prisma.city.findFirst({ where: { ownerId, isPrimary: true } });
    const include = { species: true, place: { include: { city: true } } } as const;
    let plants = await this.prisma.plant.findMany({
      where: primary ? { ownerId, place: { cityId: primary.id } } : { ownerId },
      include,
    });
    // Empty-primary fallback (bug B8): a primary city holding none of the owner's plants would yield
    // []. Fall back to ALL owner plants; off-primary ones are flagged so the UI can warn per plant.
    if (primary && plants.length === 0) {
      plants = await this.prisma.plant.findMany({ where: { ownerId }, include });
    }
```

  (c) In the `return plants.map((plant) => { ... })` block, add the two fields to the returned object (alongside `speciesCommonName`):

```ts
      return {
        plantId: plant.id,
        nickname: plant.nickname,
        speciesSlug: plant.speciesSlug,
        speciesScientificName: record.scientificName,
        speciesCommonName: primaryCommonName(record),
        placeCityName: plant.place.city.name,
        inPrimaryCity: primary ? plant.place.cityId === primary.id : true,
        ...result,
      };
```

- [ ] **Step 4: Run to verify it passes.** Run: `npm test -- simulate-scope` → Expected: PASS.

- [ ] **Step 5: Verify the older simulate test still passes.** Run: `npm test -- moving.service.simulate.test` → Expected: PASS. (That fake's plant row has no `place.city`; because it uses the no-primary path its assertions don't read the new fields, but the map now reads `plant.place.city.name`.) **If it fails because `plant.place.city` is undefined**, add `city: { id: 'c1', name: 'Anytown' }` to the `place` object of `plantRow` in `src/moving/moving.service.simulate.test.ts` — that is the only change needed there.

- [ ] **Step 6: Commit.**

```bash
git add src/moving/moving.service.ts src/moving/moving.service.simulate-scope.test.ts src/moving/moving.service.simulate.test.ts
git commit -m "fix(moving): empty-primary simulate fallback + per-plant city flags (B8)"
```

---

### Task 2: Re-scope `POST /care-plan/recompute` to the effective owner

**Files:**
- Modify: `src/care-plan/care-plan.controller.ts`
- Modify: `src/care-plan/care-plan.controller.test.ts`

- [ ] **Step 1: Rewrite the controller test.** Replace the `describe('CarePlanController.recompute role gating', ...)` block in `src/care-plan/care-plan.controller.test.ts` with:

```ts
describe('CarePlanController.recompute (effective-owner scoping)', () => {
  it('a USER recomputes their own garden', async () => {
    const { ctrl, recomputeAll, recomputeOwner, run } = setup();
    await run(actor('owner-1', 'USER'), () => ctrl.recompute());
    expect(recomputeOwner).toHaveBeenCalledWith('owner-1');
    expect(recomputeAll).not.toHaveBeenCalled();
  });

  it('an ADMIN recomputes their OWN garden by default (no all-owners recompute over HTTP)', async () => {
    const { ctrl, recomputeAll, recomputeOwner, run } = setup();
    await run(actor('owner-admin', 'ADMIN'), () => ctrl.recompute());
    expect(recomputeOwner).toHaveBeenCalledWith('owner-admin');
    expect(recomputeAll).not.toHaveBeenCalled();
  });

  it('an ADMIN acting-as recomputes the TARGET owner', async () => {
    const { ctrl, recomputeOwner, run } = setup();
    await run({ ...actor('owner-admin', 'ADMIN'), actingAsOwnerId: 'owner-2' }, () => ctrl.recompute());
    expect(recomputeOwner).toHaveBeenCalledWith('owner-2');
  });

  it('today is scoped to the acting actor owner', async () => {
    const { ctrl, todaysTasks, run } = setup();
    await run(actor('owner-9', 'USER'), () => ctrl.today());
    expect(todaysTasks).toHaveBeenCalledWith('owner-9');
  });
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `npm test -- care-plan.controller.test` → Expected: FAIL ("ADMIN recomputes own" expects `recomputeOwner`, but the controller still calls `recomputeAll`).

- [ ] **Step 3: Implement.** In `src/care-plan/care-plan.controller.ts`, replace the `recompute` handler:

```ts
  // Scopes to the EFFECTIVE owner (own by default; the target when acting-as). The all-owners
  // recompute remains available only via the startup/cron job, never over HTTP.
  @Post('recompute')
  async recompute() {
    await this.carePlan.recomputeOwner(this.owner.currentOwnerId());
    return { ok: true };
  }
```

(`recomputeAll` is no longer referenced here; leave the `CarePlanService` method itself untouched — the cron/startup path still uses it.)

- [ ] **Step 4: Run to verify it passes.** Run: `npm test -- care-plan.controller.test` → Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/care-plan/care-plan.controller.ts src/care-plan/care-plan.controller.test.ts
git commit -m "feat(care-plan): recompute scopes to the effective owner (not all owners)"
```

---

### Task 3: Phase verification

- [ ] **Step 1 (verify):** `npm test` → PASS. `npm run build` → PASS.
