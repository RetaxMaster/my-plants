# Edit Phase 4 — Honest Moving (API) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Moving stops assuming every plant is with you. `simulate` and `applyDueMovesForOwner` scope to the plants/places at your **current (primary) city**. The simulate-vs-apply indoor/outdoor asymmetry is preserved on purpose (apply still repoints only outdoor places). No migration.

**Architecture:** `simulate` restricts the plant set to `place.cityId === primary.id`; `applyDueMovesForOwner` resolves the current primary **inside each move's transaction** and repoints only that old-primary city's outdoor places. Both keep a no-primary fallback to today's all-plants behavior.

**Tech Stack:** NestJS, Prisma, Vitest.

**Repo:** `repos/my-plants-api`. Branch: `feature/edit-modules`.

---

### Task 1: `simulate` — scope to current-city plants

**Files:** Modify `src/moving/moving.service.ts`; Test `src/moving/moving.service.simulate-scope.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest';
import { AsyncLocalStorage } from 'node:async_hooks';
import { ClsService } from 'nestjs-cls';
import { OwnerService } from '../owner/owner.service.js';
import { MovingService } from './moving.service.js';
// reuse the `record` constant from plants.service.ownership.test.ts

const placeFields = { indoor: false, climateControlled: false, humidityCharacter: null, indoorTempMinC: null, indoorTempMaxC: null, lightType: 'BRIGHT_INDIRECT' };
const plant = (id: string, cityId: string) => ({ id, ownerId: 'o1', nickname: id, speciesSlug: 'dracaena-trifasciata', species: { record }, place: { ...placeFields, cityId } });

function makePrisma(hasPrimary: boolean) {
  const all = [plant('p1', 'c-primary'), plant('p2', 'c-other')];
  return {
    city: { findFirst: async ({ where }: any) => (where.isPrimary && hasPrimary ? { id: 'c-primary', timezone: 'UTC' } : null) },
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
  it('excludes plants whose place is in a non-primary city', async () => {
    const { svc, run } = svcWith(makePrisma(true));
    const out = await run(() => svc.simulate(1, 2));
    expect(out.map((p) => p.plantId)).toEqual(['p1']);
  });

  it('no-primary fallback simulates all owner plants', async () => {
    const { svc, run } = svcWith(makePrisma(false));
    const out = await run(() => svc.simulate(1, 2));
    expect(out.map((p) => p.plantId).sort()).toEqual(['p1', 'p2']);
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run src/moving/moving.service.simulate-scope.test.ts` → FAIL (current simulate returns both).

- [ ] **Step 3: Implement** — in `simulate`, after resolving `ownerId` and `weather`, add the primary lookup and scope the query:

```ts
const primary = await this.prisma.city.findFirst({ where: { ownerId, isPrimary: true } });
const where = primary ? { ownerId, place: { cityId: primary.id } } : { ownerId };
const plants = await this.prisma.plant.findMany({ where, include: { species: true, place: true } });
```

(Replaces the existing `findMany({ where: { ownerId }, ... })`.) The rest of the mapping is unchanged.

- [ ] **Step 4: Fix the pre-existing simulate test (mandatory)** — `src/moving/moving.service.simulate.test.ts`'s fake Prisma only has `plant.findMany`; `simulate` now calls `this.prisma.city.findFirst` first. Add a `city: { findFirst: async () => null }` delegate to that fake so it takes the no-primary fallback and keeps returning all plants (its original intent is preserved).

- [ ] **Step 5: Run to verify it passes** → PASS (new + existing simulate tests).

- [ ] **Step 6: Commit** — `git add src/moving/moving.service.ts src/moving/moving.service.simulate-scope.test.ts src/moving/moving.service.simulate.test.ts && git commit -m "feat(moving): simulate only the plants at the current primary city"`

---

### Task 2: `applyDueMovesForOwner` — repoint only old-primary outdoor places (per move)

