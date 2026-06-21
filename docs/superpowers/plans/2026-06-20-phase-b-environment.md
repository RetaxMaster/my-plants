# Phase B — Environment Setup (Cities Bank + Rich Places + Moving Search) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hand-typed city coordinates with an Open-Meteo geocoded city bank, capture every supported environmental factor in the places form, and make the Moving view simulate/schedule against any searched city — all sharing one geocoding client, one generalized weather fetcher, and one reusable `CitySearch` component (no forks).

**Architecture:** A new geocoding client lives in the weather module alongside the existing forecast client; a thin service method exposes `GET /cities/search?q=`. `WeatherService` is generalized to `forLocation(key, lat, lng)` so both saved cities (`key = cityId`) and ad-hoc coordinates (`key = "<lat>,<lng>"`) share the same in-memory cache + 3h TTL. The Moving endpoints change to accept geocoded coordinates: `simulate` writes nothing; `schedule` finds-or-creates the owner's `City` by coordinates rounded to 4 decimals (floats are never compared for exact equality). On the frontend, a single `CitySearch.vue` component powers both the rebuilt cities form and the rebuilt moving page; the places form gains the indoor-only optional fields the DTO already accepts.

**Tech Stack:** NestJS + Prisma (MariaDB), ESM (`.js` import specifiers, `NodeNext`), `class-validator` DTOs, Vitest (`npm test`); Nuxt 3 + Vue 3 `<script setup lang="ts">` + Nuxt UI, verified with `npm run build && npm run typecheck`.

---

## Conventions (read once before starting)

- **API repo:** `/home/retaxmaster/projects/my-plants/repos/my-plants-api`. Run tests with `npm test` (alias for `vitest run`). All relative imports use the `.js` specifier even for `.ts` files (NodeNext). Prisma models map camelCase fields to snake_case columns via `@map`; never write a raw connection string. Owner scoping is done with `await this.owner.currentOwnerId()` and a `where: { ownerId }` filter — every read/write is owner-scoped.
- **Web repo:** `/home/retaxmaster/projects/my-plants/repos/my-plants-web`. Verify with `npm run build && npm run typecheck`. `nuxt.config.ts` sets `typescript.typeCheck: false`, so `npm run build` does NOT catch TypeScript type errors; the `typecheck` script (`nuxt typecheck` = `vue-tsc`) is what catches them, so always run both. Components live in `components/`, pages in `pages/`, the HTTP client in `composables/useApi.ts`, shared types in `types/api.ts`.
- **MariaDB date rule:** irrelevant here (no date/time column comparisons in Phase B) except `moveOn`, which is already bound as a native `new Date(moveOn)` — keep it that way.
- **Never write `.env`.** No migration is needed in this phase (no schema changes).
- **Open-Meteo Geocoding API** (free, no key): `GET https://geocoding-api.open-meteo.com/v1/search?name=<q>&count=10&language=es&format=json`. Response shape: `{ results?: [{ name, latitude, longitude, timezone, country, admin1 }] }`. When the query matches nothing, `results` is **absent** (not `[]`) — handle that. On any network/HTTP error, return `[]`; never throw (mirror `weather.service.ts:19-26` try/catch-to-null posture).

## Shared contract (use these EXACT names — other phases' plans depend on them)

- Backend type returned by `GET /cities/search`: `CitySearchResult = { name: string; country: string; admin1: string; latitude: number; longitude: number; timezone: string }`.
- Frontend type (same shape) in `types/api.ts`: `CitySearchResult`.
- `api.searchCities(q: string)` → `api<CitySearchResult[]>(\`/cities/search?q=${encodeURIComponent(q)}\`)`.
- `api.simulateMove(latitude: number, longitude: number)` → `api<PlantViability[]>('/moving/simulate', { method:'POST', body:{ latitude, longitude } })`.
- `api.scheduleMove(sel: { name: string; latitude: number; longitude: number; timezone: string }, moveOn: string)` → `api<{ id: string }>('/moving/schedule', { method:'POST', body:{ ...sel, moveOn } })`.
- `PlantViability` already exists in `types/api.ts:44`.

## File structure (created / modified in this phase)

**API (`repos/my-plants-api`):**
- Create: `src/weather/open-meteo.geocoding.client.ts` — geocoding HTTP client + `CitySearchResult` type.
- Create: `src/weather/open-meteo.geocoding.client.test.ts` — unit tests (mocked `fetch`).
- Modify: `src/weather/weather.service.ts` — add `forLocation(key, lat, lng)`; `forCity` becomes a thin wrapper.
- Create: `src/weather/weather.service.test.ts` — unit tests for `forLocation`/`forCity` cache reuse (mocked client).
- Modify: `src/weather/weather.module.ts` — register + export the geocoding client.
- Modify: `src/cities/cities.controller.ts` — add `GET /cities/search`.
- Modify: `src/cities/cities.service.ts` — add `search(q)` delegating to the geocoding client.
- Modify: `src/cities/cities.module.ts` — import `WeatherModule` so the geocoding client is injectable.
- Create: `src/common/geo/round-coord.ts` — `roundCoord4` helper.
- Create: `src/common/geo/round-coord.test.ts` — unit tests.
- Modify: `src/moving/moving.controller.ts` — new `SimulateDto` / `ScheduleDto`.
- Modify: `src/moving/moving.service.ts` — `simulate(lat, lng)` via `forLocation`; `schedule(sel, moveOn)` find-or-creates the city.
- Create: `src/moving/moving.service.find-or-create-city.test.ts` — unit test for the find-or-create matching logic via `roundCoord4`.

**Web (`repos/my-plants-web`):**
- Create: `components/CitySearch.vue` — reusable search-and-pick component.
- Modify: `types/api.ts` — add `CitySearchResult`.
- Modify: `composables/useApi.ts` — add `searchCities`; change `simulateMove`/`scheduleMove` signatures.
- Create: `utils/cityLabel.ts` — `friendlyCityLabel(sel)` builder.
- Create: `utils/cityLabel.test.ts` — Vitest unit test for the pure helper (the web repo HAS Vitest: `vitest.config.ts` exists and `package.json` defines `"test": "vitest run"`). See Task 9.
- Modify: `pages/cities/index.vue` — rebuild create form around `CitySearch`.
- Modify: `pages/places/index.vue` — add indoor-only optional fields.
- Modify: `pages/moving.vue` — replace dropdown with `CitySearch`.

> **Seam note (do NOT act on it here):** `moving.service.simulate` contains an inline plant→place→weather→`ViabilityInput` mapping (`moving.service.ts:38-61`). Phase C extracts it into a shared `buildViability` helper. **Leave it exactly as-is in this phase** — only swap the weather source from `forCity` to `forLocation`.

