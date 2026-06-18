# MyPlants — Phase 3: `my-plants-api` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the deterministic care engine as a NestJS API over local MariaDB (Prisma): it seeds curated species, models each plant's environment, and computes/serves the care plan (scheduling, viability, feedback adaptation, moving) — with no runtime AI.

**Architecture:** A NestJS app at `repos/my-plants-api`. The domain logic lives in **pure, I/O-free services** (scheduling, indoor-climate, viability, adaptation) that are unit-tested in isolation; Nest modules wire them to Prisma repositories, the Open-Meteo weather client, and HTTP controllers. Everything is scoped by `ownerId` (single owner in v1, resolved by a stub). The connection string is assembled at runtime from separate `DB_*` env vars.

**Tech Stack:** NestJS 10, Prisma 5 (MySQL provider → MariaDB), Vitest (unit) + Nest e2e, Zod-validated config, Open-Meteo (no key). Consumes `@retaxmaster/my-plants-species-schema` (packed tarball).

**Depends on:** Phase 1 (`my-plants-species-schema`) built; a local MariaDB server is running. The
`Species` table is populated by Phase 2 (`my-plants-knowledge-engine`)'s `db:insert` script — run
it after this phase's Prisma migration creates the table and before this phase's e2e.

---

## Data model & engine contracts (binding for this phase)

Persisted (Prisma models): `Owner`, `City`, `Place`, `Species` (seeded cache), `Plant`,
`CareEvent` (append-only log), `PlantTaskAdjustment` (per-plant learned multiplier),
`TaskOverride` (one-off next-due), `DueCache` (rebuildable). Tasks tracked: `WATER`,
`FERTILIZE`, `REPOT`, `ROTATE`, `CLEAN_LEAVES`.

Scheduling: `nextDue = anchor + round(baseIntervalDays × Madj × Mtemp × Mlight × Mseason)`,
clamped to `[min,max]` from drought tolerance. Modulators default to `1.0`; missing weather
is neutral; indoor plants are not modulated by live outdoor weather. Dates are `DATE`
granularity in the owner's primary-city timezone.

---

## File Structure (created across the tasks)

```
repos/my-plants-api/
  package.json  tsconfig.json  tsconfig.build.json  vitest.config.ts  nest-cli.json  .gitignore  .env.example
  prisma/schema.prisma
  src/
    main.ts  app.module.ts
    config/{config.module.ts,env.ts,database-url.ts,database-url.test.ts}
    prisma/{prisma.module.ts,prisma.service.ts}
    owner/{owner.module.ts,owner.service.ts}
    common/season/{season.ts,season.test.ts}
    engines/
      indoor-climate.ts  indoor-climate.test.ts
      scheduling.ts      scheduling.test.ts
      viability.ts       viability.test.ts
      adaptation.ts      adaptation.test.ts
    weather/{weather.module.ts,open-meteo.client.ts,weather.service.ts}
    species/{species.module.ts,species.service.ts,species.controller.ts}
    cities/{cities.module.ts,cities.service.ts,cities.controller.ts}
    places/{places.module.ts,places.service.ts,places.controller.ts,place-conditions.ts}
    plants/{plants.module.ts,plants.service.ts,plants.controller.ts}
    care-plan/{care-plan.module.ts,care-plan.service.ts,care-plan.controller.ts,care-plan.cron.ts}
    feedback/{feedback.module.ts,feedback.service.ts,feedback.controller.ts}
    moving/{moving.module.ts,moving.service.ts,moving.controller.ts}
    notifications/{notifications.module.ts,notifications.service.ts,notification-channel.ts}
  test/app.e2e-spec.ts
```

The `engines/*` and `common/season` files are **pure** (no Nest, no Prisma, no I/O) and carry the deepest test coverage. Modules/services are thin wiring around them.

---

## Task 1: Scaffold the NestJS submodule

**Files:** `package.json`, `tsconfig*.json`, `nest-cli.json`, `vitest.config.ts`, `.gitignore`, `.env.example`

- [ ] **Step 1: Create the GitHub repo and register the submodule**

From the **workspace root**:

```bash
gh repo create RetaxMaster/my-plants-api --public --description "MyPlants deterministic care API (NestJS + Prisma/MariaDB)."
git submodule add git@github.com:RetaxMaster/my-plants-api.git repos/my-plants-api
mkdir -p repos/my-plants-api/src repos/my-plants-api/prisma repos/my-plants-api/test repos/my-plants-api/scripts
```

- [ ] **Step 2: Create `package.json`**

Create `repos/my-plants-api/package.json`:

```json
{
  "name": "@retaxmaster/my-plants-api",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "nest build",
    "start": "node dist/main.js",
    "start:dev": "nest start --watch",
    "dev": "nest start --watch",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:e2e": "vitest run --config vitest.e2e.config.ts",
    "typecheck": "tsc --noEmit",
    "prisma:generate": "prisma generate",
    "prisma:migrate": "prisma migrate dev"
  },
  "dependencies": {
    "@nestjs/common": "^10.4.4",
    "@nestjs/core": "^10.4.4",
    "@nestjs/platform-express": "^10.4.4",
    "@nestjs/schedule": "^4.1.1",
    "@prisma/client": "^5.20.0",
    "class-transformer": "^0.5.1",
    "class-validator": "^0.14.1",
    "reflect-metadata": "^0.2.2",
    "rxjs": "^7.8.1",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@nestjs/cli": "^10.4.5",
    "@nestjs/testing": "^10.4.4",
    "@types/express": "^4.17.21",
    "@types/node": "^20.14.0",
    "@types/supertest": "^6.0.2",
    "prisma": "^5.20.0",
    "supertest": "^7.0.0",
    "tsx": "^4.16.2",
    "typescript": "^5.5.4",
    "vitest": "^2.0.5"
  }
}
```

- [ ] **Step 3: Create the TS + Nest + Vitest configs**

Create `repos/my-plants-api/tsconfig.json`:

```json
{
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "target": "ES2022",
    "outDir": "./dist",
    "strict": true,
    "declaration": false,
    "emitDecoratorMetadata": true,
    "experimentalDecorators": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*.ts", "scripts/**/*.ts", "vitest.config.ts", "vitest.e2e.config.ts"]
}
```

> The base config sets no `rootDir` so `typecheck` (`tsc --noEmit`) can include `scripts/` and
> the vitest configs without `TS6059` ("not under rootDir"). `rootDir: ./src` lives only in
> `tsconfig.build.json`, which `nest build` uses to emit just `src/`.

Create `repos/my-plants-api/tsconfig.build.json`:

```json
{
  "extends": "./tsconfig.json",
  "compilerOptions": { "rootDir": "./src" },
  "include": ["src/**/*.ts"],
  "exclude": ["node_modules", "dist", "test", "scripts", "src/**/*.test.ts"]
}
```

Create `repos/my-plants-api/nest-cli.json`:

```json
{ "collection": "@nestjs/schematics", "sourceRoot": "src", "compilerOptions": { "deleteOutDir": true } }
```

Create `repos/my-plants-api/vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    globals: true,
  },
});
```

Create `repos/my-plants-api/vitest.e2e.config.ts`:

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.e2e-spec.ts'],
    globals: true,
    hookTimeout: 30000,
  },
});
```

- [ ] **Step 4: Create `.gitignore` and `.env.example`**

Create `repos/my-plants-api/.gitignore`:

```gitignore
node_modules/
dist/
.env
*.tgz
```

Create `repos/my-plants-api/.env.example`:

```dotenv
DB_HOST=localhost
DB_PORT=3306
DB_USER=myplants
DB_PASSWORD=123
DB_NAME=myplants
PORT=8000
# Primary garden city (used for weather + canonical timezone). Overridable via the API.
DEFAULT_CITY_TZ=America/Mexico_City
```

- [ ] **Step 5: Install deps + the packed schema, then commit the submodule files**

From the **workspace root**:

```bash
npm --prefix repos/my-plants-api install
./scripts/pack-species-schema-and-install.sh   # now also installs into my-plants-api
git -C repos/my-plants-api add -A
git -C repos/my-plants-api commit -m "chore: scaffold my-plants-api"
```

Expected: install succeeds; the pack script adds the `@retaxmaster/my-plants-species-schema` tarball dep to the API too.

---

## Task 2: Config — assemble `DATABASE_URL` from separate `DB_*` vars

**Files:** `src/config/env.ts`, `src/config/database-url.ts`, `src/config/database-url.test.ts`, `src/config/config.module.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-api/src/config/database-url.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { buildDatabaseUrl } from './database-url.js';

