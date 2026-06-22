# Edit Phase 2 — Place editing (API) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a place's `name` and `climateControlled` be edited (`PATCH /places/:id`). Changing `climateControlled` recomputes every plant in that place (they share its climate); a `name`-only change does not.

**Architecture:** Add `update` to `PlacesService`, which gains a `CarePlanService` dependency; `PlacesModule` imports `CarePlanModule`. Add `CarePlanService.recomputePlace(placeId)` that recomputes all plants in a place. Ownership: resolve by `{ id, ...ownerFilter() }`.

**Tech Stack:** NestJS, Prisma, class-validator, Vitest.

**Repo:** `repos/my-plants-api`. Branch: `feature/edit-modules`.

---

### Task 1: `UpdatePlaceDto`

**Files:** Create `src/places/update-place.dto.ts`

- [ ] **Step 1: Implement**

```ts
import { IsBoolean, IsOptional, IsString, MinLength } from 'class-validator';

export class UpdatePlaceDto {
  @IsOptional() @IsString() @MinLength(1) name?: string;
  @IsOptional() @IsBoolean() climateControlled?: boolean;
}
```

- [ ] **Step 2: Commit** — `git add src/places/update-place.dto.ts && git commit -m "feat(places): UpdatePlaceDto"`

---

### Task 2: `CarePlanService.recomputePlace`

**Files:** Modify `src/care-plan/care-plan.service.ts`; Test `src/care-plan/care-plan.service.recompute-place.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest';
import { CarePlanService } from './care-plan.service.js';

it('recomputePlace recomputes every plant in the place', async () => {
  const recomputed: string[] = [];
  const prisma = { plant: { findMany: async ({ where }: any) => where.placeId === 'p1' ? [{ id: 'a' }, { id: 'b' }] : [] } } as any;
  const svc = new CarePlanService(prisma, {} as any);
  // Stub the per-plant recompute so this test stays unit-scoped.
  (svc as any).recomputePlant = async (id: string) => { recomputed.push(id); };
  await svc.recomputePlace('p1');
  expect(recomputed).toEqual(['a', 'b']);
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run src/care-plan/care-plan.service.recompute-place.test.ts` → FAIL.

- [ ] **Step 3: Implement** in `src/care-plan/care-plan.service.ts` (next to `recomputeOwner`):

```ts
// Recompute every plant in one place — used when a place's climate-affecting fields change.
async recomputePlace(placeId: string): Promise<void> {
  const plants = await this.prisma.plant.findMany({ where: { placeId }, select: { id: true } });
  for (const p of plants) await this.recomputePlant(p.id);
}
```

- [ ] **Step 4: Run to verify it passes** → PASS.

- [ ] **Step 5: Commit** — `git add src/care-plan/care-plan.service.ts src/care-plan/care-plan.service.recompute-place.test.ts && git commit -m "feat(care-plan): recomputePlace"`

---

### Task 3: `PlacesService.update` (+ module wiring)

**Files:** Modify `src/places/places.service.ts`, `src/places/places.module.ts`, `src/places/places.service.ownership.test.ts`; Create `src/places/places.service.edit.test.ts`

- [ ] **Step 1: Update the existing ownership test for the new constructor arity**

`PlacesService`'s constructor gains a 3rd arg. In `src/places/places.service.ownership.test.ts`, change every `new PlacesService(prisma, owner)` to `new PlacesService(prisma, owner, { recomputePlace: async () => {} } as any)`.

- [ ] **Step 2: Write the failing edit test** — `src/places/places.service.edit.test.ts`

