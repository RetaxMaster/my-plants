# Enrichment v2 — Phase 5: Friendly naming (common name primary) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the colloquial common name the primary, human-facing name across the app, with the scientific name always shown in small italic parentheses.

**Architecture:** The API enriches the responses the web reads for naming with two flat fields — `speciesScientificName` and `speciesCommonName` — derived from the species record via the `primaryCommonName` helper (single source). The web renders one display rule via a small helper.

**Scope note:** per the spec (B.3), names go on the **plant list, plant detail, species list, and Moving simulation** — which covers every naming surface, because the Today view cross-references the plant list and the plant page reads the plant detail. The today/care payloads are intentionally not enriched (no never-read fields). Render the scientific name in **parentheses** next to the primary name, per the spec's `Common name *(Scientific name)*` format.

**Tech Stack:** TypeScript, NestJS, Prisma, Nuxt 3 / Vue 3, Vitest.

**Repos:** `repos/my-plants-api`, then `repos/my-plants-web`.

---

### Task 1: API — enrich plant list & detail with names

**Files:**
- Modify: `repos/my-plants-api/src/plants/plants.service.ts`
- Test: `repos/my-plants-api/src/plants/*.test.ts` (extend or add a focused test)

- [ ] **Step 1: Add a private name-mapper** to `PlantsService` (import `primaryCommonName` from the schema):

```ts
import { parseSpeciesRecord, primaryCommonName } from '@retaxmaster/my-plants-species-schema';
```

```ts
  // Flatten the species' human-facing names onto a plant response (single source: primaryCommonName).
  private withNames<T extends { species: { record: unknown; scientificName: string } }>(plant: T) {
    const { species, ...rest } = plant;
    return {
      ...rest,
      speciesScientificName: species.scientificName,
      speciesCommonName: primaryCommonName(parseSpeciesRecord(species.record)),
    };
  }
```

- [ ] **Step 2: Use it in `list` and `get`** — add `include: { species: true }` and map:

```ts
  async list() {
    const ownerId = await this.owner.currentOwnerId();
    const plants = await this.prisma.plant.findMany({ where: { ownerId }, include: { species: true } });
    return plants.map((p) => this.withNames(p));
  }

  async get(id: string) {
    const ownerId = await this.owner.currentOwnerId();
    const plant = await this.prisma.plant.findFirst({ where: { id, ownerId }, include: { species: true } });
    if (!plant) throw new NotFoundException(`Unknown plant: ${id}`);
    return this.withNames(plant);
  }
```

- [ ] **Step 3: Write a failing test** — `GET /plants` items carry `speciesCommonName` + `speciesScientificName`. Mirror existing plants tests:

```ts
it('plant list includes the species common + scientific names', async () => {
  // ...seed species with commonNames: ['Snake plant'], scientificName 'Dracaena trifasciata'...
  const [p] = await service.list();
  expect(p.speciesScientificName).toBe('Dracaena trifasciata');
  expect(p.speciesCommonName).toBe('Snake plant');
});
```

- [ ] **Step 4: Run → green** — `cd repos/my-plants-api && npm test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/plants/plants.service.ts src/plants/*.test.ts
git commit -m "feat: expose species common + scientific names on plant list/detail"
```

---

### Task 2: API — enrich species list & moving simulation

**Files:**
- Modify: `repos/my-plants-api/src/species/species.service.ts` (`list`)
- Modify: `repos/my-plants-api/src/moving/moving.service.ts` (`simulate` + `PlantViability`)
- Test: extend the respective tests

- [ ] **Step 1: Species list** — return a common name too. Replace `list`:

```ts
import { parseSpeciesRecord, primaryCommonName, type SpeciesRecord } from '@retaxmaster/my-plants-species-schema';
```

```ts
  async list(): Promise<{ slug: string; scientificName: string; commonName: string }[]> {
    const rows = await this.prisma.species.findMany({ select: { slug: true, scientificName: true, record: true } });
    return rows.map((r) => ({
      slug: r.slug,
      scientificName: r.scientificName,
      commonName: primaryCommonName(parseSpeciesRecord(r.record)),
    }));
  }
```

- [ ] **Step 2: Moving simulation** — add the names to `PlantViability` and the mapped result. In `moving.service.ts`:

```ts
export interface PlantViability extends ViabilityResult {
  plantId: string;
  nickname: string | null;
  speciesSlug: string;
  speciesScientificName: string;
  speciesCommonName: string;
}
```

In the `simulate` map return, add (the loop already has `record`):

```ts
      return {
        plantId: plant.id,
        nickname: plant.nickname,
        speciesSlug: plant.speciesSlug,
        speciesScientificName: record.scientificName,
        speciesCommonName: primaryCommonName(record),
        ...result,
      };
```