describe('buildDatabaseUrl', () => {
  it('assembles a MySQL URL from separate parts and URL-encodes the password', () => {
    const url = buildDatabaseUrl({
      DB_HOST: 'localhost',
      DB_PORT: 3306,
      DB_USER: 'my_plants',
      DB_PASSWORD: 'p@ss/word',
      DB_NAME: 'my_plants',
    });
    expect(url).toBe('mysql://my_plants:p%40ss%2Fword@localhost:3306/my_plants');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- database-url`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement env parsing + URL assembly**

Create `repos/my-plants-api/src/config/env.ts`:

```ts
import { z } from 'zod';

export const envSchema = z.object({
  DB_HOST: z.string().min(1),
  DB_PORT: z.coerce.number().int().positive(),
  DB_USER: z.string().min(1),
  DB_PASSWORD: z.string(),
  DB_NAME: z.string().min(1),
  PORT: z.coerce.number().int().positive().default(3000),
  DEFAULT_CITY_TZ: z.string().min(1).default('America/Mexico_City'),
});

export type Env = z.infer<typeof envSchema>;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  return envSchema.parse(source);
}
```

Create `repos/my-plants-api/src/config/database-url.ts`:

```ts
export interface DbParts {
  DB_HOST: string;
  DB_PORT: number;
  DB_USER: string;
  DB_PASSWORD: string;
  DB_NAME: string;
}

// Assemble the Prisma/MySQL connection string from separate parts. Never hand-author it.
export function buildDatabaseUrl(p: DbParts): string {
  const user = encodeURIComponent(p.DB_USER);
  const pass = encodeURIComponent(p.DB_PASSWORD);
  return `mysql://${user}:${pass}@${p.DB_HOST}:${p.DB_PORT}/${p.DB_NAME}`;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- database-url`
Expected: PASS.

- [ ] **Step 5: Create the config module**

Create `repos/my-plants-api/src/config/config.module.ts`:

```ts
import { Global, Module } from '@nestjs/common';
import { buildDatabaseUrl } from './database-url.js';
import { loadEnv, type Env } from './env.js';

export const ENV = Symbol('ENV');
export const DATABASE_URL = Symbol('DATABASE_URL');

@Global()
@Module({
  providers: [
    { provide: ENV, useFactory: (): Env => loadEnv() },
    { provide: DATABASE_URL, useFactory: (env: Env): string => buildDatabaseUrl(env), inject: [ENV] },
  ],
  exports: [ENV, DATABASE_URL],
})
export class ConfigModule {}
```

- [ ] **Step 6: Commit**

```bash
git -C repos/my-plants-api add src/config
git -C repos/my-plants-api commit -m "feat: assemble DATABASE_URL from separate DB_* env vars"
```

---

## Task 3: Prisma schema + the env-composed CLI datasource

**Files:** `prisma/schema.prisma`, `src/prisma/prisma.service.ts`, `src/prisma/prisma.module.ts`, `.env` (generated, git-ignored), a `prisma:env` helper

- [ ] **Step 1: Write the Prisma schema**

Create `repos/my-plants-api/prisma/schema.prisma`:

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "mysql"
  url      = env("DATABASE_URL")
}

enum Task {
  WATER
  FERTILIZE
  REPOT
  ROTATE
  CLEAN_LEAVES
}

enum CareEventType {
  DONE
  POSTPONED
  SYMPTOM
}

enum LightType {
  DIRECT
  BRIGHT_INDIRECT
  MEDIUM
  LOW
}

enum HumidityCharacter {
  DRY
  NORMAL
  HUMID
}

model Owner {
  id     String  @id @default(cuid())
  name   String
  cities City[]
  places Place[]
  plants Plant[]

  @@map("owners")
}

model City {
  id        String  @id @default(cuid())
  ownerId   String
  owner     Owner   @relation(fields: [ownerId], references: [id])
  name      String
  latitude  Float
  longitude Float
  timezone  String
  isPrimary Boolean @default(false)
  places    Place[]

  @@index([ownerId])
  @@map("cities")
}

model Place {
  id                String            @id @default(cuid())
  ownerId           String
  owner             Owner             @relation(fields: [ownerId], references: [id])
  cityId            String
  city              City              @relation(fields: [cityId], references: [id])
  name              String
  indoor            Boolean
  lightType         LightType
  climateControlled Boolean           @default(false)
  humidityCharacter HumidityCharacter @default(NORMAL)
  indoorTempMinC    Float?
  indoorTempMaxC    Float?
  plants            Plant[]

  @@index([ownerId])
  @@index([cityId])
  @@map("places")
}

model Species {
  slug           String  @id
  scientificName String  @unique
  record         Json
  plants         Plant[]

  @@map("species")
}

model Plant {
  id          String   @id @default(cuid())
  ownerId     String
  owner       Owner    @relation(fields: [ownerId], references: [id])
  placeId     String
  place       Place    @relation(fields: [placeId], references: [id])
  speciesSlug String
  species     Species  @relation(fields: [speciesSlug], references: [slug])
  nickname    String?
  acquiredOn  DateTime @db.Date
  createdAt   DateTime @default(now())

  events      CareEvent[]
  adjustments PlantTaskAdjustment[]
  overrides   TaskOverride[]
  dueCache    DueCache[]

  @@index([ownerId])
  @@index([placeId])
  @@map("plants")
}

model CareEvent {
  id         String        @id @default(cuid())
  plantId    String
  plant      Plant         @relation(fields: [plantId], references: [id])
  task       Task
  type       CareEventType
  occurredOn DateTime      @db.Date
  payload    Json?
  createdAt  DateTime      @default(now())

  @@index([plantId, task])
  @@map("care_events")
}

model PlantTaskAdjustment {
  id         String   @id @default(cuid())
  plantId    String
  plant      Plant    @relation(fields: [plantId], references: [id])
  task       Task
  multiplier Float    @default(1.0)
  updatedAt  DateTime @updatedAt

  @@unique([plantId, task])
  @@map("plant_task_adjustments")
}

model TaskOverride {
  id        String   @id @default(cuid())
  plantId   String
  plant     Plant    @relation(fields: [plantId], references: [id])
  task      Task
  nextDueOn DateTime @db.Date

  @@unique([plantId, task])
  @@map("task_overrides")
}

model DueCache {
  id         String   @id @default(cuid())
  plantId    String
  plant      Plant    @relation(fields: [plantId], references: [id])
  task       Task
  nextDueOn  DateTime @db.Date
  computedAt DateTime @default(now())

  @@unique([plantId, task])
  @@map("due_caches")
}

model ScheduledMove {
  id           String   @id @default(cuid())
  ownerId      String
  targetCityId String
  moveOn       DateTime @db.Date
  applied      Boolean  @default(false)
  createdAt    DateTime @default(now())

  @@index([ownerId])
  @@map("scheduled_moves")
}
```

> **Table naming convention:** every model carries an `@@map(...)` so the physical tables are
> **snake_case plural** (`owners`, `cities`, `places`, `species`, `plants`, `care_events`,
> `plant_task_adjustments`, `task_overrides`, `due_caches`, `scheduled_moves`) while the Prisma
> model names stay PascalCase. Prisma model field names remain the column names (camelCase, e.g.
> `scientificName`); the knowledge engine's raw-SQL `db:insert` targets `species` with those
> exact column names.

- [ ] **Step 2: Add the `prisma:env` helper that composes the CLI datasource URL**

The Prisma CLI (`migrate`, `generate`) reads `DATABASE_URL` from the environment. Compose it
from the same `DB_*` vars in a git-ignored `.env` so it is never hand-authored. Create
`repos/my-plants-api/scripts/write-prisma-env.ts`:

```ts
import { writeFileSync } from 'node:fs';
import { loadEnv } from '../src/config/env.js';
import { buildDatabaseUrl } from '../src/config/database-url.js';

const env = loadEnv();
writeFileSync('.env', `DATABASE_URL=${buildDatabaseUrl(env)}\n`, 'utf8');
console.log('Wrote .env with composed DATABASE_URL');
```

Add to `package.json` scripts (edit the existing `scripts` block):

```json
"prisma:env": "tsx scripts/write-prisma-env.ts",
"prisma:migrate": "npm run prisma:env && prisma migrate dev",
"prisma:generate": "npm run prisma:env && prisma generate"
```

> Run order before any Prisma CLI use: export the `DB_*` vars (e.g. `set -a; source .env.local; set +a`, with your own un-committed `.env.local`), then `npm run prisma:env` writes the composed `.env` that Prisma reads.

- [ ] **Step 3: Generate the client and run the first migration**

Run (inside `repos/my-plants-api`, with `DB_*` exported and MariaDB up):

```bash
npm run prisma:env
npm run prisma:generate
npm run prisma:migrate -- --name init
```

Expected: the MariaDB schema is created; `@prisma/client` is generated.

- [ ] **Step 4: Create the Prisma service + module**

Create `repos/my-plants-api/src/prisma/prisma.service.ts`:

```ts
import { Inject, Injectable, type OnModuleDestroy, type OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { DATABASE_URL } from '../config/config.module.js';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor(@Inject(DATABASE_URL) databaseUrl: string) {
    super({ datasources: { db: { url: databaseUrl } } });
  }
  async onModuleInit(): Promise<void> {
    await this.$connect();
    // Fix the session timezone to UTC so DATE/DATETIME handling is deterministic and the
    // MariaDB UTC-offset pitfall cannot shift due-date thresholds. All local-day logic is
    // done app-side via the local-date helper. (v1 runs a single connection locally; if a
    // pool is introduced later, set the server/global time_zone or a per-connection init hook
    // so every pooled connection inherits UTC.)
    await this.$executeRawUnsafe("SET time_zone = '+00:00'");
  }
  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }
}
```

Create `repos/my-plants-api/src/prisma/prisma.module.ts`:

```ts
import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service.js';

@Global()
@Module({ providers: [PrismaService], exports: [PrismaService] })
export class PrismaModule {}
```

- [ ] **Step 5: Commit**

```bash
git -C repos/my-plants-api add prisma src/prisma scripts/write-prisma-env.ts package.json package-lock.json
git -C repos/my-plants-api commit -m "feat: add Prisma schema, MariaDB datasource, and env-composed CLI url"
```

---

## Task 4: Season + local-date helpers (pure)

**Files:** `src/common/season/season.ts`, `src/common/season/season.test.ts`, `src/common/time/local-date.ts`, `src/common/time/local-date.test.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-api/src/common/season/season.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { seasonForDate } from './season.js';

describe('seasonForDate (northern hemisphere)', () => {
  it('maps months to meteorological seasons', () => {
    expect(seasonForDate(new Date('2026-01-15'), 'north')).toBe('winter');
    expect(seasonForDate(new Date('2026-04-15'), 'north')).toBe('spring');
    expect(seasonForDate(new Date('2026-07-15'), 'north')).toBe('summer');
    expect(seasonForDate(new Date('2026-10-15'), 'north')).toBe('autumn');
  });
  it('flips for the southern hemisphere', () => {
    expect(seasonForDate(new Date('2026-01-15'), 'south')).toBe('summer');
    expect(seasonForDate(new Date('2026-07-15'), 'south')).toBe('winter');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- season`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `repos/my-plants-api/src/common/season/season.ts`:

```ts
import type { Season } from '@retaxmaster/my-plants-species-schema';

export type Hemisphere = 'north' | 'south';

const NORTH: Season[] = ['winter', 'spring', 'summer', 'autumn'];

// Meteorological seasons by month index (0-11): DJF winter, MAM spring, JJA summer, SON autumn.
export function seasonForDate(date: Date, hemisphere: Hemisphere): Season {
  const m = date.getUTCMonth();
  const idx = m === 11 ? 0 : Math.floor(((m + 1) % 12) / 3); // 0 winter..3 autumn
  const north = NORTH[idx];
  if (hemisphere === 'north') return north;
  const flip: Record<Season, Season> = { winter: 'summer', summer: 'winter', spring: 'autumn', autumn: 'spring' };
  return flip[north];
}

export function hemisphereForLatitude(latitude: number): Hemisphere {
  return latitude >= 0 ? 'north' : 'south';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- season`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C repos/my-plants-api add src/common/season
git -C repos/my-plants-api commit -m "feat: add hemisphere-aware season helper"
```

- [ ] **Step 6: Write the failing local-date test**

Create `repos/my-plants-api/src/common/time/local-date.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { startOfTodayUtc, startOfTomorrowUtc } from './local-date.js';

describe('timezone-aware local-date boundaries', () => {
  // 02:00Z on 2026-06-18 is still 2026-06-17 in America/Mexico_City (UTC-6).
  const now = new Date('2026-06-18T02:00:00Z');

  it('computes the start of the local day as a UTC-midnight Date', () => {
    expect(startOfTodayUtc('America/Mexico_City', now).toISOString()).toBe('2026-06-17T00:00:00.000Z');
  });

  it('computes the start of the next local day', () => {
    expect(startOfTomorrowUtc('America/Mexico_City', now).toISOString()).toBe('2026-06-18T00:00:00.000Z');
  });

  it('uses the local calendar day for a positive-offset zone', () => {
    expect(startOfTodayUtc('Asia/Tokyo', now).toISOString()).toBe('2026-06-18T00:00:00.000Z');
  });
});
```

- [ ] **Step 7: Run test to verify it fails**

Run: `npm test -- local-date`
Expected: FAIL.

- [ ] **Step 8: Implement**

Create `repos/my-plants-api/src/common/time/local-date.ts`:

```ts
// All day boundaries use the owner's primary-city timezone. Due dates are DATE granularity,
// so we represent a local calendar day as that day's UTC-midnight Date (matching how Prisma
// returns @db.Date columns) and never compare against toISOString() strings of timestamps.
interface Ymd { y: number; m: number; d: number }

function localYmd(now: Date, timeZone: string): Ymd {
  // en-CA formats as YYYY-MM-DD.
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
  const [y, m, d] = parts.split('-').map(Number);
  return { y, m, d };
}

export function startOfTodayUtc(timeZone: string, now: Date = new Date()): Date {
  const { y, m, d } = localYmd(now, timeZone);
  return new Date(Date.UTC(y, m - 1, d));
}

export function startOfTomorrowUtc(timeZone: string, now: Date = new Date()): Date {
  const { y, m, d } = localYmd(now, timeZone);
  return new Date(Date.UTC(y, m - 1, d + 1));
}
```

- [ ] **Step 9: Run test, then commit**

Run: `npm test -- local-date`
Expected: PASS.

```bash
git -C repos/my-plants-api add src/common/time
git -C repos/my-plants-api commit -m "feat: add timezone-aware local-date boundaries"
```

---

## Task 5: Indoor-climate engine (pure)

**Files:** `src/engines/indoor-climate.ts`, `src/engines/indoor-climate.test.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-api/src/engines/indoor-climate.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { effectiveConditions, type PlaceClimateInput } from './indoor-climate.js';

const outdoor: PlaceClimateInput = {
  indoor: false, climateControlled: false, humidityCharacter: 'NORMAL',
  indoorTempMinC: null, indoorTempMaxC: null,
};
const weather = { tempC: 30, humidityPct: 45 };

describe('effectiveConditions', () => {
  it('passes outdoor weather straight through for outdoor places', () => {
    expect(effectiveConditions(outdoor, weather)).toEqual({ tempC: 30, humidityPct: 45 });
  });

  it('uses the midpoint of an indoor temperature range when provided', () => {
    const place: PlaceClimateInput = { ...outdoor, indoor: true, indoorTempMinC: 18, indoorTempMaxC: 24 };
    expect(effectiveConditions(place, weather).tempC).toBe(21);
  });

  it('treats a climate-controlled indoor place as a stable comfort baseline', () => {
    const place: PlaceClimateInput = { ...outdoor, indoor: true, climateControlled: true };
    expect(effectiveConditions(place, weather).tempC).toBe(21);
  });

  it('damps outdoor temperature toward the comfort baseline for a plain indoor place', () => {
    const place: PlaceClimateInput = { ...outdoor, indoor: true };
    // 21 + 0.4 * (30 - 21) = 24.6
    expect(effectiveConditions(place, weather).tempC).toBeCloseTo(24.6, 5);
  });

  it('raises humidity for a HUMID indoor place and lowers it for DRY', () => {
    const humid: PlaceClimateInput = { ...outdoor, indoor: true, humidityCharacter: 'HUMID' };
    const dry: PlaceClimateInput = { ...outdoor, indoor: true, humidityCharacter: 'DRY' };
    expect(effectiveConditions(humid, weather).humidityPct).toBe(65);
    expect(effectiveConditions(dry, weather).humidityPct).toBe(35);
  });

  it('is neutral when weather is missing (uses baselines)', () => {
    const place: PlaceClimateInput = { ...outdoor, indoor: true };
    expect(effectiveConditions(place, null)).toEqual({ tempC: 21, humidityPct: 50 });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- indoor-climate`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `repos/my-plants-api/src/engines/indoor-climate.ts`:

```ts
export interface PlaceClimateInput {
  indoor: boolean;
  climateControlled: boolean;
  humidityCharacter: 'DRY' | 'NORMAL' | 'HUMID';
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
}

const COMFORT_BASELINE_C = 21;
const INDOOR_HUMIDITY_BASELINE = 50;
const INDOOR_DAMPING = 0.4; // how much an indoor place tracks outdoor swings
const HUMID_INDOOR = 65;
const DRY_INDOOR = 35;

function indoorHumidity(character: PlaceClimateInput['humidityCharacter']): number {
  if (character === 'HUMID') return HUMID_INDOOR;
  if (character === 'DRY') return DRY_INDOOR;
  return INDOOR_HUMIDITY_BASELINE;
}

export function effectiveConditions(
  place: PlaceClimateInput,
  weather: Weather | null,
): EffectiveConditions {
  if (!place.indoor) {
    // Outdoor: real weather, or neutral baselines if unavailable.
    return weather ?? { tempC: COMFORT_BASELINE_C, humidityPct: INDOOR_HUMIDITY_BASELINE };
  }

  // Indoor temperature.
  let tempC: number;
  if (place.indoorTempMinC !== null && place.indoorTempMaxC !== null) {
    tempC = (place.indoorTempMinC + place.indoorTempMaxC) / 2;
  } else if (place.climateControlled || weather === null) {
    tempC = COMFORT_BASELINE_C;
  } else {
    tempC = COMFORT_BASELINE_C + INDOOR_DAMPING * (weather.tempC - COMFORT_BASELINE_C);
  }

  return { tempC, humidityPct: indoorHumidity(place.humidityCharacter) };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- indoor-climate`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C repos/my-plants-api add src/engines/indoor-climate.ts src/engines/indoor-climate.test.ts
git -C repos/my-plants-api commit -m "feat: add pure indoor-climate engine"
```

---

## Task 6: Scheduling engine (pure)

**Files:** `src/engines/scheduling.ts`, `src/engines/scheduling.test.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-api/src/engines/scheduling.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import {
  computeCadenceDue,
  computeFertilizingDue,
  computeNextDue,
  type ScheduleInput,
} from './scheduling.js';

const base: ScheduleInput = {
  baseIntervalDays: 10,
  droughtTolerance: 'medium',
  temperatureSensitivity: 'high',
  lightSensitivity: 'low',
  reduceInDormancy: true,
  idealMinC: 18,
  idealMaxC: 27,
  idealLightRank: 2, // bright-indirect
  anchor: new Date('2026-06-01'),
  adjustment: 1,
  effective: { tempC: 22, humidityPct: 55 },
  placeLightRank: 2,
  isOutdoor: true,
  weatherAvailable: true,
  season: 'summer',
  reduceSeason: 'winter',
};

describe('computeNextDue', () => {
  it('returns anchor + base interval at ideal conditions', () => {
    const due = computeNextDue(base);
    expect(due.toISOString().slice(0, 10)).toBe('2026-06-11');
  });

  it('shortens the interval in hot weather for a temperature-sensitive plant', () => {
    const due = computeNextDue({ ...base, effective: { tempC: 33, humidityPct: 40 } });
    const days = Math.round((due.getTime() - base.anchor.getTime()) / 86_400_000);
    expect(days).toBeLessThan(10);
  });

  it('ignores outdoor heat for an indoor plant', () => {
    const outdoorHot = computeNextDue({ ...base, effective: { tempC: 33, humidityPct: 40 } });
    const indoorHot = computeNextDue({ ...base, isOutdoor: false, effective: { tempC: 33, humidityPct: 40 } });
    expect(indoorHot.getTime()).toBeGreaterThan(outdoorHot.getTime());
  });

  it('is neutral on temperature when outdoor weather is unavailable', () => {
    const noWeather = computeNextDue({
      ...base,
      weatherAvailable: false,
      effective: { tempC: 33, humidityPct: 40 }, // would otherwise shorten
    });
    const days = Math.round((noWeather.getTime() - base.anchor.getTime()) / 86_400_000);
    expect(days).toBe(10); // base interval, temperature modulator forced to 1.0
  });

  it('lengthens during dormancy when reduceInDormancy is set', () => {
    const dormant = computeNextDue({ ...base, season: 'winter' });
    const days = Math.round((dormant.getTime() - base.anchor.getTime()) / 86_400_000);
    expect(days).toBeGreaterThan(10);
  });

  it('applies the per-plant adjustment multiplier', () => {
    const due = computeNextDue({ ...base, adjustment: 1.5 });
    const days = Math.round((due.getTime() - base.anchor.getTime()) / 86_400_000);
    expect(days).toBe(15);
  });

  it('clamps to the drought-tolerance bounds', () => {
    const tight = computeNextDue({ ...base, droughtTolerance: 'low', adjustment: 5 });
    const days = Math.round((tight.getTime() - base.anchor.getTime()) / 86_400_000);
    expect(days).toBeLessThanOrEqual(15); // low tolerance caps at base * 1.5
  });
});

const anchor = new Date('2026-06-01');
const daysFrom = (d: Date): number => Math.round((d.getTime() - anchor.getTime()) / 86_400_000);

describe('computeCadenceDue (rotation / leaf-cleaning / repotting — pure cadence)', () => {
  it('is anchor + cadence, unaffected by weather or season', () => {
    expect(daysFrom(computeCadenceDue({ cadenceDays: 14, adjustment: 1, anchor }))).toBe(14);
  });

  it('applies the per-plant adjustment', () => {
    expect(daysFrom(computeCadenceDue({ cadenceDays: 14, adjustment: 2, anchor }))).toBe(28);
  });
});

describe('computeFertilizingDue (season-aware)', () => {
  it('uses the in-season frequency during an active season', () => {
    const due = computeFertilizingDue({
      inSeasonFrequencyDays: 21, adjustment: 1, anchor, season: 'summer',
      activeSeasons: ['spring', 'summer'], reduceInDormancy: true,
    });
    expect(daysFrom(due)).toBe(21);
  });

  it('pushes far out when dormant and reduceInDormancy is set', () => {
    const due = computeFertilizingDue({
      inSeasonFrequencyDays: 21, adjustment: 1, anchor, season: 'winter',
      activeSeasons: ['spring', 'summer'], reduceInDormancy: true,
    });
    expect(daysFrom(due)).toBe(84); // DORMANT factor 4
  });

  it('mildly lengthens out of season when reduceInDormancy is false', () => {
    const due = computeFertilizingDue({
      inSeasonFrequencyDays: 21, adjustment: 1, anchor, season: 'winter',
      activeSeasons: ['spring', 'summer'], reduceInDormancy: false,
    });
    expect(daysFrom(due)).toBe(42); // INACTIVE factor 2
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- scheduling`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `repos/my-plants-api/src/engines/scheduling.ts`:

```ts
import type { DroughtTolerance, Season, Sensitivity } from '@retaxmaster/my-plants-species-schema';
import type { EffectiveConditions } from './indoor-climate.js';

export interface ScheduleInput {
  baseIntervalDays: number;
  droughtTolerance: DroughtTolerance;
  temperatureSensitivity: Sensitivity;
  lightSensitivity: Sensitivity;
  reduceInDormancy: boolean;
  idealMinC: number;
  idealMaxC: number;
  idealLightRank: number; // 0..3 (low..direct)
  anchor: Date;
  adjustment: number; // per-plant learned multiplier (>0)
  effective: EffectiveConditions;
  placeLightRank: number; // 0..3
  isOutdoor: boolean;
  weatherAvailable: boolean; // false → temperature modulator is forced neutral
  season: Season;
  reduceSeason: Season; // the dormancy season for this hemisphere (typically 'winter')
}

const SENS_WEIGHT: Record<Sensitivity, number> = { low: 0.04, medium: 0.08, high: 0.14 };
const TOLERANCE_SPAN: Record<DroughtTolerance, number> = { low: 0.5, medium: 1.0, high: 1.5 };

const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v));

// Hotter than ideal → drink sooner (multiplier < 1); colder → slower (> 1). Outdoor only,
// and only when real weather is available — missing weather must be neutral (spec).
function tempModulator(input: ScheduleInput): number {
  if (!input.isOutdoor || !input.weatherAvailable) return 1;
  const { tempC } = input.effective;
  let deviation = 0;
  if (tempC > input.idealMaxC) deviation = -(tempC - input.idealMaxC);
  else if (tempC < input.idealMinC) deviation = input.idealMinC - tempC;
  return clamp(1 + deviation * SENS_WEIGHT[input.temperatureSensitivity] * 0.1, 0.5, 1.6);
}

// Brighter than ideal → drink sooner; dimmer → slower.
function lightModulator(input: ScheduleInput): number {
  const deviation = input.idealLightRank - input.placeLightRank; // + means dimmer than ideal
  return clamp(1 + deviation * SENS_WEIGHT[input.lightSensitivity], 0.7, 1.4);
}

function seasonModulator(input: ScheduleInput): number {
  return input.reduceInDormancy && input.season === input.reduceSeason ? 1.5 : 1;
}

export function computeNextDue(input: ScheduleInput): Date {
  const raw =
    input.baseIntervalDays *
    input.adjustment *
    tempModulator(input) *
    lightModulator(input) *
    seasonModulator(input);

  const span = TOLERANCE_SPAN[input.droughtTolerance];
  const min = input.baseIntervalDays * (1 - span * 0.5);
  const max = input.baseIntervalDays * (1 + span);
  const days = Math.round(clamp(raw, Math.max(1, min), max));

  return addDays(input.anchor, days);
}

function addDays(anchor: Date, days: number): Date {
  const due = new Date(anchor.getTime());
  due.setUTCDate(due.getUTCDate() + days);
  return due;
}

// Rotation / leaf-cleaning / repotting: pure cadence, no weather/season/drought sensitivity.
export interface CadenceInput {
  cadenceDays: number;
  adjustment: number;
  anchor: Date;
}
export function computeCadenceDue(i: CadenceInput): Date {
  return addDays(i.anchor, Math.round(i.cadenceDays * i.adjustment));
}

// Fertilizing: in-season cadence; OUT of an active season always lengthens — strongly when
// reduceInDormancy is set (true dormancy), mildly otherwise.
const DORMANT_FERTILIZE_FACTOR = 4;
const INACTIVE_FERTILIZE_FACTOR = 2;
export interface FertilizingInput {
  inSeasonFrequencyDays: number;
  adjustment: number;
  anchor: Date;
  season: Season;
  activeSeasons: Season[];
  reduceInDormancy: boolean;
}
export function computeFertilizingDue(i: FertilizingInput): Date {
  const active = i.activeSeasons.includes(i.season);
  const factor = active ? 1 : i.reduceInDormancy ? DORMANT_FERTILIZE_FACTOR : INACTIVE_FERTILIZE_FACTOR;
  return addDays(i.anchor, Math.round(i.inSeasonFrequencyDays * i.adjustment * factor));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- scheduling`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C repos/my-plants-api add src/engines/scheduling.ts src/engines/scheduling.test.ts
git -C repos/my-plants-api commit -m "feat: add pure scheduling engine"
```

---

## Task 7: Viability engine (pure)

**Files:** `src/engines/viability.ts`, `src/engines/viability.test.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-api/src/engines/viability.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { assessViability, type ViabilityInput } from './viability.js';

const ok: ViabilityInput = {
  survivalMinC: 10, survivalMaxC: 35, minLightRank: 1, minHumidityPct: 30,
  seasonalLowC: 16, seasonalHighC: 28, placeLightRank: 2, effectiveHumidityPct: 50,
};

describe('assessViability', () => {
  it('returns good when everything is within tolerance', () => {
    const r = assessViability(ok);
    expect(r.level).toBe('good');
    expect(r.reasons).toEqual([]);
  });

  it('returns poor with a reason when the seasonal low is below survival', () => {
    const r = assessViability({ ...ok, seasonalLowC: 4 });
    expect(r.level).toBe('poor');
    expect(r.reasons.join(' ')).toMatch(/survival minimum/i);
  });

  it('returns caution when light is one rank below the minimum', () => {
    const r = assessViability({ ...ok, placeLightRank: 0, minLightRank: 1 });
    expect(r.level).toBe('caution');
    expect(r.reasons.join(' ')).toMatch(/light/i);
  });

  it('returns caution when humidity is below the minimum', () => {
    const r = assessViability({ ...ok, effectiveHumidityPct: 20, minHumidityPct: 30 });
    expect(r.level).toBe('caution');
    expect(r.reasons.join(' ')).toMatch(/humidity/i);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- viability`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `repos/my-plants-api/src/engines/viability.ts`:

```ts
export interface ViabilityInput {
  survivalMinC: number;
  survivalMaxC: number;
  minLightRank: number;
  minHumidityPct: number;
  seasonalLowC: number;
  seasonalHighC: number;
  placeLightRank: number;
  effectiveHumidityPct: number;
}

export type ViabilityLevel = 'good' | 'caution' | 'poor';

export interface ViabilityResult {
  level: ViabilityLevel;
  reasons: string[];
}

export function assessViability(i: ViabilityInput): ViabilityResult {
  const reasons: string[] = [];
  let poor = false;
  let caution = false;

  if (i.seasonalLowC < i.survivalMinC) {
    poor = true;
    reasons.push(`seasonal low ${i.seasonalLowC} °C is below the ${i.survivalMinC} °C survival minimum`);
  } else if (i.seasonalLowC < i.survivalMinC + 3) {
    caution = true;
    reasons.push(`seasonal low ${i.seasonalLowC} °C is close to the ${i.survivalMinC} °C survival minimum`);
  }

  if (i.seasonalHighC > i.survivalMaxC) {
    poor = true;
    reasons.push(`seasonal high ${i.seasonalHighC} °C is above the ${i.survivalMaxC} °C survival maximum`);
  }

  if (i.placeLightRank < i.minLightRank) {
    const gap = i.minLightRank - i.placeLightRank;
    if (gap >= 2) {
      poor = true;
      reasons.push(`light is well below the species minimum`);
    } else {
      caution = true;
      reasons.push(`light is below the species minimum`);
    }
  }

  if (i.effectiveHumidityPct < i.minHumidityPct) {
    caution = true;
    reasons.push(`humidity ${i.effectiveHumidityPct}% is below the ${i.minHumidityPct}% minimum`);
  }

  const level: ViabilityLevel = poor ? 'poor' : caution ? 'caution' : 'good';
  return { level, reasons };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- viability`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C repos/my-plants-api add src/engines/viability.ts src/engines/viability.test.ts
git -C repos/my-plants-api commit -m "feat: add pure viability engine"
```

---

## Task 8: Adaptation engine (pure)

**Files:** `src/engines/adaptation.ts`, `src/engines/adaptation.test.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-api/src/engines/adaptation.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { nextAdjustment, type AdaptationInput } from './adaptation.js';

describe('nextAdjustment', () => {
  it('keeps the multiplier when there is no signal', () => {
    expect(nextAdjustment({ current: 1, recentPostpones: 0, earlyLateRatio: 1 })).toBeCloseTo(1, 5);
  });

  it('lengthens the interval after repeated postpones', () => {
    const next = nextAdjustment({ current: 1, recentPostpones: 3, earlyLateRatio: 1 });
    expect(next).toBeGreaterThan(1);
  });

  it('shortens when the owner consistently acts early (ratio < 1)', () => {
    const next = nextAdjustment({ current: 1, recentPostpones: 0, earlyLateRatio: 0.7 });
    expect(next).toBeLessThan(1);
  });

  it('clamps within [0.5, 2]', () => {
    expect(nextAdjustment({ current: 2, recentPostpones: 10, earlyLateRatio: 2 })).toBeLessThanOrEqual(2);
    expect(nextAdjustment({ current: 0.5, recentPostpones: 0, earlyLateRatio: 0.1 })).toBeGreaterThanOrEqual(0.5);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- adaptation`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `repos/my-plants-api/src/engines/adaptation.ts`:

```ts
export interface AdaptationInput {
  current: number; // current multiplier
  recentPostpones: number; // count in the recent window
  earlyLateRatio: number; // observed interval / scheduled interval (avg over recent dones)
}

const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v));

// Small, bounded nudges so the plan adapts gradually rather than oscillating.
export function nextAdjustment(i: AdaptationInput): number {
  const postponeNudge = i.recentPostpones * 0.05; // each postpone lengthens slightly
  const cadenceNudge = (i.earlyLateRatio - 1) * 0.3; // acting early shortens, late lengthens
  return clamp(i.current + postponeNudge + cadenceNudge, 0.5, 2);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- adaptation`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C repos/my-plants-api add src/engines/adaptation.ts src/engines/adaptation.test.ts
git -C repos/my-plants-api commit -m "feat: add pure adaptation engine"
```

---

## Task 9: Owner seam + Prisma-backed modules (cities, places, plants, species seed)

> These modules are thin Prisma wiring. Each `*.service.ts` scopes queries by `ownerId`; the
> `OwnerService` resolves the single default owner (creating it on first use) so multi-user is
> a later change to this one seam. Controllers expose REST CRUD. Full DTO/controller code per
> module follows the same shape; below is the owner seam + one representative module (places),
> then the remaining modules listed with their endpoints and the one detail each adds.

- [ ] **Step 1: Owner seam**

Create `repos/my-plants-api/src/owner/owner.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';

const DEFAULT_OWNER_NAME = 'default';

@Injectable()
export class OwnerService {
  constructor(private readonly prisma: PrismaService) {}

  // v1: one owner. The whole app calls this; multi-user later replaces only this method.
  async currentOwnerId(): Promise<string> {
    const existing = await this.prisma.owner.findFirst({ where: { name: DEFAULT_OWNER_NAME } });
    if (existing) return existing.id;
    const created = await this.prisma.owner.create({ data: { name: DEFAULT_OWNER_NAME } });
    return created.id;
  }
}
```

Create `repos/my-plants-api/src/owner/owner.module.ts`:

```ts
import { Global, Module } from '@nestjs/common';
import { OwnerService } from './owner.service.js';

@Global()
@Module({ providers: [OwnerService], exports: [OwnerService] })
export class OwnerModule {}
```

- [ ] **Step 2: Species read service (rows are written by the knowledge engine)**

> The API does **not** seed species. The `Species` table is populated exclusively by
> `my-plants-knowledge-engine`'s `db:insert` script (the single writer); the API only reads
> the table. The Prisma migration here just creates the table shape (`slug`, `scientificName`,
> `record`) that the knowledge engine writes to.

Create `repos/my-plants-api/src/species/species.service.ts`:

```ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { parseSpeciesRecord, type SpeciesRecord } from '@retaxmaster/my-plants-species-schema';
import { PrismaService } from '../prisma/prisma.service.js';

@Injectable()
export class SpeciesService {
  constructor(private readonly prisma: PrismaService) {}

  async list(): Promise<{ slug: string; scientificName: string }[]> {
    return this.prisma.species.findMany({ select: { slug: true, scientificName: true } });
  }

  async record(slug: string): Promise<SpeciesRecord> {
    const row = await this.prisma.species.findUnique({ where: { slug } });
    if (!row) throw new NotFoundException(`Unknown species: ${slug}`);
    return parseSpeciesRecord(row.record); // re-validate the cached JSON on read
  }
}
```

Create `repos/my-plants-api/src/species/species.controller.ts`:

```ts
import { Controller, Get, Param } from '@nestjs/common';
import { SpeciesService } from './species.service.js';

@Controller('species')
export class SpeciesController {
  constructor(private readonly species: SpeciesService) {}

  @Get()
  list() {
    return this.species.list();
  }

  @Get(':slug')
  one(@Param('slug') slug: string) {
    return this.species.record(slug);
  }
}
```

Create `repos/my-plants-api/src/species/species.module.ts`:

```ts
import { Module } from '@nestjs/common';
import { SpeciesController } from './species.controller.js';
import { SpeciesService } from './species.service.js';

@Module({ controllers: [SpeciesController], providers: [SpeciesService], exports: [SpeciesService] })
export class SpeciesModule {}
```

- [ ] **Step 3: Cities, Places, Plants modules (Prisma CRUD scoped by owner)**

Implement, for each of `cities`, `places`, `plants`, a `*.service.ts` (methods that take the
owner id from `OwnerService` and filter/set `ownerId`), a `*.controller.ts`, and a `*.module.ts`.
**v1 exposes create/list/get only** (`GET /x`, `POST /x`, `GET /x/:id`); update/delete are a
later addition. The bodies are plain Prisma calls; here is the full set —
`repos/my-plants-api/src/places/places.service.ts`:

```ts
import { Injectable, NotFoundException } from '@nestjs/common';
import type { HumidityCharacter, LightType } from '@prisma/client';
import { OwnerService } from '../owner/owner.service.js';
import { PrismaService } from '../prisma/prisma.service.js';

export interface PlaceInput {
  cityId: string;
  name: string;
  indoor: boolean;
  lightType: LightType;
  climateControlled?: boolean;
  humidityCharacter?: HumidityCharacter;
  indoorTempMinC?: number | null;
  indoorTempMaxC?: number | null;
}

@Injectable()
export class PlacesService {
  constructor(private readonly prisma: PrismaService, private readonly owner: OwnerService) {}

  async list() {
    const ownerId = await this.owner.currentOwnerId();
    return this.prisma.place.findMany({ where: { ownerId } });
  }

  async create(input: PlaceInput) {
    const ownerId = await this.owner.currentOwnerId();
    return this.prisma.place.create({ data: { ...input, ownerId } });
  }

  async get(id: string) {
    const ownerId = await this.owner.currentOwnerId();
    const place = await this.prisma.place.findFirst({ where: { id, ownerId } });
    if (!place) throw new NotFoundException(`Unknown place: ${id}`);
    return place;
  }
}
```

Add the places controller + module + DTO, then the full cities and plants modules.

`repos/my-plants-api/src/places/create-place.dto.ts`:

```ts
import { IsBoolean, IsEnum, IsNumber, IsOptional, IsString, MinLength } from 'class-validator';
import { HumidityCharacter, LightType } from '@prisma/client';

export class CreatePlaceDto {
  @IsString() @MinLength(1) cityId!: string;
  @IsString() @MinLength(1) name!: string;
  @IsBoolean() indoor!: boolean;
  @IsEnum(LightType) lightType!: LightType;
  @IsOptional() @IsBoolean() climateControlled?: boolean;
  @IsOptional() @IsEnum(HumidityCharacter) humidityCharacter?: HumidityCharacter;
  @IsOptional() @IsNumber() indoorTempMinC?: number | null;
  @IsOptional() @IsNumber() indoorTempMaxC?: number | null;
}
```

`repos/my-plants-api/src/places/places.controller.ts`:

```ts
import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { CreatePlaceDto } from './create-place.dto.js';
import { PlacesService } from './places.service.js';

@Controller('places')
export class PlacesController {
  constructor(private readonly places: PlacesService) {}

  @Get() list() { return this.places.list(); }
  @Post() create(@Body() dto: CreatePlaceDto) { return this.places.create(dto); }
  @Get(':id') get(@Param('id') id: string) { return this.places.get(id); }
}
```

`repos/my-plants-api/src/places/places.module.ts`:

```ts
import { Module } from '@nestjs/common';
import { PlacesController } from './places.controller.js';
import { PlacesService } from './places.service.js';

@Module({ controllers: [PlacesController], providers: [PlacesService], exports: [PlacesService] })
export class PlacesModule {}
```

**Cities** — `repos/my-plants-api/src/cities/create-city.dto.ts`:

```ts
import { IsBoolean, IsNumber, IsOptional, IsString, Max, Min, MinLength } from 'class-validator';

export class CreateCityDto {
  @IsString() @MinLength(1) name!: string;
  @IsNumber() @Min(-90) @Max(90) latitude!: number;
  @IsNumber() @Min(-180) @Max(180) longitude!: number;
  @IsString() @MinLength(1) timezone!: string;
  @IsOptional() @IsBoolean() isPrimary?: boolean;
}
```

`repos/my-plants-api/src/cities/cities.service.ts`:

```ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { OwnerService } from '../owner/owner.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateCityDto } from './create-city.dto.js';

@Injectable()
export class CitiesService {
  constructor(private readonly prisma: PrismaService, private readonly owner: OwnerService) {}

  async list() {
    const ownerId = await this.owner.currentOwnerId();
    return this.prisma.city.findMany({ where: { ownerId } });
  }

  async create(dto: CreateCityDto) {
    const ownerId = await this.owner.currentOwnerId();
    return this.prisma.$transaction(async (tx) => {
      if (dto.isPrimary) {
        await tx.city.updateMany({ where: { ownerId }, data: { isPrimary: false } });
      }
      return tx.city.create({ data: { ...dto, isPrimary: dto.isPrimary ?? false, ownerId } });
    });
  }

  async get(id: string) {
    const ownerId = await this.owner.currentOwnerId();
    const city = await this.prisma.city.findFirst({ where: { id, ownerId } });
    if (!city) throw new NotFoundException(`Unknown city: ${id}`);
    return city;
  }

  async makePrimary(id: string) {
    const ownerId = await this.owner.currentOwnerId();
    await this.get(id); // ensures ownership
    return this.prisma.$transaction(async (tx) => {
      await tx.city.updateMany({ where: { ownerId }, data: { isPrimary: false } });
      return tx.city.update({ where: { id }, data: { isPrimary: true } });
    });
  }
}
```

`repos/my-plants-api/src/cities/cities.controller.ts`:

```ts
import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { CitiesService } from './cities.service.js';
import { CreateCityDto } from './create-city.dto.js';

@Controller('cities')
export class CitiesController {
  constructor(private readonly cities: CitiesService) {}

  @Get() list() { return this.cities.list(); }
  @Post() create(@Body() dto: CreateCityDto) { return this.cities.create(dto); }
  @Get(':id') get(@Param('id') id: string) { return this.cities.get(id); }
  @Post(':id/make-primary') makePrimary(@Param('id') id: string) { return this.cities.makePrimary(id); }
}
```

`repos/my-plants-api/src/cities/cities.module.ts`:

```ts
import { Module } from '@nestjs/common';
import { CitiesController } from './cities.controller.js';
import { CitiesService } from './cities.service.js';

@Module({ controllers: [CitiesController], providers: [CitiesService], exports: [CitiesService] })
export class CitiesModule {}
```

**Plants** — `repos/my-plants-api/src/plants/create-plant.dto.ts` (with optional per-task
last-done dates that become the first-due anchors):

```ts
import { Type } from 'class-transformer';
import { ArrayUnique, IsArray, IsDateString, IsEnum, IsOptional, IsString, MinLength, ValidateNested } from 'class-validator';
import { Task } from '@prisma/client';

export class LastDoneDto {
  @IsEnum(Task) task!: Task;
  @IsDateString() doneOn!: string;
}

export class CreatePlantDto {
  @IsString() @MinLength(1) placeId!: string;
  @IsString() @MinLength(1) speciesSlug!: string;
  @IsOptional() @IsString() nickname?: string;
  @IsDateString() acquiredOn!: string;
  @IsOptional() @IsArray() @ArrayUnique((d: LastDoneDto) => d.task)
  @ValidateNested({ each: true }) @Type(() => LastDoneDto)
  lastDone?: LastDoneDto[];
}
```

`repos/my-plants-api/src/plants/plants.service.ts`:

```ts
import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { OwnerService } from '../owner/owner.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreatePlantDto } from './create-plant.dto.js';

@Injectable()
export class PlantsService {
  constructor(private readonly prisma: PrismaService, private readonly owner: OwnerService) {}

  async list() {
    const ownerId = await this.owner.currentOwnerId();
    return this.prisma.plant.findMany({ where: { ownerId } });
  }

  async get(id: string) {
    const ownerId = await this.owner.currentOwnerId();
    const plant = await this.prisma.plant.findFirst({ where: { id, ownerId } });
    if (!plant) throw new NotFoundException(`Unknown plant: ${id}`);
    return plant;
  }

  async create(dto: CreatePlantDto) {
    const ownerId = await this.owner.currentOwnerId();
    const place = await this.prisma.place.findFirst({ where: { id: dto.placeId, ownerId } });
    if (!place) throw new BadRequestException(`Unknown place: ${dto.placeId}`);
    const species = await this.prisma.species.findUnique({ where: { slug: dto.speciesSlug } });
    if (!species) throw new BadRequestException(`Unknown species: ${dto.speciesSlug}`);

    return this.prisma.plant.create({
      data: {
        ownerId,
        placeId: dto.placeId,
        speciesSlug: dto.speciesSlug,
        nickname: dto.nickname,
        acquiredOn: new Date(dto.acquiredOn),
        // Optional per-task last-done dates become DONE events = the first-due anchors.
        events: dto.lastDone?.length
          ? { create: dto.lastDone.map((e) => ({ task: e.task, type: 'DONE' as const, occurredOn: new Date(e.doneOn) })) }
          : undefined,
      },
    });
  }
}
```

`repos/my-plants-api/src/plants/plants.controller.ts`:

```ts
import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { CreatePlantDto } from './create-plant.dto.js';
import { PlantsService } from './plants.service.js';

@Controller('plants')
export class PlantsController {
  constructor(private readonly plants: PlantsService) {}

  @Get() list() { return this.plants.list(); }
  @Post() create(@Body() dto: CreatePlantDto) { return this.plants.create(dto); }
  @Get(':id') get(@Param('id') id: string) { return this.plants.get(id); }
}
```

`repos/my-plants-api/src/plants/plants.module.ts`:

```ts
import { Module } from '@nestjs/common';
import { PlantsController } from './plants.controller.js';
import { PlantsService } from './plants.service.js';

@Module({ controllers: [PlantsController], providers: [PlantsService], exports: [PlantsService] })
export class PlantsModule {}
```

- [ ] **Step 4: Run tests + commit**

Run: `npm test`
Expected: PASS (engine tests still green; these modules are covered by the e2e in Task 13).

```bash
git -C repos/my-plants-api add src/owner src/species src/cities src/places src/plants
git -C repos/my-plants-api commit -m "feat: add owner seam, species read, and CRUD modules"
```

---

## Task 10: Weather module (Open-Meteo client + cache + fallback)

**Files:** `src/weather/open-meteo.client.ts`, `src/weather/weather.service.ts`, `src/weather/weather.module.ts`

- [ ] **Step 1: Implement the Open-Meteo client**

Create `repos/my-plants-api/src/weather/open-meteo.client.ts`:

```ts
import { Injectable } from '@nestjs/common';

export interface CurrentWeather {
  tempC: number;
  humidityPct: number;
  seasonalLowC: number;
  seasonalHighC: number;
}

@Injectable()
export class OpenMeteoClient {
  // Current conditions + the day's min/max. NOTE (v1 proxy): seasonalLowC/seasonalHighC are
  // the *today* forecast min/max — a coarse stand-in for true seasonal extremes used by the
  // viability semaphore. A later version can widen this to a multi-day forecast or climate
  // normals; the contract (low/high pair) stays the same.
  async fetch(latitude: number, longitude: number): Promise<CurrentWeather> {
    const url = new URL('https://api.open-meteo.com/v1/forecast');
    url.searchParams.set('latitude', String(latitude));
    url.searchParams.set('longitude', String(longitude));
    url.searchParams.set('current', 'temperature_2m,relative_humidity_2m');
    url.searchParams.set('daily', 'temperature_2m_min,temperature_2m_max');
    url.searchParams.set('forecast_days', '1');
    url.searchParams.set('timezone', 'auto');

    const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) throw new Error(`Open-Meteo ${res.status}`);
    const data = (await res.json()) as {
      current: { temperature_2m: number; relative_humidity_2m: number };
      daily: { temperature_2m_min: number[]; temperature_2m_max: number[] };
    };
    return {
      tempC: data.current.temperature_2m,
      humidityPct: data.current.relative_humidity_2m,
      seasonalLowC: data.daily.temperature_2m_min[0],
      seasonalHighC: data.daily.temperature_2m_max[0],
    };
  }
}
```

- [ ] **Step 2: Implement the cache + fallback service**

Create `repos/my-plants-api/src/weather/weather.service.ts`:

```ts
import { Injectable, Logger } from '@nestjs/common';
import { OpenMeteoClient, type CurrentWeather } from './open-meteo.client.js';

interface CacheEntry { value: CurrentWeather; at: number }
const TTL_MS = 3 * 60 * 60 * 1000; // 3 hours

@Injectable()
export class WeatherService {
  private readonly log = new Logger(WeatherService.name);
  private readonly cache = new Map<string, CacheEntry>();

  constructor(private readonly client: OpenMeteoClient) {}

  // Returns fresh weather, a still-valid cache hit, a stale cache on failure, or null if we
  // have nothing. The scheduler treats null as "neutral" — it never throws here.
  async forCity(cityId: string, latitude: number, longitude: number): Promise<CurrentWeather | null> {
    const hit = this.cache.get(cityId);
    if (hit && Date.now() - hit.at < TTL_MS) return hit.value;
    try {
      const value = await this.client.fetch(latitude, longitude);
      this.cache.set(cityId, { value, at: Date.now() });
      return value;
    } catch (err) {
      this.log.warn(`Open-Meteo failed for ${cityId}; using ${hit ? 'stale cache' : 'no'} weather: ${String(err)}`);
      return hit?.value ?? null;
    }
  }
}
```

Create `repos/my-plants-api/src/weather/weather.module.ts`:

```ts
import { Module } from '@nestjs/common';
import { OpenMeteoClient } from './open-meteo.client.js';
import { WeatherService } from './weather.service.js';

@Module({ providers: [OpenMeteoClient, WeatherService], exports: [WeatherService] })
export class WeatherModule {}
```

- [ ] **Step 3: Commit**

```bash
git -C repos/my-plants-api add src/weather
git -C repos/my-plants-api commit -m "feat: add Open-Meteo weather client with cache and fallback"
```

---

## Task 11: Care-plan service (orchestrates the engines) + cron + controller

**Files:** `src/care-plan/care-plan.service.ts`, `src/care-plan/care-plan.cron.ts`, `src/care-plan/care-plan.controller.ts`, `src/care-plan/care-plan.module.ts`, plus `src/places/place-conditions.ts`

- [ ] **Step 1: Light-rank + place-conditions helper (pure)**

Create `repos/my-plants-api/src/places/place-conditions.ts`:

```ts
import { LIGHT_LEVELS, type LightLevel } from '@retaxmaster/my-plants-species-schema';
import type { LightType } from '@prisma/client';

const LIGHT_TYPE_TO_LEVEL: Record<LightType, LightLevel> = {
  LOW: 'low',
  MEDIUM: 'medium',
  BRIGHT_INDIRECT: 'bright-indirect',
  DIRECT: 'direct',
};

export const lightRank = (level: LightLevel): number => LIGHT_LEVELS.indexOf(level);
export const placeLightRank = (lightType: LightType): number =>
  lightRank(LIGHT_TYPE_TO_LEVEL[lightType]);
```

- [ ] **Step 2: Implement the care-plan service**

`care-plan.service.ts` loads a plant (+ its species record, place, city), resolves weather via
`WeatherService`, computes effective conditions (`effectiveConditions`), derives the per-task
anchor (last `DONE` event date for the task, else the plant's `acquiredOn`), reads the
`PlantTaskAdjustment` multiplier (default 1), and applies any `TaskOverride` for the next
occurrence. It then **dispatches each scheduled task to the right engine**, never one-size-fits-all:
`WATER` → `computeNextDue` (full weather/light/season modulators + drought clamp, neutral when
weather is missing); `FERTILIZE` → `computeFertilizingDue` (in-season `fertilizing.inSeasonFrequencyDays`,
pushed far out during dormancy per `activeSeasons` + `reduceInDormancy`); `REPOT`
(`repotting.typicalIntervalMonths × 30`), `ROTATE` (`maintenance.rotationDays`), and `CLEAN_LEAVES`
(`maintenance.leafCleaningDays`) → `computeCadenceDue` (pure cadence, no weather/drought sensitivity;
`ROTATE`/`CLEAN_LEAVES` are skipped when their cadence is null). Each result is written into
`DueCache` (upsert by `plantId+task`). It exposes `recomputePlant(plantId)`, `recomputeAll()`, and
`todaysTasks(ownerId)` (reads `DueCache` where `nextDueOn < startOfTomorrow` computed in the
owner's **primary-city timezone**).

Create `repos/my-plants-api/src/care-plan/care-plan.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { parseSpeciesRecord, type SpeciesRecord } from '@retaxmaster/my-plants-species-schema';
import type { Task } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service.js';
import { WeatherService } from '../weather/weather.service.js';
import { effectiveConditions, type EffectiveConditions } from '../engines/indoor-climate.js';
import { computeCadenceDue, computeFertilizingDue, computeNextDue } from '../engines/scheduling.js';
import { hemisphereForLatitude, seasonForDate, type Hemisphere } from '../common/season/season.js';
import { startOfTomorrowUtc } from '../common/time/local-date.js';
import { lightRank, placeLightRank } from '../places/place-conditions.js';
import type { Season } from '@retaxmaster/my-plants-species-schema';

const SCHEDULED_TASKS: Task[] = ['WATER', 'FERTILIZE', 'REPOT', 'ROTATE', 'CLEAN_LEAVES'];

@Injectable()
export class CarePlanService {
  constructor(private readonly prisma: PrismaService, private readonly weather: WeatherService) {}

  async recomputePlant(plantId: string): Promise<void> {
    const plant = await this.prisma.plant.findUniqueOrThrow({
      where: { id: plantId },
      include: { species: true, place: { include: { city: true } }, adjustments: true, overrides: true },
    });
    const record = parseSpeciesRecord(plant.species.record);
    const { place } = plant;
    const { city } = place;
    const weather = await this.weather.forCity(city.id, city.latitude, city.longitude);
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
    const hemisphere = hemisphereForLatitude(city.latitude);
    const season = seasonForDate(new Date(), hemisphere);

    for (const task of SCHEDULED_TASKS) {
      // ROTATE / CLEAN_LEAVES are optional cadences — skip when the species has none.
      if (task === 'ROTATE' && record.maintenance.rotationDays === null) continue;
      if (task === 'CLEAN_LEAVES' && record.maintenance.leafCleaningDays === null) continue;

      const override = plant.overrides.find((o) => o.task === task);
      if (override) {
        await this.upsertDue(plantId, task, override.nextDueOn);
        continue;
      }

      const lastDone = await this.prisma.careEvent.findFirst({
        where: { plantId, task, type: 'DONE' },
        orderBy: { occurredOn: 'desc' },
      });
      const anchor = lastDone?.occurredOn ?? plant.acquiredOn;
      const adjustment = plant.adjustments.find((a) => a.task === task)?.multiplier ?? 1;

      const due = this.dueForTask(task, record, { effective, weatherAvailable: weather !== null, isOutdoor: !place.indoor, placeLightRank: placeLightRank(place.lightType), season, anchor, adjustment });
      await this.upsertDue(plantId, task, due);
    }
  }

  private dueForTask(
    task: Task,
    record: SpeciesRecord,
    ctx: {
      effective: EffectiveConditions;
      weatherAvailable: boolean;
      isOutdoor: boolean;
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
        reduceInDormancy: record.watering.reduceInDormancy,
        idealMinC: record.temperature.idealMinC,
        idealMaxC: record.temperature.idealMaxC,
        idealLightRank: lightRank(record.light.ideal),
        anchor: ctx.anchor,
        adjustment: ctx.adjustment,
        effective: ctx.effective,
        placeLightRank: ctx.placeLightRank,
        isOutdoor: ctx.isOutdoor,
        weatherAvailable: ctx.weatherAvailable,
        season: ctx.season,
        reduceSeason: 'winter',
      });
    }
    if (task === 'FERTILIZE') {
      return computeFertilizingDue({
        inSeasonFrequencyDays: record.fertilizing.inSeasonFrequencyDays,
        adjustment: ctx.adjustment,
        anchor: ctx.anchor,
        season: ctx.season,
        activeSeasons: record.fertilizing.activeSeasons,
        reduceInDormancy: record.fertilizing.reduceInDormancy,
      });
    }
    // REPOT / ROTATE / CLEAN_LEAVES: pure cadence.
    const cadenceDays =
      task === 'REPOT'
        ? record.repotting.typicalIntervalMonths * 30
        : task === 'ROTATE'
          ? (record.maintenance.rotationDays as number)
          : (record.maintenance.leafCleaningDays as number);
    return computeCadenceDue({ cadenceDays, adjustment: ctx.adjustment, anchor: ctx.anchor });
  }

  async recomputeAll(): Promise<void> {
    const plants = await this.prisma.plant.findMany({ select: { id: true } });
    for (const p of plants) await this.recomputePlant(p.id);
  }

  // "Today" uses the owner's primary-city timezone; due dates are DATE granularity.
  async todaysTasks(ownerId: string): Promise<{ plantId: string; task: Task; nextDueOn: Date }[]> {
    const primary = await this.prisma.city.findFirst({ where: { ownerId, isPrimary: true } });
    const tz = primary?.timezone ?? 'UTC';
    const end = startOfTomorrowUtc(tz);
    return this.prisma.dueCache.findMany({
      where: { nextDueOn: { lt: end }, plant: { ownerId } },
      select: { plantId: true, task: true, nextDueOn: true },
      orderBy: { nextDueOn: 'asc' },
    });
  }

  private async upsertDue(plantId: string, task: Task, nextDueOn: Date): Promise<void> {
    await this.prisma.dueCache.upsert({
      where: { plantId_task: { plantId, task } },
      create: { plantId, task, nextDueOn },
      update: { nextDueOn, computedAt: new Date() },
    });
  }
}
```

- [ ] **Step 3: Cron + controller + module**

Create `repos/my-plants-api/src/care-plan/care-plan.cron.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { CarePlanService } from './care-plan.service.js';

@Injectable()
export class CarePlanCron {
  constructor(private readonly carePlan: CarePlanService) {}

  @Cron(CronExpression.EVERY_DAY_AT_5AM)
  async daily(): Promise<void> {
    await this.carePlan.recomputeAll();
  }
}
```

Create `repos/my-plants-api/src/care-plan/care-plan.controller.ts`:

```ts
import { Controller, Get, Post } from '@nestjs/common';
import { OwnerService } from '../owner/owner.service.js';
import { CarePlanService } from './care-plan.service.js';

@Controller('care-plan')
export class CarePlanController {
  constructor(private readonly carePlan: CarePlanService, private readonly owner: OwnerService) {}

  @Get('today')
  async today() {
    return this.carePlan.todaysTasks(await this.owner.currentOwnerId());
  }

  @Post('recompute')
  async recompute() {
    await this.carePlan.recomputeAll();
    return { ok: true };
  }
}
```

Create `repos/my-plants-api/src/care-plan/care-plan.module.ts`:

```ts
import { Module } from '@nestjs/common';
import { WeatherModule } from '../weather/weather.module.js';
import { CarePlanController } from './care-plan.controller.js';
import { CarePlanCron } from './care-plan.cron.js';
import { CarePlanService } from './care-plan.service.js';

@Module({
  imports: [WeatherModule],
  controllers: [CarePlanController],
  providers: [CarePlanService, CarePlanCron],
  exports: [CarePlanService],
})
export class CarePlanModule {}
```

- [ ] **Step 4: Commit**

```bash
git -C repos/my-plants-api add src/care-plan src/places/place-conditions.ts
git -C repos/my-plants-api commit -m "feat: add care-plan orchestration, cron, and endpoints"
```

---

## Task 12: Feedback + Moving modules

**Files:** `src/feedback/*`, `src/moving/*`, `src/notifications/*`

- [ ] **Step 1: Feedback module**

`feedback.service.ts` records a `CareEvent` (DONE/POSTPONED/SYMPTOM), then:
- on DONE: clears any `TaskOverride` for that task and triggers `recomputePlant`.
- on POSTPONED: writes/updates a `TaskOverride` (next-due = postponed-to date) AND recomputes
  the per-task `PlantTaskAdjustment` via `nextAdjustment` using the recent postpone count, then
  recomputes the plant.
- on SYMPTOM: stores the symptom payload; maps known symptoms (e.g. yellow leaves + wet soil →
  lengthen) to an adjustment nudge, then recomputes.

Create `repos/my-plants-api/src/feedback/feedback.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { Prisma, type CareEventType, type Task } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service.js';
import { CarePlanService } from '../care-plan/care-plan.service.js';
import { nextAdjustment } from '../engines/adaptation.js';

const POSTPONE_WINDOW_DAYS = 60;

@Injectable()
export class FeedbackService {
  constructor(private readonly prisma: PrismaService, private readonly carePlan: CarePlanService) {}

  async record(input: {
    plantId: string;
    task: Task;
    type: CareEventType;
    occurredOn: Date;
    postponeToOn?: Date;
    payload?: unknown;
  }): Promise<void> {
    await this.prisma.careEvent.create({
      data: {
        plantId: input.plantId,
        task: input.task,
        type: input.type,
        occurredOn: input.occurredOn,
        ...(input.payload === undefined
          ? {}
          : { payload: input.payload as Prisma.InputJsonValue }),
      },
    });

    if (input.type === 'DONE') {
      await this.prisma.taskOverride.deleteMany({ where: { plantId: input.plantId, task: input.task } });
    }

    if (input.type === 'POSTPONED' && input.postponeToOn) {
      await this.prisma.taskOverride.upsert({
        where: { plantId_task: { plantId: input.plantId, task: input.task } },
        create: { plantId: input.plantId, task: input.task, nextDueOn: input.postponeToOn },
        update: { nextDueOn: input.postponeToOn },
      });
      await this.adapt(input.plantId, input.task);
    }

    if (input.type === 'SYMPTOM') {
      await this.adaptForSymptom(input.plantId, input.payload);
    }

    await this.carePlan.recomputePlant(input.plantId);
  }

  // Minimal v1 symptom→watering map: over-watering signs lengthen, under-watering shorten.
  private async adaptForSymptom(plantId: string, payload: unknown): Promise<void> {
    const symptom = (payload as { symptom?: string } | undefined)?.symptom;
    const nudge: Record<string, number> = {
      'yellow-leaves-wet-soil': 0.15, // likely over-watered → water less often
      'mushy-stem': 0.2,
      'wilting-dry-soil': -0.15, // under-watered → water more often
      'crispy-edges-dry-soil': -0.1,
    };
    const delta = symptom ? nudge[symptom] : undefined;
    if (delta === undefined) return; // unknown symptom: stored as an event, no adjustment
    const current = (await this.prisma.plantTaskAdjustment.findUnique({
      where: { plantId_task: { plantId, task: 'WATER' } },
    }))?.multiplier ?? 1;
    const multiplier = Math.min(2, Math.max(0.5, current + delta));
    await this.prisma.plantTaskAdjustment.upsert({
      where: { plantId_task: { plantId, task: 'WATER' } },
      create: { plantId, task: 'WATER', multiplier },
      update: { multiplier },
    });
  }

  private async adapt(plantId: string, task: Task): Promise<void> {
    const since = new Date(Date.now() - POSTPONE_WINDOW_DAYS * 86_400_000);
    const recentPostpones = await this.prisma.careEvent.count({
      where: { plantId, task, type: 'POSTPONED', occurredOn: { gte: since } },
    });
    const current = (await this.prisma.plantTaskAdjustment.findUnique({
      where: { plantId_task: { plantId, task } },
    }))?.multiplier ?? 1;
    const multiplier = nextAdjustment({ current, recentPostpones, earlyLateRatio: 1 });
    await this.prisma.plantTaskAdjustment.upsert({
      where: { plantId_task: { plantId, task } },
      create: { plantId, task, multiplier },
      update: { multiplier },
    });
  }
}
```

Create `repos/my-plants-api/src/feedback/feedback.controller.ts`:

```ts
import { Body, Controller, Param, Post } from '@nestjs/common';
import { IsDateString, IsEnum, IsOptional, IsObject } from 'class-validator';
import { CareEventType, Task } from '@prisma/client';
import { FeedbackService } from './feedback.service.js';

class FeedbackDto {
  @IsEnum(Task) task!: Task;
  @IsEnum(CareEventType) type!: CareEventType;
  @IsDateString() occurredOn!: string;
  @IsOptional() @IsDateString() postponeToOn?: string;
  @IsOptional() @IsObject() payload?: Record<string, unknown>;
}

@Controller('plants/:id/feedback')
export class FeedbackController {
  constructor(private readonly feedback: FeedbackService) {}

  @Post()
  async record(@Param('id') plantId: string, @Body() dto: FeedbackDto) {
    await this.feedback.record({
      plantId,
      task: dto.task,
      type: dto.type,
      occurredOn: new Date(dto.occurredOn),
      postponeToOn: dto.postponeToOn ? new Date(dto.postponeToOn) : undefined,
      payload: dto.payload,
    });
    return { ok: true };
  }
}
```

Create `repos/my-plants-api/src/feedback/feedback.module.ts`:

```ts
import { Module } from '@nestjs/common';
import { CarePlanModule } from '../care-plan/care-plan.module.js';
import { FeedbackController } from './feedback.controller.js';
import { FeedbackService } from './feedback.service.js';

@Module({ imports: [CarePlanModule], controllers: [FeedbackController], providers: [FeedbackService] })
export class FeedbackModule {}
```

- [ ] **Step 2: Moving module**

> **v1 scope:** the what-if simulator returns per-plant **viability** (level + reasons) against
> the target city. A full per-task *care-delta preview* (showing how each due date would shift)
> is deferred — the scheduled move already recomputes the real plan on the move date.

Create `repos/my-plants-api/src/moving/moving.service.ts`:

```ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { parseSpeciesRecord, LIGHT_LEVELS } from '@retaxmaster/my-plants-species-schema';
import { OwnerService } from '../owner/owner.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { WeatherService } from '../weather/weather.service.js';
import { CarePlanService } from '../care-plan/care-plan.service.js';
import { assessViability, type ViabilityResult } from '../engines/viability.js';
import { effectiveConditions } from '../engines/indoor-climate.js';
import { placeLightRank } from '../places/place-conditions.js';
import { startOfTomorrowUtc } from '../common/time/local-date.js';

export interface PlantViability extends ViabilityResult {
  plantId: string;
  nickname: string | null;
}

@Injectable()
export class MovingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly owner: OwnerService,
    private readonly weather: WeatherService,
    private readonly carePlan: CarePlanService,
  ) {}

  // What-if: viability of every plant against the target city's weather. Writes nothing.
  async simulate(targetCityId: string): Promise<PlantViability[]> {
    const ownerId = await this.owner.currentOwnerId();
    const city = await this.prisma.city.findFirst({ where: { id: targetCityId, ownerId } });
    if (!city) throw new NotFoundException(`Unknown city: ${targetCityId}`);
    const weather = await this.weather.forCity(city.id, city.latitude, city.longitude);
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
      return { plantId: plant.id, nickname: plant.nickname, ...result };
    });
  }

  async schedule(targetCityId: string, moveOn: string): Promise<{ id: string }> {
    const ownerId = await this.owner.currentOwnerId();
    const city = await this.prisma.city.findFirst({ where: { id: targetCityId, ownerId } });
    if (!city) throw new NotFoundException(`Unknown city: ${targetCityId}`);
    const move = await this.prisma.scheduledMove.create({
      data: { ownerId, targetCityId, moveOn: new Date(moveOn) },
    });
    return { id: move.id };
  }

  // Applies any move whose date has arrived: target becomes primary, outdoor places repoint to
  // it, then the whole garden recomputes. Idempotent via the `applied` flag.
  async applyDueMoves(now: Date = new Date()): Promise<number> {
    const ownerId = await this.owner.currentOwnerId();
    const primary = await this.prisma.city.findFirst({ where: { ownerId, isPrimary: true } });
    const cutoff = startOfTomorrowUtc(primary?.timezone ?? 'UTC', now);
    const due = await this.prisma.scheduledMove.findMany({
      where: { ownerId, applied: false, moveOn: { lt: cutoff } },
      orderBy: { moveOn: 'asc' },
    });

    for (const move of due) {
      await this.prisma.$transaction(async (tx) => {
        await tx.city.updateMany({ where: { ownerId }, data: { isPrimary: false } });
        await tx.city.update({ where: { id: move.targetCityId }, data: { isPrimary: true } });
        await tx.place.updateMany({ where: { ownerId, indoor: false }, data: { cityId: move.targetCityId } });
        await tx.scheduledMove.update({ where: { id: move.id }, data: { applied: true } });
      });
    }
    if (due.length > 0) await this.carePlan.recomputeAll();
    return due.length;
  }
}
```

Create `repos/my-plants-api/src/moving/moving.controller.ts`:

```ts
import { Body, Controller, Post } from '@nestjs/common';
import { IsDateString, IsString, MinLength } from 'class-validator';
import { MovingService } from './moving.service.js';

class SimulateDto { @IsString() @MinLength(1) targetCityId!: string; }
class ScheduleDto {
  @IsString() @MinLength(1) targetCityId!: string;
  @IsDateString() moveOn!: string;
}

@Controller('moving')
export class MovingController {
  constructor(private readonly moving: MovingService) {}

  @Post('simulate') simulate(@Body() dto: SimulateDto) { return this.moving.simulate(dto.targetCityId); }
  @Post('schedule') schedule(@Body() dto: ScheduleDto) { return this.moving.schedule(dto.targetCityId, dto.moveOn); }
}
```

Create `repos/my-plants-api/src/moving/moving.cron.ts` (runs before the care-plan recompute):

```ts
import { Injectable } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { MovingService } from './moving.service.js';

@Injectable()
export class MovingCron {
  constructor(private readonly moving: MovingService) {}

  @Cron(CronExpression.EVERY_DAY_AT_4AM) // before the 5 AM care-plan recompute
  async daily(): Promise<void> {
    await this.moving.applyDueMoves();
  }
}
```

Create `repos/my-plants-api/src/moving/moving.module.ts`:

```ts
import { Module } from '@nestjs/common';
import { CarePlanModule } from '../care-plan/care-plan.module.js';
import { WeatherModule } from '../weather/weather.module.js';
import { MovingController } from './moving.controller.js';
import { MovingCron } from './moving.cron.js';
import { MovingService } from './moving.service.js';

@Module({
  imports: [WeatherModule, CarePlanModule],
  controllers: [MovingController],
  providers: [MovingService, MovingCron],
})
export class MovingModule {}
```

- [ ] **Step 3: Notifications module (in-app, behind an interface)**

Create `repos/my-plants-api/src/notifications/notification-channel.ts`:

```ts
export interface DueNotification {
  plantId: string;
  task: string;
  nextDueOn: Date;
}

export interface NotificationChannel {
  deliver(notifications: DueNotification[]): Promise<void>;
}
```

Create `repos/my-plants-api/src/notifications/notifications.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { OwnerService } from '../owner/owner.service.js';
import { CarePlanService } from '../care-plan/care-plan.service.js';
import type { DueNotification, NotificationChannel } from './notification-channel.js';

// v1 in-app channel: exposes today's due tasks for the web to read. Email/push are future
// channels implementing the same NotificationChannel interface.
@Injectable()
export class InAppNotificationsService implements NotificationChannel {
  private latest: DueNotification[] = [];

  constructor(private readonly carePlan: CarePlanService, private readonly owner: OwnerService) {}

  async deliver(notifications: DueNotification[]): Promise<void> {
    this.latest = notifications;
  }

  async pending(): Promise<DueNotification[]> {
    const ownerId = await this.owner.currentOwnerId();
    const due = await this.carePlan.todaysTasks(ownerId);
    return due.map((d) => ({ plantId: d.plantId, task: d.task, nextDueOn: d.nextDueOn }));
  }
}
```

Create `repos/my-plants-api/src/notifications/notifications.module.ts`:

```ts
import { Module } from '@nestjs/common';
import { CarePlanModule } from '../care-plan/care-plan.module.js';
import { InAppNotificationsService } from './notifications.service.js';

@Module({ imports: [CarePlanModule], providers: [InAppNotificationsService], exports: [InAppNotificationsService] })
export class NotificationsModule {}
```

- [ ] **Step 4: Commit**

```bash
git -C repos/my-plants-api add src/feedback src/moving src/notifications
git -C repos/my-plants-api commit -m "feat: add feedback, moving, and notifications modules"
```

---

## Task 13: App wiring, bootstrap, and e2e smoke

**Files:** `src/app.module.ts`, `src/main.ts`, `test/app.e2e-spec.ts`

- [ ] **Step 1: Compose the root module**

Create `repos/my-plants-api/src/app.module.ts`:

```ts
import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { ConfigModule } from './config/config.module.js';
import { PrismaModule } from './prisma/prisma.module.js';
import { OwnerModule } from './owner/owner.module.js';
import { SpeciesModule } from './species/species.module.js';
import { CitiesModule } from './cities/cities.module.js';
import { PlacesModule } from './places/places.module.js';
import { PlantsModule } from './plants/plants.module.js';
import { WeatherModule } from './weather/weather.module.js';
import { CarePlanModule } from './care-plan/care-plan.module.js';
import { FeedbackModule } from './feedback/feedback.module.js';
import { MovingModule } from './moving/moving.module.js';
import { NotificationsModule } from './notifications/notifications.module.js';

@Module({
  imports: [
    ConfigModule,
    PrismaModule,
    OwnerModule,
    ScheduleModule.forRoot(),
    SpeciesModule,
    CitiesModule,
    PlacesModule,
    PlantsModule,
    WeatherModule,
    CarePlanModule,
    FeedbackModule,
    MovingModule,
    NotificationsModule,
  ],
})
export class AppModule {}
```

Create `repos/my-plants-api/src/main.ts`:

```ts
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module.js';
import { loadEnv } from './config/env.js';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  await app.listen(loadEnv().PORT);
}

void bootstrap();
```

- [ ] **Step 2: Write an e2e smoke that exercises the real flow**

Create `repos/my-plants-api/test/app.e2e-spec.ts`:

```ts
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Test } from '@nestjs/testing';
import { ValidationPipe, type INestApplication } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';

// Requires a running MariaDB with migrations applied and >=1 species row (inserted by the
// knowledge engine's db:insert).
describe('MyPlants API (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true })); // mirror main.ts
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('creates a city → place → plant and returns a computed care plan', async () => {
    const server = app.getHttpServer();
    const species = await request(server).get('/species').expect(200);
    expect(species.body.length).toBeGreaterThan(0);
    const slug = species.body[0].slug as string;

    const city = await request(server)
      .post('/cities')
      .send({ name: 'Test City', latitude: 19.43, longitude: -99.13, timezone: 'America/Mexico_City', isPrimary: true })
      .expect(201);

    const place = await request(server)
      .post('/places')
      .send({ cityId: city.body.id, name: 'Living room', indoor: true, lightType: 'BRIGHT_INDIRECT' })
      .expect(201);

    // Acquired long ago so every task is already overdue regardless of species intervals.
    const plant = await request(server)
      .post('/plants')
      .send({ placeId: place.body.id, speciesSlug: slug, acquiredOn: '2020-01-01' })
      .expect(201);

    await request(server).post('/care-plan/recompute').expect(201);

    const today = await request(server).get('/care-plan/today').expect(200);
    expect(Array.isArray(today.body)).toBe(true);
    expect(today.body.some((t: { plantId: string }) => t.plantId === plant.body.id)).toBe(true);
  });
});
```

- [ ] **Step 3: Run unit tests, build, then the e2e against a real DB**

Run (inside `repos/my-plants-api`, with `DB_*` exported, MariaDB up, and migrations applied).
**Before the e2e, the `Species` table must hold ≥1 row** — populate it by running the
knowledge engine's `db:insert` (Phase 2) against this DB:
```bash
npm test
npm run typecheck
npm run build
# from the workspace root, after this migration: ( cd ../my-plants-knowledge-engine && npm run db:insert )
npm run test:e2e
```
Expected: unit tests green; typecheck clean; build succeeds; with ≥1 species present, the e2e
creates the city→place→plant chain and asserts a computed plan. Fix any red at the root (per the
no-workarounds rule) — never stub the failing path.

- [ ] **Step 4: Commit**

```bash
git -C repos/my-plants-api add src/app.module.ts src/main.ts test/app.e2e-spec.ts vitest.e2e.config.ts
git -C repos/my-plants-api commit -m "feat: wire the app, bootstrap, and add an e2e smoke"
```

---

## Task 14: Register the submodule pointer in the workspace root

- [ ] **Step 1: Push the submodule and bump the pointer**

Run (from the **workspace root**):
```bash
git -C repos/my-plants-api push -u origin main
git add .gitmodules repos/my-plants-api
git commit -m "chore: add my-plants-api submodule"
git push origin main
```

---

## Self-Review

**Spec coverage** (against architecture spec → care-app modules + "Resolved decisions"):
- Owner seam (single owner, multi-user later) → Task 9. ✅
- Local MariaDB via Prisma; `DATABASE_URL` assembled from separate `DB_*` (runtime + CLI) → Tasks 2, 3. ✅
- Persistence model: species cache, plant, append-only `CareEvent`, `PlantTaskAdjustment`, `TaskOverride`, rebuildable `DueCache` → Task 3. ✅
- Pure engines: indoor-climate, scheduling — watering modulators (neutral on missing weather via `weatherAvailable`, indoor-not-weather-driven, clamps), `computeFertilizingDue` (active-seasons + dormancy), `computeCadenceDue` (rotation/leaf-cleaning/repotting), first-due anchor — viability (good/caution/poor + reasons, humidity-below-min = caution), adaptation → Tasks 5–8. ✅
- Per-task dispatch in orchestration (watering ≠ fertilizing ≠ cadence) and DATE/primary-tz day boundary via the local-date helper → Tasks 4, 11. ✅
- Weather: Open-Meteo + cache TTL + fallback to stale/neutral (never hard-fail) → Task 10. ✅
- Scheduling orchestration + daily cron + `today` endpoint (DATE granularity, primary-tz day boundary) → Task 11. ✅
- Feedback (action/postpone/symptom) → adaptation + override; moving (simulate + scheduled via the `ScheduledMove` model + a 4 AM cron that applies due moves before the 5 AM recompute) → Task 12. ✅
- Species: API reads only; rows are written exclusively by the knowledge engine's `db:insert` (single writer; the migration owns the table shape) → Task 9. ✅
- Notifications behind a channel interface (in-app v1) → Task 12. ✅
- Submodule + workspace pointer → Tasks 1, 14. ✅

**Placeholder scan:** Pure engines, config, Prisma schema (incl. `ScheduledMove`), weather, care-plan, cities, places, plants (with DTOs + first-due anchors), moving (service + controller + cron + module), feedback, and the e2e are all complete code. Feedback's controller/module are described (one endpoint) but the service is full. No "TODO"/"TBD".

**Type consistency:** `effectiveConditions`/`computeNextDue`/`assessViability`/`nextAdjustment` signatures match their callers in `care-plan.service.ts`/`feedback.service.ts`. Prisma enum names (`Task`, `LightType`, `HumidityCharacter`, `CareEventType`) are used consistently. `buildDatabaseUrl` is shared by the runtime `PrismaService`, the seed, and the CLI env writer. Imports from `@retaxmaster/my-plants-species-schema` (`parseSpeciesRecord`, `toSpeciesSlug`, `LIGHT_LEVELS`, types) match the Phase 1 barrel.