---

## Task 1: Geocoding client (new, mocked-fetch unit test)

**Files:**
- Create: `src/weather/open-meteo.geocoding.client.ts`
- Test: `src/weather/open-meteo.geocoding.client.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/weather/open-meteo.geocoding.client.test.ts`:

```typescript
import { afterEach, describe, expect, it, vi } from 'vitest';
import { OpenMeteoGeocodingClient } from './open-meteo.geocoding.client.js';

const client = new OpenMeteoGeocodingClient();

afterEach(() => vi.restoreAllMocks());

function mockFetch(impl: () => Promise<Partial<Response>>) {
  vi.stubGlobal('fetch', vi.fn(impl as unknown as typeof fetch));
}

describe('OpenMeteoGeocodingClient.search', () => {
  it('maps Open-Meteo results to CitySearchResult[]', async () => {
    mockFetch(async () => ({
      ok: true,
      json: async () => ({
        results: [
          {
            name: 'Guadalajara',
            latitude: 20.6668,
            longitude: -103.3918,
            timezone: 'America/Mexico_City',
            country: 'Mexico',
            admin1: 'Jalisco',
          },
        ],
      }),
    }));
    const out = await client.search('guadalajara');
    expect(out).toEqual([
      {
        name: 'Guadalajara',
        country: 'Mexico',
        admin1: 'Jalisco',
        latitude: 20.6668,
        longitude: -103.3918,
        timezone: 'America/Mexico_City',
      },
    ]);
  });

  it('returns [] when the API omits results (no match)', async () => {
    mockFetch(async () => ({ ok: true, json: async () => ({}) }));
    expect(await client.search('zzzznotacity')).toEqual([]);
  });

  it('returns [] (never throws) on a non-ok HTTP status', async () => {
    mockFetch(async () => ({ ok: false, status: 503, json: async () => ({}) }));
    expect(await client.search('x')).toEqual([]);
  });

  it('returns [] (never throws) on a network error', async () => {
    mockFetch(async () => {
      throw new Error('network down');
    });
    expect(await client.search('x')).toEqual([]);
  });

  it('returns [] for a blank query without calling fetch', async () => {
    const spy = vi.fn();
    vi.stubGlobal('fetch', spy as unknown as typeof fetch);
    expect(await client.search('   ')).toEqual([]);
    expect(spy).not.toHaveBeenCalled();
  });

  it('defaults missing country/admin1 to empty strings', async () => {
    mockFetch(async () => ({
      ok: true,
      json: async () => ({
        results: [{ name: 'Somewhere', latitude: 1, longitude: 2, timezone: 'UTC' }],
      }),
    }));
    const out = await client.search('somewhere');
    expect(out[0]).toEqual({
      name: 'Somewhere',
      country: '',
      admin1: '',
      latitude: 1,
      longitude: 2,
      timezone: 'UTC',
    });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- open-meteo.geocoding.client`
Expected: FAIL — `Cannot find module './open-meteo.geocoding.client.js'`.

- [ ] **Step 3: Write minimal implementation**

Create `src/weather/open-meteo.geocoding.client.ts`:

```typescript
import { Injectable, Logger } from '@nestjs/common';

export interface CitySearchResult {
  name: string;
  country: string;
  admin1: string;
  latitude: number;
  longitude: number;
  timezone: string;
}

interface RawResult {
  name: string;
  latitude: number;
  longitude: number;
  timezone: string;
  country?: string;
  admin1?: string;
}

@Injectable()
export class OpenMeteoGeocodingClient {
  private readonly log = new Logger(OpenMeteoGeocodingClient.name);

  // Proxies Open-Meteo's free, key-less geocoding API. Mirrors the weather client's
  // failure posture: any network/HTTP error degrades to [] and is logged, never thrown,
  // so the endpoint stays available even when the upstream is down.
  async search(query: string): Promise<CitySearchResult[]> {
    const q = query.trim();
    if (q.length === 0) return [];

    const url = new URL('https://geocoding-api.open-meteo.com/v1/search');
    url.searchParams.set('name', q);
    url.searchParams.set('count', '10');
    url.searchParams.set('language', 'es');
    url.searchParams.set('format', 'json');

    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
      if (!res.ok) throw new Error(`Open-Meteo geocoding ${res.status}`);
      const data = (await res.json()) as { results?: RawResult[] };
      return (data.results ?? []).map((r) => ({
        name: r.name,
        country: r.country ?? '',
        admin1: r.admin1 ?? '',
        latitude: r.latitude,
        longitude: r.longitude,
        timezone: r.timezone,
      }));
    } catch (err) {
      this.log.warn(`Geocoding failed for "${q}"; returning []: ${String(err)}`);
      return [];
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- open-meteo.geocoding.client`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weather/open-meteo.geocoding.client.ts src/weather/open-meteo.geocoding.client.test.ts
git commit -m "feat(weather): add Open-Meteo geocoding client degrading to [] on failure"
```

---

## Task 2: Generalize WeatherService to forLocation (no fork)

**Files:**
- Modify: `src/weather/weather.service.ts:16-27`
- Test: `src/weather/weather.service.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/weather/weather.service.test.ts`:

```typescript
import { describe, expect, it, vi } from 'vitest';
import { WeatherService } from './weather.service.js';
import type { OpenMeteoClient, CurrentWeather } from './open-meteo.client.js';

const sample: CurrentWeather = { tempC: 22, humidityPct: 50, seasonalLowC: 16, seasonalHighC: 28 };

function makeService(fetchImpl: () => Promise<CurrentWeather>) {
  const client = { fetch: vi.fn(fetchImpl) } as unknown as OpenMeteoClient;
  return { svc: new WeatherService(client), client };
}

describe('WeatherService.forLocation', () => {
  it('fetches on a cache miss and returns the value', async () => {
    const { svc, client } = makeService(async () => sample);
    const out = await svc.forLocation('19.43,-99.13', 19.43, -99.13);
    expect(out).toEqual(sample);
    expect(client.fetch).toHaveBeenCalledTimes(1);
  });

  it('reuses the cache for the same key within TTL (no second fetch)', async () => {
    const { svc, client } = makeService(async () => sample);
    await svc.forLocation('k', 1, 2);
    await svc.forLocation('k', 1, 2);
    expect(client.fetch).toHaveBeenCalledTimes(1);
  });

  it('keys the cache per location (different keys each fetch once)', async () => {
    const { svc, client } = makeService(async () => sample);
    await svc.forLocation('a', 1, 2);
    await svc.forLocation('b', 3, 4);
    expect(client.fetch).toHaveBeenCalledTimes(2);
  });

  it('returns null on failure with an empty cache', async () => {
    const { svc } = makeService(async () => {
      throw new Error('down');
    });
    expect(await svc.forLocation('k', 1, 2)).toBeNull();
  });
});

