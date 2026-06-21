# Phase D — Blog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose each curated species' bilingual brief through a new `GET /species/:slug/brief` endpoint and add a reader-facing Blog section in the web app that lists supported species and renders the Spanish brief as plain text.

**Architecture:** The backend adds one read-only endpoint to the existing `SpeciesModule`. The only non-trivial logic is reading `commonNames` from the `record` JSON column (it is NOT a DB column), so that read is isolated into a small pure helper with its own unit test; the endpoint itself is a thin wrapper that fetches the species row, throws 404 when missing, and assembles the response from columns + the helper. The existing `GET /species` (list) and `GET /species/:slug` (care record) endpoints are left untouched. The frontend adds two pages (`/blog` and `/blog/[id]`) following the existing page style, a typed client method, a shared type, and a nav link.

**Tech Stack:** NestJS + Prisma + MariaDB (`repos/my-plants-api`), Vitest for unit tests; Nuxt 3 + Vue 3 + Nuxt UI (`repos/my-plants-web`). Note: the web app's `nuxt.config.ts` has `typescript.typeCheck: false`, so `npm run build` alone does NOT catch type errors — verify web code with `npm run build && npm run typecheck` (the `typecheck` script runs `nuxt typecheck` = `vue-tsc`, which does catch type errors). The species contract comes from `@retaxmaster/my-plants-species-schema` (`parseSpeciesRecord`).

---

## File structure

Backend (`repos/my-plants-api`):

- `src/species/species.brief.ts` — **new.** Pure helper `extractCommonNames(record: unknown): string[]` and the response shape `SpeciesBrief`. One responsibility: turn a raw `record` JSON value into the `commonNames` array via `parseSpeciesRecord`. Pure → unit-testable with no database.
- `src/species/species.brief.test.ts` — **new.** Unit test for `extractCommonNames`.
- `src/species/species.service.ts` — **modify** (currently lines 1-18). Add a `brief(slug)` method that fetches the row, 404s when missing, and assembles `{ slug, scientificName, commonNames, briefEs, briefEn }` using the helper. Leave `list()` and `record()` unchanged.
- `src/species/species.controller.ts` — **modify** (currently lines 1-17). Add the `GET :slug/brief` route. Leave the two existing routes unchanged.

Frontend (`repos/my-plants-web`):

- `types/api.ts` — **modify** (currently lines 1-45). Add the `SpeciesBrief` interface.
- `composables/useApi.ts` — **modify** (currently lines 1-36). Add `getSpeciesBrief(slug)` and import the new type.
- `pages/blog/index.vue` — **new.** Lists supported species (slug + scientificName), each linking to `/blog/<slug>`.
- `pages/blog/[id].vue` — **new.** Fetches the brief and renders `briefEs` as plain text with `white-space: pre-wrap`, with scientificName + commonNames as a header.
- `components/AppNav.vue` — **modify** (currently lines 1-15). Add a "Blog" nav link.

> **Route note:** the existing `GET :slug` route in `species.controller.ts` is declared with `@Get(':slug')`. NestJS matches static path segments before the param when the new route is `@Get(':slug/brief')` (different segment count), so ordering is not ambiguous — `/species/foo/brief` only matches the two-segment route. No reordering needed.

---

## Task 1: Pure helper to read `commonNames` from the record JSON

**Files:**
- Create: `repos/my-plants-api/src/species/species.brief.ts`
- Test: `repos/my-plants-api/src/species/species.brief.test.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-api/src/species/species.brief.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { extractCommonNames } from './species.brief.js';

// A complete VALID species record. parseSpeciesRecord re-validates the JSON,
// so the fixture must satisfy the schema in full; commonNames is the field under test.
// Source of truth for the shape: @retaxmaster/my-plants-species-schema
// (modeled on its own src/species-record.test.ts validRecord).
const baseRecord = {
  scientificName: 'Monstera deliciosa',
  commonNames: ['Costilla de Adán', 'Swiss cheese plant'],
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
  },
};

describe('extractCommonNames', () => {
  it('returns the commonNames array parsed from the record JSON', () => {
    expect(extractCommonNames(baseRecord)).toEqual([
      'Costilla de Adán',
      'Swiss cheese plant',
    ]);
  });

  it('returns an empty array when the record has no commonNames (schema default)', () => {
    const { commonNames: _omit, ...withoutCommonNames } = baseRecord;
    expect(extractCommonNames(withoutCommonNames)).toEqual([]);
  });
});
```

