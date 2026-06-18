# MyPlants — Phase 1: `my-plants-species-schema` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared `my-plants-species-schema` package — the single, versioned source of truth for the curated plant-species data contract that the knowledge engine and the care app both depend on.

**Architecture:** A standalone TypeScript subrepo (a git submodule at `repos/my-plants-species-schema`) that exports a Zod schema, the TypeScript types inferred from it, parse/validate helpers, and the canonical species-slug derivation. One declaration is both the runtime validator and the static type, so the contract cannot drift. Consumers install it as a packed, version-pinned dependency.

**Tech Stack:** TypeScript (strict), Zod 3, Vitest, compiled to ESM with `tsc`.

---

## Contract notes (decisions this package locks in)

- **The slug is derived, not stored.** A species is identified by `scientificName`; its
  folder name and DB key are a slug *derived* from it. To prevent drift, the derivation
  lives here as `toSpeciesSlug()` and is imported by both the knowledge engine (to write
  `species/<slug>/`) and the API (to upsert by slug). `record.json` does not contain a slug.
- **Season response in v1 = dormancy only.** The schema models seasonal behavior solely via
  `watering.reduceInDormancy` and `fertilizing` (`activeSeasons` + `reduceInDormancy`). The
  scheduler's `Mseason` is derived from these; there is no separate "season sensitivity"
  field in v1.
- **This package validates citation *shape* only.** It checks that sources have a title, a
  valid URL, and a date. Source reputation, the ≥2-corroboration rule, confidence scoring,
  and conflict handling are enforced by the knowledge-engine workflow, not here.

---

## File Structure

- `repos/my-plants-species-schema/package.json` — manifest, scripts, deps.
- `repos/my-plants-species-schema/tsconfig.json` — strict TS config for editor + tests.
- `repos/my-plants-species-schema/tsconfig.build.json` — emit config for `dist/`.
- `repos/my-plants-species-schema/vitest.config.ts` — test runner config.
- `repos/my-plants-species-schema/.gitignore` — ignore `node_modules/`, `dist/`, `*.tgz`.
- `repos/my-plants-species-schema/src/enums.ts` — controlled vocabularies.
- `repos/my-plants-species-schema/src/sections.ts` — per-section Zod object schemas.
- `repos/my-plants-species-schema/src/species-record.ts` — top-level schema, inferred `SpeciesRecord` type, parse helpers.
- `repos/my-plants-species-schema/src/slug.ts` — canonical `toSpeciesSlug()` derivation.
- `repos/my-plants-species-schema/src/index.ts` — public barrel.
- `repos/my-plants-species-schema/src/*.test.ts` — co-located tests.

**Boundary:** zero runtime dependencies beyond Zod; performs no I/O. It describes/validates one species record and derives its slug. File reading/writing belongs to the knowledge engine; querying belongs to the app.

---

## Task 1: Create the submodule and scaffold the package

**Files:**
- Create: `repos/my-plants-species-schema/package.json`
- Create: `repos/my-plants-species-schema/.gitignore`
- Create: `repos/my-plants-species-schema/tsconfig.json`
- Create: `repos/my-plants-species-schema/tsconfig.build.json`
- Create: `repos/my-plants-species-schema/vitest.config.ts`

- [ ] **Step 1: Create the GitHub repo and register it as a submodule**

These subsystems are git submodules under `repos/`. Create the public repo and register it —
do **not** run a bare `git init` inside the workspace, which would leave an unregistered
nested repo and break the submodule-pointer flow. From the **workspace root**:

```bash
gh repo create RetaxMaster/my-plants-species-schema --public --description "Shared curated plant-species data contract for MyPlants."
git submodule add git@github.com:RetaxMaster/my-plants-species-schema.git repos/my-plants-species-schema
mkdir -p repos/my-plants-species-schema/src
```

All subsequent steps run **inside** `repos/my-plants-species-schema`.