describe('WeatherService.forCity', () => {
  it('delegates to forLocation using cityId as the cache key', async () => {
    const { svc, client } = makeService(async () => sample);
    const out = await svc.forCity('city-1', 1, 2);
    expect(out).toEqual(sample);
    // Same city id is a cache hit -> still one fetch.
    await svc.forCity('city-1', 1, 2);
    expect(client.fetch).toHaveBeenCalledTimes(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- weather.service`
Expected: FAIL — `svc.forLocation is not a function`.

- [ ] **Step 3: Write minimal implementation**

Replace the body of `src/weather/weather.service.ts` (lines 16-27, the `forCity` method) with `forLocation` plus a thin `forCity` wrapper. The full file becomes:

```typescript
import { Injectable, Logger } from '@nestjs/common';
import { OpenMeteoClient, type CurrentWeather } from './open-meteo.client.js';

interface CacheEntry { value: CurrentWeather; at: number }
const TTL_MS = 3 * 60 * 60 * 1000; // 3 hours

@Injectable()
export class WeatherService {
  private readonly log = new Logger(WeatherService.name);
  private readonly cache = new Map<string, CacheEntry>();

  constructor(private readonly client: OpenMeteoClient) {}

  // Generalized weather fetch keyed by an arbitrary string. Saved cities pass cityId;
  // ad-hoc Moving targets pass "<lat>,<lng>". Returns fresh weather, a still-valid cache
  // hit, a stale cache on failure, or null if we have nothing — never throws.
  // NOTE: ad-hoc coordinate keys make this in-memory cache unbounded across distinct
  // searched coordinates. Acceptable for local single-user; add eviction only if it matters.
  async forLocation(key: string, latitude: number, longitude: number): Promise<CurrentWeather | null> {
    const hit = this.cache.get(key);
    if (hit && Date.now() - hit.at < TTL_MS) return hit.value;
    try {
      const value = await this.client.fetch(latitude, longitude);
      this.cache.set(key, { value, at: Date.now() });
      return value;
    } catch (err) {
      this.log.warn(`Open-Meteo failed for ${key}; using ${hit ? 'stale cache' : 'no'} weather: ${String(err)}`);
      return hit?.value ?? null;
    }
  }

  // Thin wrapper: a saved city caches under its id.
  async forCity(cityId: string, latitude: number, longitude: number): Promise<CurrentWeather | null> {
    return this.forLocation(cityId, latitude, longitude);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- weather.service`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weather/weather.service.ts src/weather/weather.service.test.ts
git commit -m "refactor(weather): generalize WeatherService to forLocation; forCity becomes a wrapper"
```

---

## Task 3: Wire the geocoding client into the weather module

**Files:**
- Modify: `src/weather/weather.module.ts:1-6`

- [ ] **Step 1: Update the module (no separate test — covered by compile + downstream tests)**

Replace the full contents of `src/weather/weather.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { OpenMeteoClient } from './open-meteo.client.js';
import { OpenMeteoGeocodingClient } from './open-meteo.geocoding.client.js';
import { WeatherService } from './weather.service.js';

@Module({
  providers: [OpenMeteoClient, OpenMeteoGeocodingClient, WeatherService],
  exports: [WeatherService, OpenMeteoGeocodingClient],
})
export class WeatherModule {}
```

- [ ] **Step 2: Verify the project still compiles and tests pass**

Run: `npm run typecheck && npm test`
Expected: typecheck clean; full suite PASS (includes Tasks 1-2).

- [ ] **Step 3: Commit**

```bash
git add src/weather/weather.module.ts
git commit -m "chore(weather): register and export OpenMeteoGeocodingClient"
```

---

## Task 4: GET /cities/search endpoint

**Files:**
- Modify: `src/cities/cities.service.ts:1-8` (constructor) and add `search`
- Modify: `src/cities/cities.controller.ts:1-13`
- Modify: `src/cities/cities.module.ts:1-6` (import WeatherModule)

- [ ] **Step 1: Wire WeatherModule into CitiesModule**

Replace the full contents of `src/cities/cities.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { WeatherModule } from '../weather/weather.module.js';
import { CitiesController } from './cities.controller.js';
import { CitiesService } from './cities.service.js';

@Module({
  imports: [WeatherModule],
  controllers: [CitiesController],
  providers: [CitiesService],
  exports: [CitiesService],
})
export class CitiesModule {}
```

- [ ] **Step 2: Add `search` to CitiesService**

In `src/cities/cities.service.ts`, update the imports and constructor and add the method. The top of the file (imports + constructor) becomes:

```typescript
import { Injectable, NotFoundException } from '@nestjs/common';
import { OwnerService } from '../owner/owner.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { OpenMeteoGeocodingClient, type CitySearchResult } from '../weather/open-meteo.geocoding.client.js';
import type { CreateCityDto } from './create-city.dto.js';

@Injectable()
export class CitiesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly owner: OwnerService,
    private readonly geocoding: OpenMeteoGeocodingClient,
  ) {}

  // Proxies the geocoding bank. Not owner-scoped: the candidate list is public reference
  // data, not the owner's saved cities. Degrades to [] (the client never throws).
  search(query: string): Promise<CitySearchResult[]> {
    return this.geocoding.search(query);
  }
```

Leave the existing `list`, `create`, `get`, `makePrimary` methods unchanged below it.

- [ ] **Step 3: Add the controller route**

Replace the full contents of `src/cities/cities.controller.ts`:

```typescript
import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { CitiesService } from './cities.service.js';
import { CreateCityDto } from './create-city.dto.js';

@Controller('cities')
export class CitiesController {
  constructor(private readonly cities: CitiesService) {}

  @Get() list() { return this.cities.list(); }
  @Get('search') search(@Query('q') q = '') { return this.cities.search(q); }
  @Post() create(@Body() dto: CreateCityDto) { return this.cities.create(dto); }
  @Get(':id') get(@Param('id') id: string) { return this.cities.get(id); }
  @Post(':id/make-primary') makePrimary(@Param('id') id: string) { return this.cities.makePrimary(id); }
}
```

> **Route ordering matters:** `@Get('search')` is declared **before** `@Get(':id')` so the literal path is matched before the wildcard param. NestJS resolves explicit routes ahead of params here, but keeping the order makes intent obvious.

- [ ] **Step 4: Verify**

Run: `npm run typecheck && npm test`
Expected: typecheck clean; full suite PASS (no behavior regressions; new route compiles).

- [ ] **Step 5: Commit**

```bash
git add src/cities/cities.controller.ts src/cities/cities.service.ts src/cities/cities.module.ts
git commit -m "feat(cities): add GET /cities/search proxying the geocoding bank"
```

---

## Task 5: roundCoord4 helper (find-or-create matching)

**Files:**
- Create: `src/common/geo/round-coord.ts`
- Test: `src/common/geo/round-coord.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/common/geo/round-coord.test.ts`:

```typescript
import { describe, expect, it } from 'vitest';
import { roundCoord4 } from './round-coord.js';

describe('roundCoord4', () => {
  it('rounds to 4 decimal places', () => {
    expect(roundCoord4(20.66682)).toBe(20.6668);
    expect(roundCoord4(-103.39182)).toBe(-103.3918);
  });

  it('rounds half away from the boundary consistently', () => {
    expect(roundCoord4(0.00005)).toBe(0.0001);
  });

  it('leaves a value already at 4 decimals unchanged', () => {
    expect(roundCoord4(19.4326)).toBe(19.4326);
  });

  it('maps two near-identical floats to the same rounded value', () => {
    expect(roundCoord4(20.66680001)).toBe(roundCoord4(20.66684999));
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- round-coord`
Expected: FAIL — `Cannot find module './round-coord.js'`.

- [ ] **Step 3: Write minimal implementation**

Create `src/common/geo/round-coord.ts`:

```typescript
// Rounds a latitude/longitude to 4 decimal places (~11 m precision). Used to match a
// geocoded selection against an already-saved City without comparing floats for exact
// equality — distinct searches of the same place yield the same rounded key.
export function roundCoord4(value: number): number {
  return Math.round(value * 10_000) / 10_000;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- round-coord`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/common/geo/round-coord.ts src/common/geo/round-coord.test.ts
git commit -m "feat(geo): add roundCoord4 helper for coordinate matching"
```

---

## Task 6: Moving DTOs — geocoded bodies

**Files:**
- Modify: `src/moving/moving.controller.ts:1-17`

- [ ] **Step 1: Replace the DTOs and route wiring**

Replace the full contents of `src/moving/moving.controller.ts`:

```typescript
import { Body, Controller, Post } from '@nestjs/common';
import { IsDateString, IsNumber, IsString, Max, Min, MinLength } from 'class-validator';
import { MovingService } from './moving.service.js';

class SimulateDto {
  @IsNumber() @Min(-90) @Max(90) latitude!: number;
  @IsNumber() @Min(-180) @Max(180) longitude!: number;
}

class ScheduleDto {
  @IsString() @MinLength(1) name!: string;
  @IsNumber() @Min(-90) @Max(90) latitude!: number;
  @IsNumber() @Min(-180) @Max(180) longitude!: number;
  @IsString() @MinLength(1) timezone!: string;
  @IsDateString() moveOn!: string;
}

@Controller('moving')
export class MovingController {
  constructor(private readonly moving: MovingService) {}

  @Post('simulate') simulate(@Body() dto: SimulateDto) {
    return this.moving.simulate(dto.latitude, dto.longitude);
  }

  @Post('schedule') schedule(@Body() dto: ScheduleDto) {
    return this.moving.schedule(
      { name: dto.name, latitude: dto.latitude, longitude: dto.longitude, timezone: dto.timezone },
      dto.moveOn,
    );
  }
}
```

> This will not compile until Task 7 changes `MovingService.simulate`/`schedule` signatures. Do Tasks 6 and 7 together before running the suite.

- [ ] **Step 2: Commit (after Task 7 verifies)**

Hold the commit until Task 7 Step 5 — they ship together.

---

## Task 7: MovingService — simulate via forLocation; schedule find-or-creates the city

**Files:**
- Modify: `src/moving/moving.service.ts:28-72`
- Test: `src/moving/moving.service.find-or-create-city.test.ts`

- [ ] **Step 1: Write the failing test (find-or-create matching logic)**

The find-or-create is owner-scoped Prisma I/O; we unit-test the **matching decision** by injecting a fake Prisma whose `city.findMany` returns saved cities and asserting `schedule` reuses a coordinate-matching city (rounded to 4 decimals) and creates only when none matches.

Create `src/moving/moving.service.find-or-create-city.test.ts`:

```typescript
import { describe, expect, it, vi } from 'vitest';
import { MovingService } from './moving.service.js';

function makeService(savedCities: Array<{ id: string; latitude: number; longitude: number }>) {
  const created: Array<Record<string, unknown>> = [];
  const moves: Array<Record<string, unknown>> = [];
  const prisma = {
    city: {
      findMany: vi.fn(async () => savedCities),
      create: vi.fn(async ({ data }: { data: Record<string, unknown> }) => {
        const row = { id: `city-${created.length + 1}`, ...data };
        created.push(row);
        return row;
      }),
    },
    scheduledMove: {
      create: vi.fn(async ({ data }: { data: Record<string, unknown> }) => {
        const row = { id: `move-${moves.length + 1}`, ...data };
        moves.push(row);
        return row;
      }),
    },
  } as unknown as ConstructorParameters<typeof MovingService>[0];
  const owner = { currentOwnerId: vi.fn(async () => 'owner-1') } as unknown as ConstructorParameters<typeof MovingService>[1];
  const weather = {} as ConstructorParameters<typeof MovingService>[2];
  const carePlan = {} as ConstructorParameters<typeof MovingService>[3];
  const svc = new MovingService(prisma, owner, weather, carePlan);
  return { svc, prisma, created, moves };
}

const sel = { name: 'Guadalajara, Jalisco, Mexico', latitude: 20.66682, longitude: -103.39182, timezone: 'America/Mexico_City' };

describe('MovingService.schedule find-or-create city', () => {
  it('reuses a saved city whose coordinates match when rounded to 4 decimals', async () => {
    const { svc, prisma, created } = makeService([
      { id: 'existing', latitude: 20.6668, longitude: -103.3918 },
    ]);
    const out = await svc.schedule(sel, '2026-07-01');
    expect((prisma as unknown as { city: { create: ReturnType<typeof vi.fn> } }).city.create).not.toHaveBeenCalled();
    expect(created).toHaveLength(0);
    expect(typeof out.id).toBe('string');
  });

  it('creates a new city when no saved city matches', async () => {
    const { svc, created } = makeService([
      { id: 'other', latitude: 19.4326, longitude: -99.1332 },
    ]);
    await svc.schedule(sel, '2026-07-01');
    expect(created).toHaveLength(1);
    expect(created[0]).toMatchObject({
      ownerId: 'owner-1',
      name: sel.name,
      latitude: sel.latitude,
      longitude: sel.longitude,
      timezone: sel.timezone,
    });
  });

  it('binds moveOn as a native Date (MariaDB date rule)', async () => {
    const { svc, moves } = makeService([{ id: 'existing', latitude: 20.6668, longitude: -103.3918 }]);
    await svc.schedule(sel, '2026-07-01');
    expect(moves[0].moveOn).toBeInstanceOf(Date);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- find-or-create-city`
Expected: FAIL — `schedule` still has the old `(targetCityId, moveOn)` signature; the city-matching branch does not exist.

- [ ] **Step 3: Write the implementation**

In `src/moving/moving.service.ts`:

(a) Add the import for the rounding helper near the other imports (after `startOfTomorrowUtc`):

```typescript
import { roundCoord4 } from '../common/geo/round-coord.js';
```

(b) Replace `simulate` (currently `moving.service.ts:28-62`). The signature changes to coordinates and the weather source becomes `forLocation`. **Keep the inline viability mapping exactly as it is** (Phase C extracts it):

```typescript
  // What-if: viability of every plant against an arbitrary geocoded target. Writes nothing.
  async simulate(latitude: number, longitude: number): Promise<PlantViability[]> {
    const ownerId = await this.owner.currentOwnerId();
    const weather = await this.weather.forLocation(`${latitude},${longitude}`, latitude, longitude);
    const plants = await this.prisma.plant.findMany({
      where: { ownerId },
      include: { species: true, place: true },
    });

    return plants.map((plant) => {
      const record = parseSpeciesRecord(plant.species.record);
      const effective = effectiveConditions(
        {
          indoor: plant.place.indoor,
          climateControlled: plant.place.climateControlled,
          humidityCharacter: plant.place.humidityCharacter,
          indoorTempMinC: plant.place.indoorTempMinC,
          indoorTempMaxC: plant.place.indoorTempMaxC,
        },
        weather ? { tempC: weather.tempC, humidityPct: weather.humidityPct } : null,
      );
      const result = assessViability({
        survivalMinC: record.temperature.survivalMinC,
        survivalMaxC: record.temperature.survivalMaxC,
        minLightRank: LIGHT_LEVELS.indexOf(record.light.minimum),
        minHumidityPct: record.humidity.minimumPct,
        seasonalLowC: weather?.seasonalLowC ?? record.temperature.idealMinC,
        seasonalHighC: weather?.seasonalHighC ?? record.temperature.idealMaxC,
        placeLightRank: placeLightRank(plant.place.lightType),
        effectiveHumidityPct: effective.humidityPct,
      });
      return { plantId: plant.id, nickname: plant.nickname, speciesSlug: plant.speciesSlug, ...result };
    });
  }
```

(c) Replace `schedule` (currently `moving.service.ts:64-72`) with the find-or-create version. We fetch the owner's cities and match in JS via `roundCoord4` (floats are never compared for exact equality), then create if absent:

```typescript
  // Persists a planned move. Finds-or-creates the owner's destination City by coordinates
  // rounded to 4 decimals (never exact float equality), then schedules the move against it.
  async schedule(
    target: { name: string; latitude: number; longitude: number; timezone: string },
    moveOn: string,
  ): Promise<{ id: string }> {
    const ownerId = await this.owner.currentOwnerId();
    const wantLat = roundCoord4(target.latitude);
    const wantLng = roundCoord4(target.longitude);

    const owned = await this.prisma.city.findMany({ where: { ownerId } });
    let city = owned.find(
      (c) => roundCoord4(c.latitude) === wantLat && roundCoord4(c.longitude) === wantLng,
    );
    if (!city) {
      city = await this.prisma.city.create({
        data: {
          ownerId,
          name: target.name,
          latitude: target.latitude,
          longitude: target.longitude,
          timezone: target.timezone,
        },
      });
    }

    const move = await this.prisma.scheduledMove.create({
      data: { ownerId, targetCityId: city.id, moveOn: new Date(moveOn) },
    });
    return { id: move.id };
  }
```

> `NotFoundException` is still imported and used by `applyDueMoves`'s neighbors? Check: after this edit, `simulate` no longer throws `NotFoundException`, but `applyDueMoves` does not use it either. If `NotFoundException` becomes unused, remove the now-unused `NotFoundException` import for hygiene — the build won't fail on it (the API `tsconfig.json` has no `noUnusedLocals`), but keep imports clean: `import { Injectable } from '@nestjs/common';`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- find-or-create-city && npm run typecheck && npm test`
Expected: the targeted test PASSES (3 tests); typecheck clean (this is where the Task 6 controller now compiles against the new signatures); full suite PASS.

- [ ] **Step 5: Commit (ships Tasks 6 + 7 together)**

```bash
git add src/moving/moving.controller.ts src/moving/moving.service.ts src/moving/moving.service.find-or-create-city.test.ts
git commit -m "feat(moving): simulate by coordinates; schedule find-or-creates city by rounded coords"
```

---

## Task 8: Frontend types + useApi client

**Files:**
- Modify: `types/api.ts` (add `CitySearchResult`)
- Modify: `composables/useApi.ts:1-36`

- [ ] **Step 1: Add the `CitySearchResult` type**

In `repos/my-plants-web/types/api.ts`, add after the `CreateCity` interface (around line 12):

```typescript
export interface CitySearchResult {
  name: string; country: string; admin1: string; latitude: number; longitude: number; timezone: string;
}
```

- [ ] **Step 2: Update the API client**

In `composables/useApi.ts`, add the new name `CitySearchResult` to the **existing** `import type { … } from '../types/api.js'` line — do not rewrite the line from scratch and do not remove names already there (notably `PlantCare`, added in Phase A, plus whatever else the line currently imports). After the edit the line includes all its prior names **plus** `CitySearchResult`, e.g.:

```typescript
import type {
  City, CitySearchResult, CreateCity, CreatePlace, CreatePlant, DueTaskResponse, Feedback, Place, Plant,
  PlantCare, PlantViability, SpeciesSummary,
} from '../types/api.js';
```

> Add to the existing import line; do not remove names already there (e.g. `PlantCare` from Phase A). The exact set may differ from the illustration above — only ensure `CitySearchResult` is added and nothing pre-existing is dropped.

Add `searchCities` next to the other city methods (after `makePrimaryCity`):

```typescript
    searchCities: (q: string) =>
      api<CitySearchResult[]>(`/cities/search?q=${encodeURIComponent(q)}`),
```

Replace the existing `simulateMove` / `scheduleMove` (lines 31-34) with the new signatures:

```typescript
    simulateMove: (latitude: number, longitude: number) =>
      api<PlantViability[]>('/moving/simulate', { method: 'POST', body: { latitude, longitude } }),
    scheduleMove: (sel: { name: string; latitude: number; longitude: number; timezone: string }, moveOn: string) =>
      api<{ id: string }>('/moving/schedule', { method: 'POST', body: { ...sel, moveOn } }),
```

- [ ] **Step 3: Verify (typecheck will still fail until callers updated — that's expected here)**

Run: `npm run build && npm run typecheck`
Expected: the `npm run typecheck` (`vue-tsc`) pass MAY fail on `pages/moving.vue` (still calls the old `simulateMove(targetCityId)` — a signature mismatch only `typecheck` catches, since `nuxt build` does not typecheck). That page is fixed in Task 12. If it fails, the only errors must be in `pages/moving.vue`; any other error is a mistake in this task. Proceed to Task 9.

- [ ] **Step 4: Commit**

```bash
git add types/api.ts composables/useApi.ts
git commit -m "feat(web): add CitySearchResult type, searchCities, and coordinate-based move client"
```

---

## Task 9: friendlyCityLabel helper

**Files:**
- Create: `utils/cityLabel.ts`
- Test: `utils/cityLabel.test.ts`

- [ ] **Step 1: Write the helper**

Create `repos/my-plants-web/utils/cityLabel.ts`:

```typescript
import type { CitySearchResult } from '../types/api.js';

// Builds the friendly display name stored as City.name, e.g. "Guadalajara, Jalisco, Mexico".
// Drops empty admin1/country segments so a sparse result still reads cleanly.
export function friendlyCityLabel(sel: Pick<CitySearchResult, 'name' | 'admin1' | 'country'>): string {
  return [sel.name, sel.admin1, sel.country].filter((part) => part && part.trim().length > 0).join(', ');
}
```

- [ ] **Step 2: Write the unit test (the web repo HAS Vitest)**

The web repo has Vitest configured (`vitest.config.ts` exists; `package.json` has `"test": "vitest run"`), so the pure helper gets a real unit test. Create `repos/my-plants-web/utils/cityLabel.test.ts`:

```typescript
import { describe, expect, it } from 'vitest';
import { friendlyCityLabel } from './cityLabel.js';

describe('friendlyCityLabel', () => {
  it('joins all three parts present', () => {
    expect(friendlyCityLabel({ name: 'Guadalajara', admin1: 'Jalisco', country: 'Mexico' }))
      .toBe('Guadalajara, Jalisco, Mexico');
  });

  it('drops a missing admin1', () => {
    expect(friendlyCityLabel({ name: 'Guadalajara', admin1: '', country: 'Mexico' }))
      .toBe('Guadalajara, Mexico');
  });

  it('drops both missing admin1 and country', () => {
    expect(friendlyCityLabel({ name: 'Somewhere', admin1: '', country: '' }))
      .toBe('Somewhere');
  });
});
```

Run: `npm test -- cityLabel`
Expected: PASS (3 tests).

- [ ] **Step 3: Verify it typechecks**

Run: `npm run build && npm run typecheck`
Expected: same status as Task 8 (only `pages/moving.vue` may still error in `typecheck`). The new util compiles.

- [ ] **Step 4: Commit**

```bash
git add utils/cityLabel.ts utils/cityLabel.test.ts
git commit -m "feat(web): add friendlyCityLabel builder for stored city names"
```

---

## Task 10: Reusable CitySearch component

**Files:**
- Create: `components/CitySearch.vue`

- [ ] **Step 1: Write the component**

Create `repos/my-plants-web/components/CitySearch.vue`. It searches via `useApi().searchCities(q)` and emits the chosen `CitySearchResult`. It debounces input so typing doesn't fire a request per keystroke, shows candidates with disambiguating context, and is used unchanged by both the cities form and the moving page:

```vue
<script setup lang="ts">
import type { CitySearchResult } from '../types/api.js';
import { friendlyCityLabel } from '../utils/cityLabel.js';

const props = withDefaults(defineProps<{ placeholder?: string }>(), {
  placeholder: 'Search a city…',
});
const emit = defineEmits<{ (e: 'select', value: CitySearchResult): void }>();

const api = useApi();
const query = ref('');
const results = ref<CitySearchResult[]>([]);
const loading = ref(false);
const selectedLabel = ref<string | null>(null);
let timer: ReturnType<typeof setTimeout> | null = null;

function optionLabel(c: CitySearchResult): string {
  return friendlyCityLabel(c);
}

async function runSearch(q: string) {
  if (q.trim().length < 2) {
    results.value = [];
    return;
  }
  loading.value = true;
  try {
    results.value = await api.searchCities(q);
  } finally {
    loading.value = false;
  }
}

watch(query, (q) => {
  selectedLabel.value = null;
  if (timer) clearTimeout(timer);
  timer = setTimeout(() => runSearch(q), 300);
});

function choose(c: CitySearchResult) {
  selectedLabel.value = optionLabel(c);
  results.value = [];
  query.value = '';
  emit('select', c);
}
</script>

<template>
  <div class="grid gap-2">
    <UInput v-model="query" :placeholder="props.placeholder" icon="i-heroicons-magnifying-glass" />
    <p v-if="selectedLabel" class="text-xs text-gray-500">Selected: {{ selectedLabel }}</p>
    <p v-else-if="loading" class="text-xs text-gray-400">Searching…</p>
    <p v-else-if="query.trim().length >= 2 && results.length === 0" class="text-xs text-gray-400">
      No matches.
    </p>
    <div v-if="results.length" class="grid gap-1">
      <UButton
        v-for="c in results"
        :key="`${c.latitude},${c.longitude}`"
        variant="ghost"
        class="justify-start"
        @click="choose(c)"
      >
        {{ optionLabel(c) }}
      </UButton>
    </div>
  </div>
</template>
```

- [ ] **Step 2: Verify it typechecks**

Run: `npm run build && npm run typecheck`
Expected: same as Task 9 (only `pages/moving.vue` may still error in `typecheck`). The component compiles.

- [ ] **Step 3: Commit**

```bash
git add components/CitySearch.vue
git commit -m "feat(web): add reusable CitySearch component (search, debounce, pick)"
```

---

## Task 11: Rebuild the cities create form around CitySearch

**Files:**
- Modify: `pages/cities/index.vue`

- [ ] **Step 1: Rebuild the page**

Replace the full contents of `repos/my-plants-web/pages/cities/index.vue`. The manual latitude/longitude/timezone inputs are removed; a `CitySearch` selection populates `{ name, latitude, longitude, timezone }`, with "Make primary" preserved:

```vue
<script setup lang="ts">
import type { CitySearchResult } from '../../types/api.js';
import { friendlyCityLabel } from '../../utils/cityLabel.js';

const api = useApi();
const { data: cities, refresh } = await useAsyncData('cities', () => api.listCities());

const selection = ref<CitySearchResult | null>(null);
const isPrimary = ref(false);

function onSelect(sel: CitySearchResult) {
  selection.value = sel;
}

async function submit() {
  if (!selection.value) return;
  const sel = selection.value;
  await api.createCity({
    name: friendlyCityLabel(sel),
    latitude: sel.latitude,
    longitude: sel.longitude,
    timezone: sel.timezone,
    isPrimary: isPrimary.value,
  });
  selection.value = null;
  isPrimary.value = false;
  await refresh();
}

async function makePrimary(id: string) {
  await api.makePrimaryCity(id);
  await refresh();
}
</script>

<template>
  <div>
    <h2 class="text-lg font-semibold mb-3">Cities</h2>
    <div class="grid gap-2 mb-6">
      <UCard v-for="c in cities" :key="c.id">
        <div class="flex items-center justify-between">
          <span class="font-medium">{{ c.name }} <UBadge v-if="c.isPrimary" color="green" size="xs">Primary</UBadge></span>
          <UButton v-if="!c.isPrimary" size="xs" variant="ghost" @click="makePrimary(c.id)">Make primary</UButton>
        </div>
        <span class="text-xs text-gray-500">{{ c.timezone }}</span>
      </UCard>
    </div>

    <div class="grid gap-3 max-w-md">
      <UFormGroup label="Find a city" required>
        <CitySearch placeholder="e.g. Guadalajara" @select="onSelect" />
      </UFormGroup>
      <p v-if="selection" class="text-sm">
        Will add: <span class="font-medium">{{ friendlyCityLabel(selection) }}</span>
        <span class="text-xs text-gray-500"> · {{ selection.timezone }}</span>
      </p>
      <UFormGroup label="Primary"><UToggle v-model="isPrimary" /></UFormGroup>
      <UButton :disabled="!selection" @click="submit">Add city</UButton>
    </div>
  </div>
</template>
```

- [ ] **Step 2: Verify**

Run: `npm run build && npm run typecheck`
Expected: same status as before — only `pages/moving.vue` may still error in `typecheck` (fixed in Task 12). The cities page compiles.

- [ ] **Step 3: Manual check (after the stack runs in the QA phase)**

On `/cities`: type "Guadalajara", pick a candidate, see "Will add: Guadalajara, Jalisco, Mexico", optionally toggle Primary, click "Add city" → the new card shows the friendly name and timezone. Confirm there are no latitude/longitude/timezone text inputs left.

- [ ] **Step 4: Commit**

```bash
git add pages/cities/index.vue
git commit -m "feat(web): rebuild cities form around CitySearch (no manual coordinates)"
```

---

## Task 12: Moving page uses CitySearch (simulate on select, schedule with selection)

**Files:**
- Modify: `pages/moving.vue`

- [ ] **Step 1: Rebuild the page**

Replace the full contents of `repos/my-plants-web/pages/moving.vue`. The saved-city dropdown is replaced with `CitySearch`; selecting a city simulates immediately; scheduling uses the selection + a date:

```vue
<script setup lang="ts">
import type { CitySearchResult, PlantViability } from '../types/api.js';
import { friendlyCityLabel } from '../utils/cityLabel.js';

const api = useApi();
const selection = ref<CitySearchResult | null>(null);
const results = ref<PlantViability[] | null>(null);
const moveOn = ref('');
const scheduling = ref(false);
const scheduled = ref(false);

async function onSelect(sel: CitySearchResult) {
  selection.value = sel;
  scheduled.value = false;
  results.value = await api.simulateMove(sel.latitude, sel.longitude);
}

async function schedule() {
  if (!selection.value || !moveOn.value) return;
  const sel = selection.value;
  scheduling.value = true;
  try {
    await api.scheduleMove(
      { name: friendlyCityLabel(sel), latitude: sel.latitude, longitude: sel.longitude, timezone: sel.timezone },
      moveOn.value,
    );
    scheduled.value = true;
  } finally {
    scheduling.value = false;
  }
}
</script>

<template>
  <div>
    <h2 class="text-lg font-semibold mb-3">Moving — what-if</h2>
    <div class="grid gap-3 max-w-md mb-6">
      <UFormGroup label="Target city">
        <CitySearch placeholder="Search where you'd move them" @select="onSelect" />
      </UFormGroup>
      <p v-if="selection" class="text-sm">
        Simulating against <span class="font-medium">{{ friendlyCityLabel(selection) }}</span>
      </p>
    </div>

    <div v-if="results" class="grid gap-2 mb-6">
      <UCard v-for="r in results" :key="r.plantId">
        <div class="flex items-center justify-between">
          <span class="font-medium">{{ r.nickname ?? r.speciesSlug }}</span>
          <ViabilityBadge :level="r.level" :reasons="r.reasons" />
        </div>
      </UCard>
    </div>

    <div v-if="selection" class="flex gap-2 items-end max-w-md">
      <UFormGroup label="Move on" class="flex-1">
        <UInput v-model="moveOn" type="date" />
      </UFormGroup>
      <UButton :disabled="!moveOn || scheduling" @click="schedule">Schedule move</UButton>
    </div>
    <p v-if="scheduled" class="text-xs text-green-600 mt-2">Move scheduled.</p>
  </div>
</template>
```

- [ ] **Step 2: Verify (build + typecheck must now be fully green)**

Run: `npm run build && npm run typecheck`
Expected: PASS (build + `typecheck` clean) — this is the task that resolves the `pages/moving.vue` `typecheck` errors (the mismatched `simulateMove` signature, which only `vue-tsc` via `npm run typecheck` catches — not `nuxt build`) deferred from Tasks 8-11.

- [ ] **Step 3: Manual check (QA phase)**

On `/moving`: search a city, pick it → the viability list renders for every plant against that city's weather; pick a date and "Schedule move" → confirmation shows; the destination appears under `/cities`.

- [ ] **Step 4: Commit**

```bash
git add pages/moving.vue
git commit -m "feat(web): moving page simulates and schedules via CitySearch"
```

---

## Task 13: Rich places form (indoor-only optional fields)

**Files:**
- Modify: `pages/places/index.vue`

- [ ] **Step 1: Rebuild the form**

Replace the full contents of `repos/my-plants-web/pages/places/index.vue`. Required fields stay `name`, `cityId`, `indoor`, `lightType`; the four optional fields render **only when `indoor = true`** (outdoor places use real weather, so the engine ignores them). The DTO already accepts all of them — only the form changes:

```vue
<script setup lang="ts">
import type { CreatePlace, HumidityCharacter, LightType } from '../../types/api.js';

const api = useApi();
const { data: places, refresh } = await useAsyncData('places', () => api.listPlaces());
const { data: cities } = await useAsyncData('cities', () => api.listCities());

const lightOptions: { label: string; value: LightType }[] = [
  { label: 'Direct sun', value: 'DIRECT' },
  { label: 'Bright indirect', value: 'BRIGHT_INDIRECT' },
  { label: 'Medium', value: 'MEDIUM' },
  { label: 'Low', value: 'LOW' },
];
const humidityOptions: { label: string; value: HumidityCharacter }[] = [
  { label: 'Dry', value: 'DRY' },
  { label: 'Normal', value: 'NORMAL' },
  { label: 'Humid', value: 'HUMID' },
];

const form = reactive<CreatePlace>({
  cityId: '', name: '', indoor: true, lightType: 'BRIGHT_INDIRECT',
  climateControlled: false, humidityCharacter: 'NORMAL', indoorTempMinC: null, indoorTempMaxC: null,
});
const cityOptions = computed(() => (cities.value ?? []).map((c) => ({ label: c.name, value: c.id })));

async function submit() {
  // Outdoor places ignore the indoor-only fields; send only what applies.
  const payload: CreatePlace = form.indoor
    ? { ...form }
    : { cityId: form.cityId, name: form.name, indoor: false, lightType: form.lightType };
  await api.createPlace(payload);
  Object.assign(form, {
    name: '', climateControlled: false, humidityCharacter: 'NORMAL', indoorTempMinC: null, indoorTempMaxC: null,
  });
  await refresh();
}
</script>

<template>
  <div>
    <h2 class="text-lg font-semibold mb-3">Places</h2>
    <div class="grid gap-2 mb-6">
      <UCard v-for="p in places" :key="p.id">
        <span class="font-medium">{{ p.name }}</span>
        <span class="text-xs text-gray-500"> · {{ p.indoor ? 'Indoor' : 'Outdoor' }} · {{ p.lightType }}</span>
      </UCard>
    </div>
    <UForm :state="form" class="grid gap-3 max-w-md" @submit="submit">
      <UFormGroup label="City" required>
        <USelect v-model="form.cityId" :options="cityOptions" placeholder="Pick a city" />
      </UFormGroup>
      <UFormGroup label="Name" required><UInput v-model="form.name" placeholder="e.g. Living room window" /></UFormGroup>
      <UFormGroup label="Indoor"><UToggle v-model="form.indoor" /></UFormGroup>
      <UFormGroup label="Light" required><USelect v-model="form.lightType" :options="lightOptions" /></UFormGroup>

      <template v-if="form.indoor">
        <UFormGroup label="Climate controlled"><UToggle v-model="form.climateControlled" /></UFormGroup>
        <UFormGroup label="Humidity character">
          <USelect v-model="form.humidityCharacter" :options="humidityOptions" />
        </UFormGroup>
        <UFormGroup label="Indoor temp min (°C)">
          <UInput v-model.number="form.indoorTempMinC" type="number" step="0.5" />
        </UFormGroup>
        <UFormGroup label="Indoor temp max (°C)">
          <UInput v-model.number="form.indoorTempMaxC" type="number" step="0.5" />
        </UFormGroup>
      </template>

      <UButton type="submit" :disabled="!form.cityId || !form.name">Add place</UButton>
    </UForm>
  </div>
</template>
```

- [ ] **Step 2: Verify**

Run: `npm run build && npm run typecheck`
Expected: PASS (build + `typecheck` clean).

- [ ] **Step 3: Manual check (QA phase)**

On `/places`: with Indoor ON the four optional fields appear (climate controlled, humidity, temp min/max); toggle Indoor OFF and they disappear. Create one of each and confirm the card lists indoor/outdoor + light correctly.

- [ ] **Step 4: Commit**

```bash
git add pages/places/index.vue
git commit -m "feat(web): rich places form with indoor-only environmental fields"
```

---

## Task 14: Full-phase verification

**Files:** none (verification only)

- [ ] **Step 1: API suite + typecheck**

Run (in `repos/my-plants-api`): `npm run typecheck && npm test`
Expected: typecheck clean; all tests PASS (geocoding client, weather service, round-coord, find-or-create city, plus all pre-existing tests).

- [ ] **Step 2: Web build + typecheck**

Run (in `repos/my-plants-web`): `npm run build && npm run typecheck`
Expected: PASS (build + `typecheck` clean).

- [ ] **Step 3: Cross-check the shared contract**

Confirm by reading the files that these names match exactly across repos: `CitySearchResult` fields (`name, country, admin1, latitude, longitude, timezone`); `api.searchCities`, `api.simulateMove(latitude, longitude)`, `api.scheduleMove(sel, moveOn)`; backend `GET /cities/search`, `POST /moving/simulate { latitude, longitude }`, `POST /moving/schedule { name, latitude, longitude, timezone, moveOn }`.

- [ ] **Step 4: No commit** (verification only). Phase B is complete; hand off to the QA phase per the workspace workflow (delegate live checks to the `qa-engineer` subagent: city search in cities + moving, rich places form, schedule-move persistence).

---

## Self-review notes (spec coverage)

- **B.1 geocoding bank** → Tasks 1, 3, 4 (client, wiring, endpoint), 8 (client method), 10/11 (UI).
- **B.1 cities form rebuild + friendly name + make-primary preserved** → Tasks 9, 11.
- **B.1 single reusable search component (no fork)** → Task 10, reused in Tasks 11 and 12.
- **B.2 rich places form (indoor-only optionals)** → Task 13.
- **Cross-cutting: generalize WeatherService to forLocation (no fork)** → Task 2 (cache-unbounded note included).
- **Cross-cutting: simulate `{ latitude, longitude }` writes nothing; inline viability mapping left for Phase C** → Tasks 6, 7 (seam noted, not extracted).
- **Cross-cutting: schedule `{ name, latitude, longitude, timezone, moveOn }`, find-or-create by 4-decimal-rounded coords** → Tasks 5, 6, 7.
- **Cross-cutting: MovingController DTOs + web `simulateMove`/`scheduleMove`** → Tasks 6, 8, 12.
- **Out of scope (other phases):** startup recompute, plant care endpoint/viability extraction (Phase C), blog (Phase D), care-loop learning (Phase A) — intentionally not in this plan.