> **Note for the implementer:** the fixture above is a complete, valid `SpeciesRecord`. The contract in `@retaxmaster/my-plants-species-schema` is the source of truth for its shape. Never weaken the test by stubbing or bypassing `parseSpeciesRecord`. The fields under test (`commonNames` present → returned; absent → `[]` by schema default) must stay exactly as asserted.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd repos/my-plants-api && npx vitest run src/species/species.brief.test.ts`
Expected: FAIL — `Failed to resolve import "./species.brief.js"` / `extractCommonNames is not a function` (the file does not exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `repos/my-plants-api/src/species/species.brief.ts`:

```ts
import { parseSpeciesRecord } from '@retaxmaster/my-plants-species-schema';

/** The Blog brief read model: bilingual brief + species identity. */
export interface SpeciesBrief {
  slug: string;
  scientificName: string;
  commonNames: string[];
  briefEs: string | null;
  briefEn: string | null;
}

/**
 * commonNames is NOT a DB column — it lives inside the species `record` JSON.
 * We re-validate the cached JSON on read (same discipline as SpeciesService.record)
 * and return the parsed commonNames (the schema defaults it to []).
 */
export function extractCommonNames(record: unknown): string[] {
  return parseSpeciesRecord(record).commonNames;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd repos/my-plants-api && npx vitest run src/species/species.brief.test.ts`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
cd repos/my-plants-api
git add src/species/species.brief.ts src/species/species.brief.test.ts
git commit -m "feat(species): add pure helper to read commonNames from record JSON for brief"
```

---

## Task 2: `SpeciesService.brief()` — assemble the brief, 404 on unknown slug

**Files:**
- Modify: `repos/my-plants-api/src/species/species.service.ts:1-18`

- [ ] **Step 1: Add the `brief` method (no test of its own — exercised via the controller route in Task 3's manual check; the interesting logic is the helper unit-tested in Task 1)**

In `repos/my-plants-api/src/species/species.service.ts`, change the import line (line 2) to also pull the new helper + type, and add the `brief` method after `record`.

Replace the current import block (lines 1-3):

```ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { parseSpeciesRecord, type SpeciesRecord } from '@retaxmaster/my-plants-species-schema';
import { PrismaService } from '../prisma/prisma.service.js';
```

with:

```ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { parseSpeciesRecord, type SpeciesRecord } from '@retaxmaster/my-plants-species-schema';
import { PrismaService } from '../prisma/prisma.service.js';
import { extractCommonNames, type SpeciesBrief } from './species.brief.js';
```

Then add this method immediately after the closing brace of `record()` (after line 17, inside the class):

```ts
  async brief(slug: string): Promise<SpeciesBrief> {
    const row = await this.prisma.species.findUnique({ where: { slug } });
    if (!row) throw new NotFoundException(`Unknown species: ${slug}`);
    return {
      slug: row.slug,
      scientificName: row.scientificName,
      commonNames: extractCommonNames(row.record), // not a column; lives in record JSON
      briefEs: row.briefEs,
      briefEn: row.briefEn,
    };
  }
```

- [ ] **Step 2: Verify the service still compiles (typecheck via the full test run is in Task 3; here just confirm no obvious type error)**

Run: `cd repos/my-plants-api && npx tsc --noEmit -p tsconfig.json`
Expected: no errors (exit code 0). The `row.briefEs` / `row.briefEn` are `string | null` from Prisma, matching `SpeciesBrief`.

- [ ] **Step 3: Commit**

```bash
cd repos/my-plants-api
git add src/species/species.service.ts
git commit -m "feat(species): add SpeciesService.brief assembling the bilingual brief read model"
```

---

## Task 3: `GET /species/:slug/brief` controller route

**Files:**
- Modify: `repos/my-plants-api/src/species/species.controller.ts:1-17`

- [ ] **Step 1: Add the route**

Replace the entire contents of `repos/my-plants-api/src/species/species.controller.ts` with:

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

  @Get(':slug/brief')
  brief(@Param('slug') slug: string) {
    return this.species.brief(slug);
  }
}
```

- [ ] **Step 2: Run the whole API suite (confirms nothing regressed and the helper test still passes)**

Run: `cd repos/my-plants-api && npm test`
Expected: PASS — all existing suites green plus `src/species/species.brief.test.ts` (2 passed).

- [ ] **Step 3: Manual endpoint check against a running API**

Start the API locally (from the workspace root: `./run.sh`, or per `docs/local-development.md`). Then, with at least one seeded species slug available (list them via the next command):

```bash
# 1. Find a real slug:
curl -s http://localhost:8000/species | head
# 2. Fetch its brief (replace <slug>):
curl -s http://localhost:8000/species/<slug>/brief
# 3. Unknown slug must 404:
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/species/does-not-exist/brief
```

Expected:
- Command 2 returns JSON `{ "slug": "...", "scientificName": "...", "commonNames": [...], "briefEs": "..."|null, "briefEn": "..."|null }`.
- Command 3 prints `404`.

> If the API port is not 3000, read it from `repos/my-plants-api/.env` / `main.ts`; do not edit `.env`.

- [ ] **Step 4: Commit**

```bash
cd repos/my-plants-api
git add src/species/species.controller.ts
git commit -m "feat(species): expose GET /species/:slug/brief endpoint"
```

---

## Task 4: Frontend type + API client method

**Files:**
- Modify: `repos/my-plants-web/types/api.ts:1-45`
- Modify: `repos/my-plants-web/composables/useApi.ts:1-36`

- [ ] **Step 1: Add the `SpeciesBrief` type**

In `repos/my-plants-web/types/api.ts`, add this interface right after the `SpeciesSummary` line (after line 5):

```ts
export interface SpeciesBrief {
  slug: string;
  scientificName: string;
  commonNames: string[];
  briefEs: string | null;
  briefEn: string | null;
}
```

- [ ] **Step 2: Add `getSpeciesBrief` to the client and import the type**

In `repos/my-plants-web/composables/useApi.ts`, **add `SpeciesBrief` to the EXISTING `import type { … } from '../types/api.js'` line — do not remove names already there** (earlier phases added types such as `PlantCare` and `CitySearchResult`; keep every name that is currently imported and just insert `SpeciesBrief`, keeping the list alphabetically ordered). The result should look like the block below (the exact set of pre-existing names depends on what earlier phases left in place — preserve them all):

```ts
import type {
  City, CreateCity, CreatePlace, CreatePlant, DueTaskResponse, Feedback, Place, Plant,
  PlantViability, SpeciesBrief, SpeciesSummary,
} from '../types/api.js';
```

Then add the method inside the returned object, immediately after the `listSpecies` line (after line 12):

```ts
    getSpeciesBrief: (slug: string) => api<SpeciesBrief>(`/species/${slug}/brief`),
```

- [ ] **Step 3: Commit**

```bash
cd repos/my-plants-web
git add types/api.ts composables/useApi.ts
git commit -m "feat(web): add SpeciesBrief type and getSpeciesBrief api client method"
```

---

## Task 5: `/blog` index page (list supported species)

**Files:**
- Create: `repos/my-plants-web/pages/blog/index.vue`

- [ ] **Step 1: Create the page**

Create `repos/my-plants-web/pages/blog/index.vue` (mirrors the `pages/plants/index.vue` style — `useApi` + `useAsyncData`, `UCard` + `NuxtLink`):

```vue
<script setup lang="ts">
const api = useApi();
const { data: species } = await useAsyncData('blog-species-list', () => api.listSpecies());
</script>

<template>
  <div>
    <h2 class="text-lg font-semibold mb-3">Blog</h2>
    <p v-if="!species?.length" class="text-gray-500">No species yet.</p>
    <div class="grid gap-2">
      <UCard v-for="s in species" :key="s.slug">
        <NuxtLink :to="`/blog/${s.slug}`" class="font-medium italic hover:underline">
          {{ s.scientificName }}
        </NuxtLink>
      </UCard>
    </div>
  </div>
</template>
```

- [ ] **Step 2: Commit**

```bash
cd repos/my-plants-web
git add pages/blog/index.vue
git commit -m "feat(web): add /blog index listing supported species"
```

---

## Task 6: `/blog/[id]` detail page (render briefEs as plain text)

**Files:**
- Create: `repos/my-plants-web/pages/blog/[id].vue`

- [ ] **Step 1: Create the page**

Create `repos/my-plants-web/pages/blog/[id].vue` (mirrors `pages/plants/[id].vue` style — route param + `useAsyncData`; renders `briefEs` with `white-space: pre-wrap`, NO Markdown parsing):

```vue
<script setup lang="ts">
const route = useRoute();
const api = useApi();
const slug = route.params.id as string;
const { data: brief } = await useAsyncData(`blog-${slug}`, () => api.getSpeciesBrief(slug));
</script>

<template>
  <div v-if="brief">
    <NuxtLink to="/blog" class="text-sm text-gray-500 hover:underline">← All articles</NuxtLink>
    <h2 class="text-xl font-bold italic mt-2">{{ brief.scientificName }}</h2>
    <p v-if="brief.commonNames.length" class="text-gray-500">
      {{ brief.commonNames.join(', ') }}
    </p>

    <p v-if="!brief.briefEs" class="text-gray-500 mt-4">No article available yet.</p>
    <article v-else class="mt-4 whitespace-pre-wrap leading-relaxed">{{ brief.briefEs }}</article>
  </div>
  <p v-else class="text-gray-500">Loading…</p>
</template>
```

> `whitespace-pre-wrap` is the Tailwind utility for CSS `white-space: pre-wrap` — it preserves the brief's line breaks while wrapping long lines. The brief text is rendered as `{{ ... }}` interpolation (escaped text), so no Markdown/HTML is parsed — exactly the spec's "plain text, this iteration" requirement.

- [ ] **Step 2: Commit**

```bash
cd repos/my-plants-web
git add pages/blog/[id].vue
git commit -m "feat(web): add /blog/:slug rendering the Spanish brief as plain text"
```

---

## Task 7: Add "Blog" link to the app nav

**Files:**
- Modify: `repos/my-plants-web/components/AppNav.vue:1-15`

- [ ] **Step 1: Add the link**

In `repos/my-plants-web/components/AppNav.vue`, add a Blog entry to the `links` array (after the `Moving` entry, line 7). Replace the array:

```ts
const links = [
  { label: 'Today', to: '/', icon: 'i-heroicons-sun' },
  { label: 'Plants', to: '/plants', icon: 'i-heroicons-sparkles' },
  { label: 'Places', to: '/places', icon: 'i-heroicons-home' },
  { label: 'Cities', to: '/cities', icon: 'i-heroicons-map-pin' },
  { label: 'Moving', to: '/moving', icon: 'i-heroicons-truck' },
];
```

with:

```ts
const links = [
  { label: 'Today', to: '/', icon: 'i-heroicons-sun' },
  { label: 'Plants', to: '/plants', icon: 'i-heroicons-sparkles' },
  { label: 'Places', to: '/places', icon: 'i-heroicons-home' },
  { label: 'Cities', to: '/cities', icon: 'i-heroicons-map-pin' },
  { label: 'Moving', to: '/moving', icon: 'i-heroicons-truck' },
  { label: 'Blog', to: '/blog', icon: 'i-heroicons-book-open' },
];
```

- [ ] **Step 2: Build + typecheck the web app (covers the new pages, client method, type, and nav)**

Run: `cd repos/my-plants-web && npm run build && npm run typecheck`
Expected: both succeed. The build bundles the new pages, and `npm run typecheck` (`nuxt typecheck` = `vue-tsc`) reports no TypeScript errors — the new `getSpeciesBrief` call and `SpeciesBrief` type resolve and the two new pages typecheck. (`npm run build` alone does NOT typecheck because the web `nuxt.config.ts` sets `typescript.typeCheck: false`, so the explicit `typecheck` step is required to catch type errors.)

- [ ] **Step 3: Manual UI check against the running stack**

With both API and web running (`./run.sh`):
- Navigate to the app, click the new **Blog** nav link → `/blog` lists species by scientific name.
- Click a species → `/blog/<slug>` shows the scientific name + comma-joined common names as a header and the Spanish brief below, with line breaks preserved. If a species has no `briefEs`, it shows "No article available yet."

- [ ] **Step 4: Commit**

```bash
cd repos/my-plants-web
git add components/AppNav.vue
git commit -m "feat(web): add Blog link to app nav"
```

---

## Self-review notes (spec coverage)

- **D.1 endpoint** `GET /species/:slug/brief` → Tasks 1-3. Returns exactly `{ slug, scientificName, commonNames, briefEs, briefEn }`; `commonNames` read from `record` JSON via `parseSpeciesRecord` (Task 1 helper); 404 on unknown slug (Task 2); existing `GET /species` and `GET /species/:slug` untouched (Task 3 keeps both routes verbatim).
- **D.2 `/blog` list** → Task 5 (uses `listSpecies()`, links to `/blog/<slug>`).
- **D.2 `/blog/:id` detail** → Task 6 (uses `getSpeciesBrief`, renders `briefEs` as plain text with `whitespace-pre-wrap`, scientificName + commonNames header, no Markdown).
- **D.2 nav link** → Task 7.
- **Shared contract** → Task 4: `SpeciesBrief` type and `api.getSpeciesBrief(slug)` match the spec's exact names and signature.
- **Conventions:** ESM imports use `.js` suffixes (matches existing files); Prisma access stays in `SpeciesService` via the injected `PrismaService`; no `.env` writes; Vitest unit test for the pure helper; web verified via `npm run build && npm run typecheck` (the web `npm run build` does not typecheck — `nuxt.config.ts` has `typescript.typeCheck: false` — so `npm run typecheck`/`vue-tsc` is what catches type errors).

---

## Execution handoff

After the workspace-level wrap-up (multi-repo feature workflow: branch, verify with `./scripts/test-all.sh`, merge/push the affected submodules, then bump the workspace submodule pointers), Phase D is complete. The species-schema package is unchanged here, so the pack-and-install step does not apply to this phase.