```ts
import { describe, expect, it } from 'vitest';
import { AsyncLocalStorage } from 'node:async_hooks';
import { ClsService } from 'nestjs-cls';
import { NotFoundException } from '@nestjs/common';
import { OwnerService } from '../owner/owner.service.js';
import { PlacesService } from './places.service.js';

const actor = (ownerId: string, role: 'USER' | 'ADMIN') => ({ userId: 'u', username: 'n', ownerId, role, jti: 'j', exp: 9e9 });

function setup() {
  const matches = (row: any, where: any = {}) => Object.entries(where).every(([k, v]) => v === undefined || row[k] === v);
  const seed = { places: [{ id: 'p1', ownerId: 'owner-1', name: 'Sala', climateControlled: false }, { id: 'p2', ownerId: 'owner-2', name: 'Otra', climateControlled: false }] };
  const recomputed: string[] = [];
  const prisma = {
    place: {
      findFirst: async ({ where }: any) => seed.places.find((p) => matches(p, where)) ?? null,
      update: async ({ where, data }: any) => { const p = seed.places.find((x) => x.id === where.id); Object.assign(p, data); return p; },
    },
  } as any;
  const cls = new ClsService(new AsyncLocalStorage());
  const owner = new OwnerService(cls);
  const carePlan = { recomputePlace: async (id: string) => { recomputed.push(id); } } as any;
  const svc = new PlacesService(prisma, owner, carePlan);
  const run = <T>(a: any, fn: () => Promise<T>) => cls.run(async () => { cls.set('actor', a); return fn(); });
  return { svc, run, recomputed, seed };
}

describe('PlacesService.update', () => {
  it('name-only change does not recompute', async () => {
    const { svc, run, recomputed, seed } = setup();
    await run(actor('owner-1', 'USER'), async () => { await svc.update('p1', { name: 'Estudio' }); });
    expect(seed.places.find((p) => p.id === 'p1').name).toBe('Estudio');
    expect(recomputed).toEqual([]);
  });

  it('climateControlled change recomputes the place', async () => {
    const { svc, run, recomputed, seed } = setup();
    await run(actor('owner-1', 'USER'), async () => { await svc.update('p1', { climateControlled: true }); });
    expect(seed.places.find((p) => p.id === 'p1').climateControlled).toBe(true);
    expect(recomputed).toEqual(['p1']);
  });

  it('setting climateControlled to its current value does not recompute', async () => {
    const { svc, run, recomputed } = setup();
    await run(actor('owner-1', 'USER'), async () => { await svc.update('p1', { climateControlled: false }); });
    expect(recomputed).toEqual([]);
  });

  it('a USER cannot edit another owner place', async () => {
    const { svc, run } = setup();
    await run(actor('owner-1', 'USER'), async () => {
      await expect(svc.update('p2', { name: 'x' })).rejects.toBeInstanceOf(NotFoundException);
    });
  });
});
```

- [ ] **Step 3: Run to verify it fails** → FAIL (no `update`).

- [ ] **Step 4: Implement** — in `src/places/places.service.ts` import `CarePlanService` and `UpdatePlaceDto`, add `carePlan` to the constructor, and add:

```ts
async update(id: string, dto: UpdatePlaceDto) {
  const place = await this.prisma.place.findFirst({ where: { id, ...this.owner.ownerFilter() } });
  if (!place) throw new NotFoundException(`Unknown place: ${id}`);
  const data: { name?: string; climateControlled?: boolean } = {};
  let recompute = false;
  if (dto.name !== undefined) data.name = dto.name;
  if (dto.climateControlled !== undefined && dto.climateControlled !== place.climateControlled) {
    data.climateControlled = dto.climateControlled;
    recompute = true;
  }
  if (Object.keys(data).length > 0) await this.prisma.place.update({ where: { id }, data });
  if (recompute) await this.carePlan.recomputePlace(id);
  return this.get(id);
}
```

Constructor becomes: `constructor(private readonly prisma: PrismaService, private readonly owner: OwnerService, private readonly carePlan: CarePlanService) {}`.

In `src/places/places.module.ts`, add `imports: [CarePlanModule]` (import from `../care-plan/care-plan.module.js`).

- [ ] **Step 5: Run to verify it passes** → PASS.

- [ ] **Step 6: Commit** — `git add src/places/places.service.ts src/places/places.module.ts src/places/places.service.edit.test.ts src/places/places.service.ownership.test.ts && git commit -m "feat(places): edit (name/climateControlled) with recompute on climate change"`

---

### Task 4: Controller wiring

**Files:** Modify `src/places/places.controller.ts`

- [ ] **Step 1: Implement** — add `Patch` to imports and:

```ts
@Patch(':id') update(@Param('id') id: string, @Body() dto: UpdatePlaceDto) {
  return this.places.update(id, dto);
}
```

Import `UpdatePlaceDto` from `./update-place.dto.js`.

- [ ] **Step 2: Build + test** — `npm run build && npm test` → green.

- [ ] **Step 3: Commit** — `git add src/places/places.controller.ts && git commit -m "feat(places): PATCH /places/:id"`