- [ ] **Step 2: Create `package.json`**

Create `repos/my-plants-species-schema/package.json`:

```json
{
  "name": "@retaxmaster/my-plants-species-schema",
  "version": "0.1.0",
  "description": "Shared curated plant-species data contract for MyPlants.",
  "type": "module",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js"
    }
  },
  "files": ["dist"],
  "scripts": {
    "build": "tsc -p tsconfig.build.json",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "typescript": "^5.5.4",
    "vitest": "^2.0.5"
  }
}
```

- [ ] **Step 3: Create `.gitignore`**

Create `repos/my-plants-species-schema/.gitignore`:

```gitignore
node_modules/
dist/
*.tgz
```

- [ ] **Step 4: Create the TS configs**

Create `repos/my-plants-species-schema/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "declaration": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "verbatimModuleSyntax": true
  },
  "include": ["src"]
}
```

Create `repos/my-plants-species-schema/tsconfig.build.json`:

```json
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "outDir": "dist",
    "rootDir": "src"
  },
  "exclude": ["src/**/*.test.ts"]
}
```

- [ ] **Step 5: Create the Vitest config**

Create `repos/my-plants-species-schema/vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
  },
});
```

- [ ] **Step 6: Install dependencies**

Run: `npm install`
Expected: `node_modules/` created, `package-lock.json` written, no errors.

- [ ] **Step 7: Commit**

```bash
git add package.json .gitignore tsconfig.json tsconfig.build.json vitest.config.ts package-lock.json
git commit -m "chore: scaffold species-schema package"
```

---

## Task 2: Controlled vocabularies (enums)

**Files:**
- Create: `repos/my-plants-species-schema/src/enums.ts`
- Test: `repos/my-plants-species-schema/src/enums.test.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-species-schema/src/enums.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import {
  CONFIDENCE_LEVELS,
  DROUGHT_TOLERANCE,
  LIGHT_LEVELS,
  SEASONS,
  SENSITIVITY,
  SOIL_DRYNESS,
} from './enums.js';

describe('controlled vocabularies', () => {
  it('orders light levels from least to most light', () => {
    expect(LIGHT_LEVELS).toEqual(['low', 'medium', 'bright-indirect', 'direct']);
  });

  it('lists the four seasons', () => {
    expect(SEASONS).toEqual(['spring', 'summer', 'autumn', 'winter']);
  });

  it('uses a shared low/medium/high scale for sensitivity, drought, and confidence', () => {
    expect(SENSITIVITY).toEqual(['low', 'medium', 'high']);
    expect(DROUGHT_TOLERANCE).toEqual(['low', 'medium', 'high']);
    expect(CONFIDENCE_LEVELS).toEqual(['low', 'medium', 'high']);
  });

  it('orders soil dryness from wettest to driest', () => {
    expect(SOIL_DRYNESS).toEqual([
      'keep-moist',
      'top-inch-dry',
      'half-dry',
      'mostly-dry',
      'fully-dry',
    ]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- enums`
Expected: FAIL — `Cannot find module './enums.js'`.

- [ ] **Step 3: Write the enums**

Create `repos/my-plants-species-schema/src/enums.ts`:

```ts
// Controlled vocabularies shared by the schema and exported for consumers.
// Arrays are intentionally ordered (least → most) so consumers can compare by index.

export const LIGHT_LEVELS = ['low', 'medium', 'bright-indirect', 'direct'] as const;
export type LightLevel = (typeof LIGHT_LEVELS)[number];

export const SEASONS = ['spring', 'summer', 'autumn', 'winter'] as const;
export type Season = (typeof SEASONS)[number];

export const SENSITIVITY = ['low', 'medium', 'high'] as const;
export type Sensitivity = (typeof SENSITIVITY)[number];

export const DROUGHT_TOLERANCE = ['low', 'medium', 'high'] as const;
export type DroughtTolerance = (typeof DROUGHT_TOLERANCE)[number];

export const CONFIDENCE_LEVELS = ['low', 'medium', 'high'] as const;
export type ConfidenceLevel = (typeof CONFIDENCE_LEVELS)[number];

export const SOIL_DRYNESS = [
  'keep-moist',
  'top-inch-dry',
  'half-dry',
  'mostly-dry',
  'fully-dry',
] as const;
export type SoilDryness = (typeof SOIL_DRYNESS)[number];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- enums`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/enums.ts src/enums.test.ts
git commit -m "feat: add controlled vocabularies for species schema"
```

---

## Task 3: Per-section schemas (with ordering refinements)

**Files:**
- Create: `repos/my-plants-species-schema/src/sections.ts`
- Test: `repos/my-plants-species-schema/src/sections.test.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-species-schema/src/sections.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import {
  fertilizingSchema,
  humiditySchema,
  lightSchema,
  maintenanceSchema,
  metadataSchema,
  nativeClimateSchema,
  repottingSchema,
  temperatureSchema,
  wateringSchema,
} from './sections.js';

describe('wateringSchema', () => {
  it('accepts a valid watering block', () => {
    expect(() =>
      wateringSchema.parse({
        baseIntervalDays: 7,
        soilDrynessBeforeWatering: 'half-dry',
        droughtTolerance: 'medium',
        temperatureSensitivity: 'high',
        lightSensitivity: 'medium',
        reduceInDormancy: true,
      }),
    ).not.toThrow();
  });

  it('rejects a non-positive interval', () => {
    expect(() =>
      wateringSchema.parse({
        baseIntervalDays: 0,
        soilDrynessBeforeWatering: 'half-dry',
        droughtTolerance: 'medium',
        temperatureSensitivity: 'high',
        lightSensitivity: 'medium',
        reduceInDormancy: true,
      }),
    ).toThrow();
  });
});

describe('temperatureSchema', () => {
  it('accepts ordered bounds', () => {
    expect(() =>
      temperatureSchema.parse({ survivalMinC: 5, idealMinC: 18, idealMaxC: 27, survivalMaxC: 35 }),
    ).not.toThrow();
  });

  it('rejects unordered bounds (ideal min above ideal max)', () => {
    expect(() =>
      temperatureSchema.parse({ survivalMinC: 5, idealMinC: 30, idealMaxC: 27, survivalMaxC: 35 }),
    ).toThrow();
  });
});

describe('lightSchema ordering', () => {
  it('accepts ordered light levels', () => {
    expect(() =>
      lightSchema.parse({ minimum: 'medium', ideal: 'bright-indirect', maximum: 'direct' }),
    ).not.toThrow();
  });

  it('rejects minimum brighter than maximum', () => {
    expect(() =>
      lightSchema.parse({ minimum: 'direct', ideal: 'medium', maximum: 'low' }),
    ).toThrow();
  });
});

describe('humiditySchema', () => {
  it('rejects humidity above 100%', () => {
    expect(() => humiditySchema.parse({ minimumPct: 40, idealPct: 120 })).toThrow();
  });

  it('rejects minimum above ideal', () => {
    expect(() => humiditySchema.parse({ minimumPct: 70, idealPct: 50 })).toThrow();
  });
});

describe('fertilizing / repotting / maintenance', () => {
  it('requires at least one active fertilizing season', () => {
    expect(() =>
      fertilizingSchema.parse({ activeSeasons: [], inSeasonFrequencyDays: 14, reduceInDormancy: true }),
    ).toThrow();
  });

  it('defaults repotting signs and maintenance pests to empty arrays', () => {
    const repotting = repottingSchema.parse({ typicalIntervalMonths: 18 });
    expect(repotting.signs).toEqual([]);
    const maintenance = maintenanceSchema.parse({
      pruning: 'Trim leggy stems in spring.',
      rotationDays: 14,
      leafCleaningDays: null,
    });
    expect(maintenance.commonPests).toEqual([]);
  });

  it('allows null maintenance cadences', () => {
    expect(() =>
      maintenanceSchema.parse({ pruning: 'none', rotationDays: null, leafCleaningDays: null }),
    ).not.toThrow();
  });

  it('rejects an empty pruning string', () => {
    expect(() =>
      maintenanceSchema.parse({ pruning: '', rotationDays: null, leafCleaningDays: null }),
    ).toThrow();
  });
});

