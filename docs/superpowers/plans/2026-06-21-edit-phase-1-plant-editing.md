# Edit Phase 1 — Plant editing + viability preview (API) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a plant's `nickname` and `place` be edited (`PATCH /plants/:id`), and expose a read-only viability preview (`GET /plants/:id/viability-preview?placeId=`) so the web can show the projected semaphore before a move is confirmed.

**Architecture:** Add `update` and `viabilityPreview` to `PlantsService` (which already injects `prisma`, `owner`, `carePlan`, `weather`). A place change recomputes the plant; a nickname-only change does not. Ownership follows the existing per-operation pattern: the plant resolves by `{ id, ...ownerFilter() }`; a target place must belong to the **plant's owner**.

**Tech Stack:** NestJS, Prisma, class-validator, Vitest.

**Repo:** `repos/my-plants-api`. Branch: `feature/edit-modules`.

---

### Task 1: `UpdatePlantDto`

**Files:** Create `src/plants/update-plant.dto.ts`

- [ ] **Step 1: Implement**

```ts
import { IsOptional, IsString, MinLength } from 'class-validator';

export class UpdatePlantDto {
  @IsOptional() @IsString() nickname?: string;        // "" / whitespace → cleared to null
  @IsOptional() @IsString() @MinLength(1) placeId?: string;
}
```

- [ ] **Step 2: Commit** — `git add src/plants/update-plant.dto.ts && git commit -m "feat(plants): UpdatePlantDto"`

---

### Task 2: `PlantsService.update` + `viabilityPreview`

**Files:** Modify `src/plants/plants.service.ts`; Create `src/plants/plants.service.edit.test.ts`

- [ ] **Step 1: Write the failing test**

Mirror the fake-Prisma + CLS actor pattern from `src/plants/plants.service.ownership.test.ts` (copy its `record`, `actor`, `ClsService` setup). Add `plant.update`, a `place.findFirst` that returns a place WITH a nested `city`, a `recomputePlant` spy, and a `weather.forCity` fake.

```ts
import { describe, expect, it } from 'vitest';
import { AsyncLocalStorage } from 'node:async_hooks';
import { ClsService } from 'nestjs-cls';
import { BadRequestException, NotFoundException } from '@nestjs/common';
import { OwnerService } from '../owner/owner.service.js';
import { PlantsService } from './plants.service.js';
// reuse the same `record` constant as plants.service.ownership.test.ts (copy it in)

const actor = (ownerId: string, role: 'USER' | 'ADMIN') => ({ userId: 'u', username: 'n', ownerId, role, jti: 'j', exp: 9e9 });
const placeRow = (id: string, ownerId: string) => ({
  id, ownerId, indoor: true, lightType: 'BRIGHT_INDIRECT', climateControlled: false,
  humidityCharacter: null, indoorTempMinC: null, indoorTempMaxC: null,
  city: { id: `city-${id}`, latitude: 10, longitude: 20, timezone: 'UTC' },
});
const plantRow = (id: string, ownerId: string, placeId: string) => ({
  id, ownerId, placeId, speciesSlug: 'dracaena-trifasciata', nickname: id,
  acquiredOn: new Date('2026-01-01'), species: { scientificName: 'Dracaena trifasciata', record },
});

function setup() {
  const matches = (row: any, where: any = {}) => Object.entries(where).every(([k, v]) => v === undefined || row[k] === v);
  const seed = {
    plants: [plantRow('pl-own', 'owner-1', 'place-a'), plantRow('pl-other', 'owner-2', 'place-x')],
    places: [placeRow('place-a', 'owner-1'), placeRow('place-b', 'owner-1'), placeRow('place-x', 'owner-2'), placeRow('place-y', 'owner-2')],
  };
  const recomputed: string[] = [];
  const prisma = {
    plant: {
      findFirst: async ({ where }: any) => seed.plants.find((p) => matches(p, where)) ?? null,
      update: async ({ where, data }: any) => { const p = seed.plants.find((x) => x.id === where.id); Object.assign(p, data); return p; },
    },
    place: { findFirst: async ({ where }: any) => seed.places.find((p) => matches(p, where)) ?? null },
  } as any;
  const cls = new ClsService(new AsyncLocalStorage());
  const owner = new OwnerService(cls);
  const carePlan = { recomputePlant: async (id: string) => { recomputed.push(id); } } as any;
  const weather = { forCity: async () => ({ tempC: 20, humidityPct: 50, seasonalLowC: 10, seasonalHighC: 30 }) } as any;
  const svc = new PlantsService(prisma, owner, carePlan, weather);
  const run = <T>(a: any, fn: () => Promise<T>) => cls.run(async () => { cls.set('actor', a); return fn(); });
  return { svc, run, recomputed, seed };
}

describe('PlantsService.update', () => {
  it('nickname-only change does not recompute and clears empty to null', async () => {
    const { svc, run, recomputed, seed } = setup();
    await run(actor('owner-1', 'USER'), async () => { await svc.update('pl-own', { nickname: '  ' }); });
    expect(seed.plants.find((p) => p.id === 'pl-own').nickname).toBeNull();
    expect(recomputed).toEqual([]);
  });

  it('place change persists and recomputes', async () => {
    const { svc, run, recomputed, seed } = setup();
    await run(actor('owner-1', 'USER'), async () => { await svc.update('pl-own', { placeId: 'place-b' }); });
    expect(seed.plants.find((p) => p.id === 'pl-own').placeId).toBe('place-b');
    expect(recomputed).toEqual(['pl-own']);
  });

  it('rejects moving to a place of another owner', async () => {
    const { svc, run } = setup();
    await run(actor('owner-1', 'USER'), async () => {
      await expect(svc.update('pl-own', { placeId: 'place-x' })).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  it('a USER cannot edit another owner plant', async () => {
    const { svc, run } = setup();
    await run(actor('owner-1', 'USER'), async () => {
      await expect(svc.update('pl-other', { nickname: 'x' })).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  it('an ADMIN can edit another owner plant, validating the target place against the PLANT owner', async () => {
    const { svc, run, recomputed, seed } = setup();
    await run(actor('owner-1', 'ADMIN'), async () => {
      // pl-other belongs to owner-2; place-y also belongs to owner-2 → allowed.
      await svc.update('pl-other', { placeId: 'place-y' });
    });
    expect(seed.plants.find((p) => p.id === 'pl-other').placeId).toBe('place-y');
    expect(recomputed).toEqual(['pl-other']);
  });
});

describe('PlantsService.viabilityPreview', () => {
  it('returns a viability result for a target place of the plant owner', async () => {
    const { svc, run } = setup();
    await run(actor('owner-1', 'USER'), async () => {
      const v = await svc.viabilityPreview('pl-own', 'place-b');
      expect(v).toHaveProperty('level');
      expect(Array.isArray(v.reasons)).toBe(true);
    });
  });

  it('rejects a place of another owner', async () => {
    const { svc, run } = setup();
    await run(actor('owner-1', 'USER'), async () => {
      await expect(svc.viabilityPreview('pl-own', 'place-x')).rejects.toBeInstanceOf(BadRequestException);
    });
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run src/plants/plants.service.edit.test.ts` → FAIL (methods missing).