**Files:** Modify `src/moving/moving.service.ts`; Test `src/moving/moving.service.apply-scope.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest';
import { MovingService } from './moving.service.js';

it('repoints only the old-primary city outdoor places, resolved inside the move tx', async () => {
  const placeUpdateCalls: any[] = [];
  const moves = [{ id: 'm1', targetCityId: 'c2', applied: false, moveOn: new Date('2026-06-01') }];
  const tx = {
    city: {
      findFirst: async ({ where }: any) => (where.isPrimary ? { id: 'c1', timezone: 'UTC' } : null), // current primary
      updateMany: async () => ({ count: 1 }),
      update: async () => ({}),
    },
    place: { updateMany: async ({ where }: any) => { placeUpdateCalls.push(where); return { count: 1 }; } },
    scheduledMove: { update: async () => ({}) },
  };
  const prisma = {
    city: { findFirst: async ({ where }: any) => (where.isPrimary ? { id: 'c1', timezone: 'UTC' } : null) },
    scheduledMove: { findMany: async () => moves },
    $transaction: async (fn: any) => fn(tx),
  } as any;
  const svc = new MovingService(prisma, {} as any, {} as any, {} as any);
  const n = await svc.applyDueMovesForOwner('o1', new Date('2026-06-21T12:00:00Z'));
  expect(n).toBe(1);
  expect(placeUpdateCalls).toEqual([{ ownerId: 'o1', indoor: false, cityId: 'c1' }]);
});

it('a chain of due moves repoints the right places per move (old primary resolved inside each tx)', async () => {
  let currentPrimary = 'c1';
  const placeUpdateCalls: any[] = [];
  const moves = [
    { id: 'm1', targetCityId: 'c2', applied: false, moveOn: new Date('2026-06-01') },
    { id: 'm2', targetCityId: 'c3', applied: false, moveOn: new Date('2026-06-02') },
  ];
  const tx = {
    city: {
      findFirst: async ({ where }: any) => (where.isPrimary ? { id: currentPrimary, timezone: 'UTC' } : null),
      updateMany: async () => ({ count: 1 }),
      update: async ({ where, data }: any) => { if (data.isPrimary) currentPrimary = where.id; return {}; },
    },
    place: { updateMany: async ({ where }: any) => { placeUpdateCalls.push(where); return { count: 1 }; } },
    scheduledMove: { update: async () => ({}) },
  };
  const prisma = {
    city: { findFirst: async ({ where }: any) => (where.isPrimary ? { id: currentPrimary, timezone: 'UTC' } : null) },
    scheduledMove: { findMany: async () => moves },
    $transaction: async (fn: any) => fn(tx),
  } as any;
  const svc = new MovingService(prisma, {} as any, {} as any, {} as any);
  const n = await svc.applyDueMovesForOwner('o1', new Date('2026-06-21T12:00:00Z'));
  expect(n).toBe(2);
  // m1 moves c1's outdoor places to c2; m2 then moves c2's outdoor places to c3.
  expect(placeUpdateCalls).toEqual([
    { ownerId: 'o1', indoor: false, cityId: 'c1' },
    { ownerId: 'o1', indoor: false, cityId: 'c2' },
  ]);
});
```

- [ ] **Step 2: Run to verify it fails** — FAIL (current code uses `{ ownerId, indoor: false }`, no `cityId`).

- [ ] **Step 3: Implement** — replace the transaction body in `applyDueMovesForOwner`:

```ts
for (const move of due) {
  await this.prisma.$transaction(async (tx) => {
    // Resolve the CURRENT primary inside the tx so a chain of due moves repoints the right places each time.
    const current = await tx.city.findFirst({ where: { ownerId, isPrimary: true } });
    const placeWhere = current
      ? { ownerId, indoor: false, cityId: current.id }
      : { ownerId, indoor: false }; // no-primary fallback: today's behavior
    await tx.city.updateMany({ where: { ownerId }, data: { isPrimary: false } });
    await tx.city.update({ where: { id: move.targetCityId }, data: { isPrimary: true } });
    await tx.place.updateMany({ where: placeWhere, data: { cityId: move.targetCityId } });
    await tx.scheduledMove.update({ where: { id: move.id }, data: { applied: true } });
  });
}
return due.length;
```

The top-of-method primary lookup that computes the due `cutoff` stays as-is (the cutoff is one date threshold for the batch).

- [ ] **Step 4: Fix the pre-existing apply test (mandatory)** — `src/moving/moving.service.apply.test.ts`'s transactional fake has only `updateMany`/`update`; the new code calls `tx.city.findFirst` inside each tx. This update is required regardless of whether that test asserts the place filter: add `city.findFirst: async ({ where }) => (where.isPrimary ? { id: '<currentPrimaryId>', timezone: 'UTC' } : null)` to its `tx` (and, if its `place.updateMany` expectation exists, extend it to include `cityId: '<currentPrimaryId>'`). Use whatever city id that test treats as the current primary.

- [ ] **Step 5: Run to verify it passes** → PASS. Then `npm test` (full suite) → green.

- [ ] **Step 6: Commit** — `git add src/moving/moving.service.ts src/moving/moving.service.apply-scope.test.ts src/moving/moving.service.apply.test.ts && git commit -m "feat(moving): apply repoints only old-primary outdoor places (per-move)"`