Add `primaryCommonName` to the existing schema import in `moving.service.ts`.

- [ ] **Step 3: Write failing tests** for both (species list item has `commonName`; a simulate result has the two name fields). Mirror existing tests.

- [ ] **Step 4: Run → green** — `npm test` → PASS; then `npm run build && npx tsc --noEmit` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/species/species.service.ts src/moving/moving.service.ts src/species/*.test.ts src/moving/*.test.ts
git commit -m "feat: expose common name on species list + moving simulation"
```

---

### Task 3: Web — types + display-name helper

**Files:**
- Modify: `repos/my-plants-web/types/api.ts`
- Create: `repos/my-plants-web/utils/displayName.ts`
- Test: `repos/my-plants-web/utils/displayName.test.ts`

- [ ] **Step 1: Update types** — in `types/api.ts`:

```ts
export interface SpeciesSummary { slug: string; scientificName: string; commonName: string }

export interface Plant {
  id: string; placeId: string; speciesSlug: string; nickname: string | null; acquiredOn: string;
  speciesScientificName: string; speciesCommonName: string;
}

export interface PlantViability {
  plantId: string; nickname: string | null; speciesSlug: string;
  speciesScientificName: string; speciesCommonName: string;
  level: ViabilityLevel; reasons: string[];
}
```

- [ ] **Step 2: Write the failing test** — `utils/displayName.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { speciesPrimaryName, plantTitle } from './displayName.js';

describe('displayName', () => {
  it('species primary name prefers the common name', () => {
    expect(speciesPrimaryName({ speciesCommonName: 'Snake plant', speciesScientificName: 'Dracaena trifasciata' }))
      .toBe('Snake plant');
  });
  it('falls back to scientific then slug', () => {
    expect(speciesPrimaryName({ speciesCommonName: '', speciesScientificName: '', speciesSlug: 'x' })).toBe('x');
  });
  it('plant title prefers the nickname', () => {
    expect(plantTitle({ nickname: 'Monty', speciesCommonName: 'Snake plant', speciesScientificName: 'D. trifasciata' }))
      .toBe('Monty');
  });
  it('plant title falls back to the common name when there is no nickname', () => {
    expect(plantTitle({ nickname: null, speciesCommonName: 'Snake plant', speciesScientificName: 'D. trifasciata' }))
      .toBe('Snake plant');
  });
});
```

- [ ] **Step 3: Implement** — `utils/displayName.ts`:

```ts
// The species' human-facing name: common name, then scientific, then slug.
export function speciesPrimaryName(s: {
  speciesCommonName?: string | null;
  speciesScientificName?: string | null;
  speciesSlug?: string | null;
}): string {
  return s.speciesCommonName || s.speciesScientificName || s.speciesSlug || '';
}

// A plant's title: the owner's nickname if set, otherwise the species' primary name.
export function plantTitle(p: {
  nickname?: string | null;
  speciesCommonName?: string | null;
  speciesScientificName?: string | null;
  speciesSlug?: string | null;
}): string {
  return p.nickname || speciesPrimaryName(p);
}
```

- [ ] **Step 4: Run → green** — `cd repos/my-plants-web && npx vitest run utils/displayName.test.ts` → PASS.

- [ ] **Step 5: Commit**

```bash
git add types/api.ts utils/displayName.ts utils/displayName.test.ts
git commit -m "feat: web display-name helper + name fields on plant/species types"
```

---

### Task 4: Web — render the display rule everywhere

**Files:**
- Modify: `repos/my-plants-web/pages/plants/index.vue`
- Modify: `repos/my-plants-web/pages/plants/[id].vue`
- Modify: `repos/my-plants-web/pages/index.vue`
- Modify: `repos/my-plants-web/pages/plants/new.vue`
- Modify: `repos/my-plants-web/pages/moving.vue`
- Modify: `repos/my-plants-web/pages/blog/index.vue`
- Modify: `repos/my-plants-web/pages/blog/[id].vue`

For each, import the helper and render the **primary name** followed by the scientific name in **small italic parentheses** (spec format `Common name *(Scientific name)*`). Render the parenthesized suffix only when the scientific name is known and differs from the primary title (avoids `Dracaena (Dracaena)` when the common name is missing and the title already is the scientific name).

- [ ] **Step 1: `pages/plants/index.vue`** — replace the card link/subtitle:

```vue
<script setup lang="ts">
import { plantTitle } from '../../utils/displayName.js';
const api = useApi();
const { data: plants } = await useAsyncData('plants-list', () => api.listPlants());
</script>
<!-- in template, per card: -->
<div>
  <NuxtLink :to="`/plants/${p.id}`" class="font-medium hover:underline">{{ plantTitle(p) }}</NuxtLink>
  <span v-if="p.speciesScientificName && p.speciesScientificName !== plantTitle(p)" class="text-xs text-gray-500 italic"> ({{ p.speciesScientificName }})</span>
</div>
```

- [ ] **Step 2: `pages/index.vue`** — apply the full display rule (title + parenthesized scientific) in the per-plant header. Expose a plant lookup and use it in the template:

```ts
import { plantTitle } from '../utils/displayName.js';
import type { Plant } from '../types/api.js';
const plantById = (id: string): Plant | undefined => (plants.value ?? []).find((x) => x.id === id);
const plantName = (id: string): string => {
  const p = plantById(id);
  return p ? plantTitle(p) : id;
};
```

In the template, replace the card header `NuxtLink` so the scientific name shows in italic parentheses, matching the other surfaces:

```vue
<template #header>
  <NuxtLink :to="`/plants/${plantId}`" class="font-medium hover:underline">{{ plantName(plantId) }}</NuxtLink>
  <span
    v-if="plantById(plantId)?.speciesScientificName && plantById(plantId)?.speciesScientificName !== plantName(plantId)"
    class="text-xs text-gray-500 italic"
  > ({{ plantById(plantId)?.speciesScientificName }})</span>
</template>
```

- [ ] **Step 3: `pages/plants/[id].vue`** — the header uses `getPlant` (now carrying names):

```vue
<script setup lang="ts">
import { plantTitle } from '../../utils/displayName.js';
// ...existing...
</script>
<!-- header -->
<h2 class="text-xl font-bold mt-2">
  {{ plantTitle(plant) }}
  <span v-if="plant.speciesScientificName && plant.speciesScientificName !== plantTitle(plant)" class="text-base font-normal text-gray-500 italic">({{ plant.speciesScientificName }})</span>
</h2>
```

(Remove the old `plant.speciesSlug` subtitle line.)

- [ ] **Step 4: `pages/plants/new.vue`** — species dropdown label shows common + scientific:

```ts
const speciesOptions = computed(() =>
  (species.value ?? []).map((s) => ({ label: `${s.commonName} (${s.scientificName})`, value: s.slug })),
);
```

- [ ] **Step 5: `pages/moving.vue`** — card title uses the names:

```vue
<script setup lang="ts">
import { speciesPrimaryName } from '../utils/displayName.js';
// ...existing...
</script>
<!-- per result card -->
<div>
  <span class="font-medium">{{ r.nickname || speciesPrimaryName(r) }}</span>
  <span v-if="r.speciesScientificName && r.speciesScientificName !== (r.nickname || speciesPrimaryName(r))" class="text-xs text-gray-500 italic"> ({{ r.speciesScientificName }})</span>
</div>
```

- [ ] **Step 6: `pages/blog/index.vue`** — list by common name, scientific italic underneath:

```vue
<div>
  <NuxtLink :to="`/blog/${s.slug}`" class="font-medium hover:underline">{{ s.commonName || s.scientificName }}</NuxtLink>
  <span v-if="s.scientificName && s.scientificName !== (s.commonName || s.scientificName)" class="text-xs text-gray-500 italic"> ({{ s.scientificName }})</span>
</div>
```

- [ ] **Step 7: `pages/blog/[id].vue`** — common name as the title, scientific italic underneath (the brief already exposes `commonNames` + `scientificName`):

```vue
<h2 class="text-xl font-bold mt-2">
  {{ brief.commonNames[0] ?? brief.scientificName }}
  <span v-if="brief.commonNames.length" class="text-base font-normal text-gray-500 italic">({{ brief.scientificName }})</span>
</h2>
```

- [ ] **Step 8: Build + typecheck** (the gate for web):

Run: `cd repos/my-plants-web && npm run build && npm run typecheck`
Expected: PASS. (`nuxt build` does NOT typecheck — `npm run typecheck` is the real gate.)

- [ ] **Step 9: Commit**

```bash
git add pages
git commit -m "feat: render common name as the primary name with italic scientific suffix everywhere"
```

---

## Self-Review

- **Spec coverage:** B.1 display rule ✓ Task 4; B.2 single helper (`primaryCommonName` API-side, `displayName` web-side) ✓ Tasks 1 & 3; B.3 API exposes names incl. moving ✓ Tasks 1–2; B.5 web rendering across list/detail/today/dropdown/blog/moving ✓ Task 4.
- **Documented deviation:** today/care payloads not enriched (web cross-references listPlants); rationale stated above.
- **Type consistency:** `speciesCommonName`/`speciesScientificName` field names identical across API responses, web types, and helpers; species list uses `commonName`.