describe('nativeClimate / metadata', () => {
  it('accepts a native climate block with optional koppen', () => {
    expect(() =>
      nativeClimateSchema.parse({
        description: 'Tropical rainforest understory.',
        hardinessMinC: 10,
        hardinessMaxC: 38,
      }),
    ).not.toThrow();
  });

  it('rejects hardiness min above max', () => {
    expect(() =>
      nativeClimateSchema.parse({ description: 'x', hardinessMinC: 40, hardinessMaxC: 10 }),
    ).toThrow();
  });

  it('requires at least one source, a valid URL, and an ISO date', () => {
    expect(() =>
      metadataSchema.parse({ confidence: 'high', sources: [], briefPath: 'brief.md' }),
    ).toThrow();
    expect(() =>
      metadataSchema.parse({
        confidence: 'high',
        sources: [{ title: 'RHS', url: 'not-a-url', accessedAt: '2026-06-18' }],
        briefPath: 'brief.md',
      }),
    ).toThrow();
    expect(() =>
      metadataSchema.parse({
        confidence: 'high',
        sources: [{ title: 'RHS', url: 'https://www.rhs.org.uk/', accessedAt: 'June 2026' }],
        briefPath: 'brief.md',
      }),
    ).toThrow();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- sections`
Expected: FAIL — `Cannot find module './sections.js'`.

- [ ] **Step 3: Write the section schemas**

Create `repos/my-plants-species-schema/src/sections.ts`:

```ts
import { z } from 'zod';
import {
  CONFIDENCE_LEVELS,
  DROUGHT_TOLERANCE,
  LIGHT_LEVELS,
  SEASONS,
  SENSITIVITY,
  SOIL_DRYNESS,
} from './enums.js';

const lightRank = (level: (typeof LIGHT_LEVELS)[number]): number => LIGHT_LEVELS.indexOf(level);

export const wateringSchema = z.object({
  baseIntervalDays: z.number().int().positive(),
  soilDrynessBeforeWatering: z.enum(SOIL_DRYNESS),
  droughtTolerance: z.enum(DROUGHT_TOLERANCE),
  temperatureSensitivity: z.enum(SENSITIVITY),
  lightSensitivity: z.enum(SENSITIVITY),
  reduceInDormancy: z.boolean(),
});

export const lightSchema = z
  .object({
    minimum: z.enum(LIGHT_LEVELS),
    ideal: z.enum(LIGHT_LEVELS),
    maximum: z.enum(LIGHT_LEVELS),
  })
  .refine((l) => lightRank(l.minimum) <= lightRank(l.ideal) && lightRank(l.ideal) <= lightRank(l.maximum), {
    message: 'light levels must satisfy minimum <= ideal <= maximum',
  });

export const temperatureSchema = z
  .object({
    survivalMinC: z.number(),
    idealMinC: z.number(),
    idealMaxC: z.number(),
    survivalMaxC: z.number(),
  })
  .refine(
    (t) =>
      t.survivalMinC <= t.idealMinC && t.idealMinC <= t.idealMaxC && t.idealMaxC <= t.survivalMaxC,
    { message: 'temperature bounds must satisfy survivalMin <= idealMin <= idealMax <= survivalMax' },
  );

export const humiditySchema = z
  .object({
    minimumPct: z.number().min(0).max(100),
    idealPct: z.number().min(0).max(100),
  })
  .refine((h) => h.minimumPct <= h.idealPct, { message: 'humidity minimumPct must be <= idealPct' });

export const fertilizingSchema = z.object({
  activeSeasons: z.array(z.enum(SEASONS)).min(1),
  inSeasonFrequencyDays: z.number().int().positive(),
  reduceInDormancy: z.boolean(),
});

export const repottingSchema = z.object({
  typicalIntervalMonths: z.number().int().positive(),
  signs: z.array(z.string().min(1)).default([]),
});

export const maintenanceSchema = z.object({
  pruning: z.string().min(1),
  rotationDays: z.number().int().positive().nullable(),
  leafCleaningDays: z.number().int().positive().nullable(),
  commonPests: z.array(z.string().min(1)).default([]),
});

export const nativeClimateSchema = z
  .object({
    description: z.string().min(1),
    koppen: z.string().optional(),
    hardinessMinC: z.number(),
    hardinessMaxC: z.number(),
  })
  .refine((n) => n.hardinessMinC <= n.hardinessMaxC, {
    message: 'hardinessMinC must be <= hardinessMaxC',
  });

export const sourceSchema = z.object({
  title: z.string().min(1),
  url: z.string().url(),
  accessedAt: z.string().date(),
});

export const metadataSchema = z.object({
  confidence: z.enum(CONFIDENCE_LEVELS),
  sources: z.array(sourceSchema).min(1),
  briefPath: z.string().min(1),
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- sections`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/sections.ts src/sections.test.ts
git commit -m "feat: add per-section species schemas with ordering refinements"
```

---

## Task 4: Top-level record, inferred type, and parse helpers

**Files:**
- Create: `repos/my-plants-species-schema/src/species-record.ts`
- Test: `repos/my-plants-species-schema/src/species-record.test.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-species-schema/src/species-record.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import {
  parseSpeciesRecord,
  safeParseSpeciesRecord,
  speciesRecordSchema,
  type SpeciesRecord,
} from './species-record.js';

const validRecord: SpeciesRecord = {
  scientificName: 'Monstera deliciosa',
  commonNames: ['Swiss cheese plant'],
  watering: {
    baseIntervalDays: 7,
    soilDrynessBeforeWatering: 'half-dry',
    droughtTolerance: 'medium',
    temperatureSensitivity: 'high',
    lightSensitivity: 'medium',
    reduceInDormancy: true,
  },
  light: { minimum: 'medium', ideal: 'bright-indirect', maximum: 'direct' },
  temperature: { survivalMinC: 5, idealMinC: 18, idealMaxC: 27, survivalMaxC: 35 },
  humidity: { minimumPct: 40, idealPct: 60 },
  fertilizing: { activeSeasons: ['spring', 'summer'], inSeasonFrequencyDays: 14, reduceInDormancy: true },
  repotting: { typicalIntervalMonths: 24, signs: ['Roots out of drainage holes'] },
  maintenance: { pruning: 'Trim leggy stems.', rotationDays: 14, leafCleaningDays: 30, commonPests: ['spider mites'] },
  nativeClimate: { description: 'Tropical rainforest understory.', koppen: 'Af', hardinessMinC: 10, hardinessMaxC: 38 },
  metadata: {
    confidence: 'high',
    sources: [{ title: 'RHS', url: 'https://www.rhs.org.uk/plants/monstera', accessedAt: '2026-06-18' }],
    briefPath: 'brief.md',
  },
};

describe('speciesRecordSchema', () => {
  it('parses a complete valid record', () => {
    expect(() => parseSpeciesRecord(validRecord)).not.toThrow();
  });

  it('rejects a record missing a required section', () => {
    const { watering, ...incomplete } = validRecord;
    void watering;
    expect(() => parseSpeciesRecord(incomplete)).toThrow();
  });

  it('safeParse returns success=false with issues on bad input', () => {
    const result = safeParseSpeciesRecord({ scientificName: '' });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues.length).toBeGreaterThan(0);
    }
  });

  it('exposes the schema object for advanced consumers', () => {
    expect(typeof speciesRecordSchema.parse).toBe('function');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- species-record`
Expected: FAIL — `Cannot find module './species-record.js'`.

- [ ] **Step 3: Write the record schema and helpers**

Create `repos/my-plants-species-schema/src/species-record.ts`:

```ts
import { z } from 'zod';
import {
  fertilizingSchema,
  humiditySchema,
  lightSchema,
  maintenanceSchema,
  metadataSchema,
  nativeClimateSchema,
  repottingSchema,
  temperatureSchema,
  wateringSchema,
} from './sections.js';

export const speciesRecordSchema = z.object({
  scientificName: z.string().min(1),
  commonNames: z.array(z.string().min(1)).default([]),
  watering: wateringSchema,
  light: lightSchema,
  temperature: temperatureSchema,
  humidity: humiditySchema,
  fertilizing: fertilizingSchema,
  repotting: repottingSchema,
  maintenance: maintenanceSchema,
  nativeClimate: nativeClimateSchema,
  metadata: metadataSchema,
});

export type SpeciesRecord = z.infer<typeof speciesRecordSchema>;

export function parseSpeciesRecord(data: unknown): SpeciesRecord {
  return speciesRecordSchema.parse(data);
}

export function safeParseSpeciesRecord(
  data: unknown,
): z.SafeParseReturnType<unknown, SpeciesRecord> {
  return speciesRecordSchema.safeParse(data);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- species-record`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/species-record.ts src/species-record.test.ts
git commit -m "feat: add top-level species record schema and parse helpers"
```

---

## Task 5: Canonical slug derivation

**Files:**
- Create: `repos/my-plants-species-schema/src/slug.ts`
- Test: `repos/my-plants-species-schema/src/slug.test.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-species-schema/src/slug.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { toSpeciesSlug } from './slug.js';

describe('toSpeciesSlug', () => {
  it('lowercases and hyphenates a binomial name', () => {
    expect(toSpeciesSlug('Monstera deliciosa')).toBe('monstera-deliciosa');
  });

  it('collapses punctuation, quotes, and repeated separators', () => {
    expect(toSpeciesSlug("Sansevieria  trifasciata 'Laurentii'")).toBe(
      'sansevieria-trifasciata-laurentii',
    );
  });

  it('strips diacritics and trims separators', () => {
    expect(toSpeciesSlug('  Aloë vera  ')).toBe('aloe-vera');
  });

  it('throws on a name with no slug-able characters', () => {
    expect(() => toSpeciesSlug('   ')).toThrow();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- slug`
Expected: FAIL — `Cannot find module './slug.js'`.

- [ ] **Step 3: Implement the slug derivation**

Create `repos/my-plants-species-schema/src/slug.ts`:

```ts
// Canonical species slug. Imported by the knowledge engine (folder name) and the API
// (DB upsert key) so the derivation never forks.
export function toSpeciesSlug(scientificName: string): string {
  const slug = scientificName
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '') // strip diacritics (combining marks)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (slug.length === 0) {
    throw new Error(`Cannot derive a slug from scientific name: ${JSON.stringify(scientificName)}`);
  }
  return slug;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- slug`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/slug.ts src/slug.test.ts
git commit -m "feat: add canonical species slug derivation"
```

---

## Task 6: Public barrel export + build verification

**Files:**
- Create: `repos/my-plants-species-schema/src/index.ts`
- Test: `repos/my-plants-species-schema/src/index.test.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-species-schema/src/index.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import * as api from './index.js';

describe('public API surface', () => {
  it('re-exports the schema, helpers, slug, types, and vocabularies', () => {
    expect(typeof api.speciesRecordSchema).toBe('object');
    expect(typeof api.parseSpeciesRecord).toBe('function');
    expect(typeof api.safeParseSpeciesRecord).toBe('function');
    expect(typeof api.toSpeciesSlug).toBe('function');
    expect(api.LIGHT_LEVELS).toContain('bright-indirect');
    expect(api.SEASONS).toContain('summer');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- index`
Expected: FAIL — `Cannot find module './index.js'`.

- [ ] **Step 3: Write the barrel**

Create `repos/my-plants-species-schema/src/index.ts`:

```ts
export * from './enums.js';
export * from './sections.js';
export * from './species-record.js';
export * from './slug.js';
```

- [ ] **Step 4: Run the full test suite**

Run: `npm test`
Expected: PASS (all tasks' tests green).

- [ ] **Step 5: Verify the build emits types and JS**

Run: `npm run build && ls dist`
Expected: `dist/index.js`, `dist/index.d.ts`, and per-module files present; no TS errors.

- [ ] **Step 6: Verify the built package imports as a consumer would**

Run:
```bash
node --input-type=module -e "import { parseSpeciesRecord, toSpeciesSlug, LIGHT_LEVELS } from './dist/index.js'; console.log(typeof parseSpeciesRecord, toSpeciesSlug('Ficus lyrata'), LIGHT_LEVELS.length);"
```
Expected: prints `function ficus-lyrata 4` — confirms the ESM `.js` specifiers and `exports` resolve from `dist/`.

- [ ] **Step 7: Commit**

```bash
git add src/index.ts src/index.test.ts
git commit -m "feat: add public barrel export and build verification for species-schema"
```

---

## Task 7: Register the submodule pointer in the workspace root

`git submodule add` (Task 1) staged `.gitmodules` and the gitlink in the workspace root, but
nothing has committed them. Without this, a fresh workspace checkout won't know the submodule
exists. Do this once the submodule's own commits exist and are pushed.

**Files:**
- Modify (workspace root): `.gitmodules`, `repos/my-plants-species-schema` (gitlink)

- [ ] **Step 1: Push the submodule's `main`**

Run (from the workspace root):
```bash
git -C repos/my-plants-species-schema push -u origin main
```

- [ ] **Step 2: Commit the submodule registration + pointer at the workspace root**

Run (from the workspace root):
```bash
git add .gitmodules repos/my-plants-species-schema
git commit -m "chore: add my-plants-species-schema submodule"
git push origin main
```
Expected: the root records `.gitmodules` and the pinned submodule commit. A fresh
`git clone --recurse-submodules` now restores everything.

---

## Self-Review

**Spec coverage** (against `2026-06-18-myplants-architecture.md` → "The shared contract" + "Resolved decisions"):
- Zod schema + inferred types + validators → Tasks 3, 4.
- All design care parameters and tolerances, including `rotationDays`/`leafCleaningDays` as numeric cadences → Task 3 sections + Task 4 record. ✅
- Ordering invariants (light, humidity, temperature, hardiness) enforced so records can't be semantically broken → Task 3 refinements. ✅
- Canonical slug derivation shared by engine + API (no fork) → Task 5, exported in Task 6. ✅
- Citation *shape* validated here; reputation/corroboration/confidence policy deferred to the knowledge-engine → Contract notes + Task 3 `sourceSchema`. ✅
- Consumed as a packed, version-pinned dependency → builds to `dist/` with types and a consumer-import check (Tasks 1, 6); pack/install lives in the workspace script. ✅
- Registered as a git submodule under `repos/` (no stray `git init`) → Task 1. ✅

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✅

**Type consistency:** `speciesRecordSchema` composes the exact section schema names from Task 3; `SpeciesRecord` inferred from it; `parseSpeciesRecord`/`safeParseSpeciesRecord`/`toSpeciesSlug` referenced consistently in Tasks 4–6. `.min(1)` (not `.nonempty()`) keeps `activeSeasons`/`sources` as ergonomic `T[]`. Enum names match across Tasks 2–6. Package name `@retaxmaster/my-plants-species-schema` matches the tarball expected by `scripts/pack-species-schema-and-install.sh`. ✅