- [ ] **Step 3: Implement** in `src/plants/plants.service.ts`. Add the import `import { buildViability } from '../engines/viability.js';` if not present, and `import type { UpdatePlantDto } from './update-plant.dto.js';`. Add:

```ts
async update(id: string, dto: UpdatePlantDto) {
  const plant = await this.prisma.plant.findFirst({ where: { id, ...this.owner.ownerFilter() } });
  if (!plant) throw new NotFoundException(`Unknown plant: ${id}`);

  const data: { nickname?: string | null; placeId?: string } = {};
  let recompute = false;

  if (dto.nickname !== undefined) data.nickname = dto.nickname.trim() || null;

  if (dto.placeId !== undefined && dto.placeId !== plant.placeId) {
    const place = await this.prisma.place.findFirst({ where: { id: dto.placeId, ownerId: plant.ownerId } });
    if (!place) throw new BadRequestException(`Unknown place: ${dto.placeId}`);
    data.placeId = dto.placeId;
    recompute = true;
  }

  if (Object.keys(data).length > 0) await this.prisma.plant.update({ where: { id }, data });
  if (recompute) await this.carePlan.recomputePlant(id);
  return this.get(id);
}

async viabilityPreview(id: string, placeId: string) {
  const plant = await this.prisma.plant.findFirst({ where: { id, ...this.owner.ownerFilter() }, include: { species: true } });
  if (!plant) throw new NotFoundException(`Unknown plant: ${id}`);
  const place = await this.prisma.place.findFirst({ where: { id: placeId, ownerId: plant.ownerId }, include: { city: true } });
  if (!place) throw new BadRequestException(`Unknown place: ${placeId}`);
  const record = parseSpeciesRecord(plant.species.record);
  const weather = await this.weather.forCity(place.city.id, place.city.latitude, place.city.longitude);
  return buildViability(
    record,
    {
      indoor: place.indoor, climateControlled: place.climateControlled, humidityCharacter: place.humidityCharacter,
      indoorTempMinC: place.indoorTempMinC, indoorTempMaxC: place.indoorTempMaxC, lightType: place.lightType,
    },
    weather ? { tempC: weather.tempC, humidityPct: weather.humidityPct, seasonalLowC: weather.seasonalLowC, seasonalHighC: weather.seasonalHighC } : null,
  );
}
```

> Note: `update`'s `findFirst` does not need `include: { species: true }` (it only checks existence/ownership and reads `placeId`/`ownerId`); `get(id)` re-fetches with names for the return.

- [ ] **Step 4: Run to verify it passes** — `npx vitest run src/plants/plants.service.edit.test.ts` → PASS.

- [ ] **Step 5: Commit** — `git add src/plants/plants.service.ts src/plants/plants.service.edit.test.ts && git commit -m "feat(plants): edit (nickname/place) + viability preview"`

---

### Task 3: Controller wiring

**Files:** Modify `src/plants/plants.controller.ts`

- [ ] **Step 1: Implement** — add `Patch`, `Query`, `BadRequestException` to the imports and the routes:

```ts
@Patch(':id') update(@Param('id') id: string, @Body() dto: UpdatePlantDto) {
  return this.plants.update(id, dto);
}

@Get(':id/viability-preview') preview(@Param('id') id: string, @Query('placeId') placeId?: string) {
  if (!placeId) throw new BadRequestException('placeId is required');
  return this.plants.viabilityPreview(id, placeId);
}
```

Import `UpdatePlantDto` from `./update-plant.dto.js`. (The two-segment `:id/viability-preview` route does not collide with `:id`.)

- [ ] **Step 2: Build + test** — `npm run build && npm test` → green.

- [ ] **Step 3: Commit** — `git add src/plants/plants.controller.ts && git commit -m "feat(plants): PATCH /plants/:id + GET /plants/:id/viability-preview"`
