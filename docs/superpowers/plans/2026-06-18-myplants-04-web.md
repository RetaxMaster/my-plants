# MyPlants — Phase 4: `my-plants-web` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Nuxt 3 + Vue 3 frontend that turns the API's care plan into the owner's daily experience: today's tasks with one-tap done/postpone, plant/place/city management, the viability semaphore, and the moving simulator.

**Architecture:** A Nuxt 3 app at `repos/my-plants-web` using `<script setup>` + TypeScript and Nuxt UI components. All server access goes through one typed API composable that points at the `my-plants-api` base URL from runtime config. Pure presentation helpers (labels, grouping, formatting) are unit-tested; pages are verified by build/typecheck and live QA.

**Tech Stack:** Nuxt 3, Vue 3, `@nuxt/ui`, TypeScript, Vitest (pure utils). Talks to `my-plants-api` over REST.

**Depends on:** Phase 3 (`my-plants-api`) running locally and reachable (default `http://localhost:8000`).

---

## API surface consumed (from Phase 3)

`GET /species`, `GET /species/:slug`; `GET/POST /cities`, `POST /cities/:id/make-primary`;
`GET/POST /places`; `GET/POST /plants`, `GET /plants/:id`; `GET /care-plan/today`,
`POST /care-plan/recompute`; `POST /plants/:id/feedback`; `POST /moving/simulate`,
`POST /moving/schedule`. Tasks: `WATER | FERTILIZE | REPOT | ROTATE | CLEAN_LEAVES`.

---

## File Structure (created across the tasks)

```
repos/my-plants-web/
  package.json  nuxt.config.ts  tsconfig.json  app.config.ts  vitest.config.ts  .gitignore  .env.example
  app.vue
  types/api.ts                       # response/request types mirroring the API contract
  utils/tasks.ts  utils/tasks.test.ts
  composables/useApi.ts              # typed fetch wrapper (runtime apiBase)
  components/AppNav.vue  components/TaskCard.vue  components/ViabilityBadge.vue
  pages/index.vue                    # Today
  pages/plants/index.vue  pages/plants/new.vue  pages/plants/[id].vue
  pages/places/index.vue
  pages/cities/index.vue
  pages/moving.vue
```

Pure helpers in `utils/` carry the unit tests; everything else is verified by `npm run build` (which typechecks) and the live-QA pass.

---

## Task 1: Scaffold the Nuxt submodule

**Files:** `package.json`, `nuxt.config.ts`, `tsconfig.json`, `app.config.ts`, `vitest.config.ts`, `.gitignore`, `.env.example`

- [ ] **Step 1: Create the GitHub repo and register the submodule**

From the **workspace root**:

```bash
gh repo create RetaxMaster/my-plants-web --public --description "MyPlants frontend (Nuxt 3 + Vue + Nuxt UI)."
git submodule add git@github.com:RetaxMaster/my-plants-web.git repos/my-plants-web
mkdir -p repos/my-plants-web
```

All subsequent steps run **inside** `repos/my-plants-web`.

- [ ] **Step 2: Create `package.json`**

Create `repos/my-plants-web/package.json`:

```json
{
  "name": "@retaxmaster/my-plants-web",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "nuxt dev",
    "build": "nuxt build",
    "generate": "nuxt generate",
    "preview": "nuxt preview",
    "postinstall": "nuxt prepare",
    "typecheck": "nuxt typecheck",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@nuxt/ui": "^2.18.7",
    "nuxt": "^3.13.2",
    "vue": "^3.5.12",
    "vue-router": "^4.4.5"
  },
  "devDependencies": {
    "typescript": "^5.5.4",
    "vue-tsc": "^2.1.6",
    "vitest": "^2.0.5"
  }
}
```

- [ ] **Step 3: Create the Nuxt config**

Create `repos/my-plants-web/nuxt.config.ts`:

```ts
export default defineNuxtConfig({
  modules: ['@nuxt/ui'],
  typescript: { strict: true, typeCheck: false },
  runtimeConfig: {
    public: {
      apiBase: process.env.NUXT_PUBLIC_API_BASE ?? 'http://localhost:8000',
    },
  },
  devServer: { port: 8001 },
  compatibilityDate: '2026-06-18',
});
```

- [ ] **Step 4: Create `tsconfig.json`, `app.config.ts`, `.gitignore`, `.env.example`, `vitest.config.ts`**

Create `repos/my-plants-web/tsconfig.json`:

```json
{ "extends": "./.nuxt/tsconfig.json" }
```

Create `repos/my-plants-web/app.config.ts`:

```ts
export default defineAppConfig({
  ui: { primary: 'green', gray: 'stone' },
});
```

Create `repos/my-plants-web/.gitignore`:

```gitignore
node_modules/
.nuxt/
.output/
dist/
.env
```

Create `repos/my-plants-web/.env.example`:

```dotenv
NUXT_PUBLIC_API_BASE=http://localhost:8000
```

Create `repos/my-plants-web/vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: { include: ['utils/**/*.test.ts'], environment: 'node' },
});
```

- [ ] **Step 5: Install + commit the submodule files**

From the **workspace root**:

```bash
npm --prefix repos/my-plants-web install
git -C repos/my-plants-web add -A
git -C repos/my-plants-web commit -m "chore: scaffold my-plants-web"
```

Expected: Nuxt prepares (`postinstall`); `.nuxt/` is generated (git-ignored).

---

## Task 2: Pure task helpers (TDD)

**Files:** `utils/tasks.ts`, `utils/tasks.test.ts`

- [ ] **Step 1: Write the failing test**

Create `repos/my-plants-web/utils/tasks.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { TASK_LABELS, dueLabel, groupByPlant, type DueTask } from './tasks.js';

const today = new Date('2026-06-18');

describe('task presentation helpers', () => {
  it('maps task codes to human labels', () => {
    expect(TASK_LABELS.WATER).toBe('Water');
    expect(TASK_LABELS.CLEAN_LEAVES).toBe('Clean leaves');
  });

  it('labels due dates relative to today', () => {
    expect(dueLabel(new Date('2026-06-18'), today)).toBe('Today');
    expect(dueLabel(new Date('2026-06-17'), today)).toBe('Overdue');
    expect(dueLabel(new Date('2026-06-19'), today)).toBe('Tomorrow');
  });

  it('groups due tasks by plant preserving order', () => {
    const tasks: DueTask[] = [
      { plantId: 'a', task: 'WATER', nextDueOn: '2026-06-18' },
      { plantId: 'b', task: 'WATER', nextDueOn: '2026-06-18' },
      { plantId: 'a', task: 'ROTATE', nextDueOn: '2026-06-18' },
    ];
    const grouped = groupByPlant(tasks);
    expect(grouped.get('a')?.map((t) => t.task)).toEqual(['WATER', 'ROTATE']);
    expect(grouped.get('b')?.length).toBe(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- tasks`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Create `repos/my-plants-web/utils/tasks.ts`:

```ts
export type TaskCode = 'WATER' | 'FERTILIZE' | 'REPOT' | 'ROTATE' | 'CLEAN_LEAVES';

export interface DueTask {
  plantId: string;
  task: TaskCode;
  nextDueOn: string; // ISO date
}

export const TASK_LABELS: Record<TaskCode, string> = {
  WATER: 'Water',
  FERTILIZE: 'Fertilize',
  REPOT: 'Repot',
  ROTATE: 'Rotate',
  CLEAN_LEAVES: 'Clean leaves',
};

const MS_DAY = 86_400_000;

function dayDiff(due: Date, today: Date): number {
  const a = Date.UTC(due.getUTCFullYear(), due.getUTCMonth(), due.getUTCDate());
  const b = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
  return Math.round((a - b) / MS_DAY);
}

export function dueLabel(due: Date, today: Date = new Date()): string {
  const diff = dayDiff(due, today);
  if (diff < 0) return 'Overdue';
  if (diff === 0) return 'Today';
  if (diff === 1) return 'Tomorrow';
  return `In ${diff} days`;
}

export function groupByPlant(tasks: DueTask[]): Map<string, DueTask[]> {
  const grouped = new Map<string, DueTask[]>();
  for (const t of tasks) {
    const list = grouped.get(t.plantId) ?? [];
    list.push(t);
    grouped.set(t.plantId, list);
  }
  return grouped;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- tasks`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C repos/my-plants-web add utils/tasks.ts utils/tasks.test.ts
git -C repos/my-plants-web commit -m "feat: add pure task presentation helpers"
```

---

## Task 3: API types + typed client composable

**Files:** `types/api.ts`, `composables/useApi.ts`

- [ ] **Step 1: Define the API contract types**

Create `repos/my-plants-web/types/api.ts`:

```ts
import type { TaskCode } from '../utils/tasks.js';

export type ViabilityLevel = 'good' | 'caution' | 'poor';

export interface SpeciesSummary { slug: string; scientificName: string }

export interface City {
  id: string; name: string; latitude: number; longitude: number; timezone: string; isPrimary: boolean;
}
export interface CreateCity {
  name: string; latitude: number; longitude: number; timezone: string; isPrimary?: boolean;
}

export type LightType = 'DIRECT' | 'BRIGHT_INDIRECT' | 'MEDIUM' | 'LOW';
export type HumidityCharacter = 'DRY' | 'NORMAL' | 'HUMID';

export interface Place {
  id: string; cityId: string; name: string; indoor: boolean; lightType: LightType;
  climateControlled: boolean; humidityCharacter: HumidityCharacter;
  indoorTempMinC: number | null; indoorTempMaxC: number | null;
}
export interface CreatePlace {
  cityId: string; name: string; indoor: boolean; lightType: LightType;
  climateControlled?: boolean; humidityCharacter?: HumidityCharacter;
  indoorTempMinC?: number | null; indoorTempMaxC?: number | null;
}

export interface Plant {
  id: string; placeId: string; speciesSlug: string; nickname: string | null; acquiredOn: string;
}
export interface CreatePlant {
  placeId: string; speciesSlug: string; nickname?: string; acquiredOn: string;
  lastDone?: { task: TaskCode; doneOn: string }[];
}

export interface DueTaskResponse { plantId: string; task: TaskCode; nextDueOn: string }

export type FeedbackType = 'DONE' | 'POSTPONED' | 'SYMPTOM';
export interface Feedback {
  task: TaskCode; type: FeedbackType; occurredOn: string;
  postponeToOn?: string; payload?: Record<string, unknown>;
}

export interface PlantViability { plantId: string; nickname: string | null; level: ViabilityLevel; reasons: string[] }
```

- [ ] **Step 2: Implement the typed API composable**

Create `repos/my-plants-web/composables/useApi.ts`:

```ts
import type {
  City, CreateCity, CreatePlace, CreatePlant, DueTaskResponse, Feedback, Place, Plant,
  PlantViability, SpeciesSummary,
} from '../types/api.js';

export function useApi() {
  const base = useRuntimeConfig().public.apiBase;
  const api = <T>(path: string, opts?: Parameters<typeof $fetch>[1]) =>
    $fetch<T>(`${base}${path}`, opts);

  return {
    listSpecies: () => api<SpeciesSummary[]>('/species'),

    listCities: () => api<City[]>('/cities'),
    createCity: (body: CreateCity) => api<City>('/cities', { method: 'POST', body }),
    makePrimaryCity: (id: string) => api<City>(`/cities/${id}/make-primary`, { method: 'POST' }),

    listPlaces: () => api<Place[]>('/places'),
    createPlace: (body: CreatePlace) => api<Place>('/places', { method: 'POST', body }),

    listPlants: () => api<Plant[]>('/plants'),
    getPlant: (id: string) => api<Plant>(`/plants/${id}`),
    createPlant: (body: CreatePlant) => api<Plant>('/plants', { method: 'POST', body }),

    todaysTasks: () => api<DueTaskResponse[]>('/care-plan/today'),
    recompute: () => api<{ ok: true }>('/care-plan/recompute', { method: 'POST' }),

    sendFeedback: (plantId: string, body: Feedback) =>
      api<{ ok: true }>(`/plants/${plantId}/feedback`, { method: 'POST', body }),

    simulateMove: (targetCityId: string) =>
      api<PlantViability[]>('/moving/simulate', { method: 'POST', body: { targetCityId } }),
    scheduleMove: (targetCityId: string, moveOn: string) =>
      api<{ id: string }>('/moving/schedule', { method: 'POST', body: { targetCityId, moveOn } }),
  };
}
```

- [ ] **Step 3: Commit**

```bash
git -C repos/my-plants-web add types/api.ts composables/useApi.ts
git -C repos/my-plants-web commit -m "feat: add API contract types and typed client composable"
```

---

## Task 4: Shared components

**Files:** `components/ViabilityBadge.vue`, `components/TaskCard.vue`, `components/AppNav.vue`

- [ ] **Step 1: Viability badge**

Create `repos/my-plants-web/components/ViabilityBadge.vue`:

```vue
<script setup lang="ts">
import type { ViabilityLevel } from '../types/api.js';

const props = defineProps<{ level: ViabilityLevel; reasons?: string[] }>();

const color = computed(() => ({ good: 'green', caution: 'amber', poor: 'red' }[props.level]));
const label = computed(() => ({ good: 'Good fit', caution: 'Caution', poor: 'Poor fit' }[props.level]));
</script>

<template>
  <div class="flex flex-col gap-1">
    <UBadge :color="color" variant="subtle">{{ label }}</UBadge>
    <ul v-if="reasons?.length" class="text-xs text-gray-500 list-disc pl-4">
      <li v-for="reason in reasons" :key="reason">{{ reason }}</li>
    </ul>
  </div>
</template>
```

- [ ] **Step 2: Task card with done/postpone actions**

Create `repos/my-plants-web/components/TaskCard.vue`:

```vue
<script setup lang="ts">
import { TASK_LABELS, dueLabel, type TaskCode } from '../utils/tasks.js';

const props = defineProps<{ plantId: string; task: TaskCode; nextDueOn: string }>();
const emit = defineEmits<{ done: [TaskCode]; postpone: [TaskCode] }>();

const due = computed(() => dueLabel(new Date(props.nextDueOn)));
const dueColor = computed(() => (due.value === 'Overdue' ? 'red' : due.value === 'Today' ? 'amber' : 'gray'));
</script>

<template>
  <div class="flex items-center justify-between gap-2 py-2">
    <div class="flex items-center gap-2">
      <span class="font-medium">{{ TASK_LABELS[task] }}</span>
      <UBadge :color="dueColor" variant="subtle" size="xs">{{ due }}</UBadge>
    </div>
    <div class="flex gap-2">
      <UButton size="xs" color="green" icon="i-heroicons-check" @click="emit('done', task)">Done</UButton>
      <UButton size="xs" color="gray" variant="ghost" icon="i-heroicons-clock" @click="emit('postpone', task)">Postpone</UButton>
    </div>
  </div>
</template>
```

- [ ] **Step 3: Navigation**

Create `repos/my-plants-web/components/AppNav.vue`:

```vue
<script setup lang="ts">
const links = [
  { label: 'Today', to: '/', icon: 'i-heroicons-sun' },
  { label: 'Plants', to: '/plants', icon: 'i-heroicons-sparkles' },
  { label: 'Places', to: '/places', icon: 'i-heroicons-home' },
  { label: 'Cities', to: '/cities', icon: 'i-heroicons-map-pin' },
  { label: 'Moving', to: '/moving', icon: 'i-heroicons-truck' },
];
</script>

<template>
  <nav class="flex gap-1 border-b border-gray-200 px-4 py-2">
    <UButton v-for="l in links" :key="l.to" :to="l.to" :icon="l.icon" variant="ghost" color="gray">{{ l.label }}</UButton>
  </nav>
</template>
```

- [ ] **Step 4: Commit**

```bash
git -C repos/my-plants-web add components
git -C repos/my-plants-web commit -m "feat: add viability badge, task card, and nav components"
```

---

## Task 5: App shell + Today dashboard

**Files:** `app.vue`, `pages/index.vue`

- [ ] **Step 1: App shell**

Create `repos/my-plants-web/app.vue`:

```vue
<template>
  <UContainer class="py-6 max-w-3xl">
    <header class="mb-4">
      <h1 class="text-2xl font-bold">🌱 MyPlants</h1>
    </header>
    <AppNav class="mb-6" />
    <NuxtPage />
  </UContainer>
</template>
```

- [ ] **Step 2: Today dashboard (groups due tasks per plant; done/postpone via feedback)**

Create `repos/my-plants-web/pages/index.vue`:

```vue
<script setup lang="ts">
import { groupByPlant, type DueTask } from '../utils/tasks.js';
import type { Plant } from '../types/api.js';

const api = useApi();
const { data: tasks, refresh } = await useAsyncData('today', () => api.todaysTasks());
const { data: plants } = await useAsyncData('plants', () => api.listPlants());

const plantName = (id: string): string => {
  const p = (plants.value ?? []).find((x: Plant) => x.id === id);
  return p?.nickname ?? p?.speciesSlug ?? id;
};

const grouped = computed(() => groupByPlant((tasks.value ?? []) as DueTask[]));

const today = new Date().toISOString().slice(0, 10);

async function markDone(plantId: string, task: DueTask['task']) {
  await api.sendFeedback(plantId, { task, type: 'DONE', occurredOn: today });
  await refresh();
}

async function postpone(plantId: string, task: DueTask['task']) {
  const tomorrow = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
  await api.sendFeedback(plantId, { task, type: 'POSTPONED', occurredOn: today, postponeToOn: tomorrow });
  await refresh();
}
</script>

<template>
  <div>
    <h2 class="text-lg font-semibold mb-3">Today's care</h2>
    <p v-if="!grouped.size" class="text-gray-500">Nothing due today. 🌿</p>
    <div v-for="[plantId, plantTasks] in grouped" :key="plantId" class="mb-4">
      <UCard>
        <template #header>
          <NuxtLink :to="`/plants/${plantId}`" class="font-medium hover:underline">{{ plantName(plantId) }}</NuxtLink>
        </template>
        <TaskCard
          v-for="t in plantTasks"
          :key="t.task"
          :plant-id="plantId"
          :task="t.task"
          :next-due-on="t.nextDueOn"
          @done="markDone(plantId, $event)"
          @postpone="postpone(plantId, $event)"
        />
      </UCard>
    </div>
  </div>
</template>
```

- [ ] **Step 3: Commit**

```bash
git -C repos/my-plants-web add app.vue pages/index.vue
git -C repos/my-plants-web commit -m "feat: add app shell and today dashboard"
```

---

## Task 6: Plants pages (list, create with viability, detail)

**Files:** `pages/plants/index.vue`, `pages/plants/new.vue`, `pages/plants/[id].vue`

- [ ] **Step 1: Plants list**

Create `repos/my-plants-web/pages/plants/index.vue`:

```vue
<script setup lang="ts">
const api = useApi();
const { data: plants } = await useAsyncData('plants-list', () => api.listPlants());
</script>

<template>
  <div>
    <div class="flex items-center justify-between mb-3">
      <h2 class="text-lg font-semibold">Your plants</h2>
      <UButton to="/plants/new" icon="i-heroicons-plus">Add plant</UButton>
    </div>
    <p v-if="!plants?.length" class="text-gray-500">No plants yet.</p>
    <div class="grid gap-2">
      <UCard v-for="p in plants" :key="p.id">
        <NuxtLink :to="`/plants/${p.id}`" class="font-medium hover:underline">
          {{ p.nickname ?? p.speciesSlug }}
        </NuxtLink>
        <p class="text-xs text-gray-500">{{ p.speciesSlug }}</p>
      </UCard>
    </div>
  </div>
</template>
```

- [ ] **Step 2: Create plant (species + place + acquired date), then recompute**

Create `repos/my-plants-web/pages/plants/new.vue`:

```vue
<script setup lang="ts">
import type { CreatePlant } from '../../types/api.js';

const api = useApi();
const router = useRouter();
const { data: species } = await useAsyncData('species', () => api.listSpecies());
const { data: places } = await useAsyncData('places', () => api.listPlaces());

const form = reactive<CreatePlant>({
  speciesSlug: '',
  placeId: '',
  nickname: '',
  acquiredOn: new Date().toISOString().slice(0, 10),
});
const error = ref('');

const speciesOptions = computed(() => (species.value ?? []).map((s) => ({ label: s.scientificName, value: s.slug })));
const placeOptions = computed(() => (places.value ?? []).map((p) => ({ label: p.name, value: p.id })));

async function submit() {
  error.value = '';
  try {
    const plant = await api.createPlant({ ...form, nickname: form.nickname || undefined });
    await api.recompute();
    await router.push(`/plants/${plant.id}`);
  } catch (e) {
    error.value = (e as Error).message;
  }
}
</script>

<template>
  <div>
    <h2 class="text-lg font-semibold mb-3">Add a plant</h2>
    <UForm :state="form" class="grid gap-3 max-w-md" @submit="submit">
      <UFormGroup label="Species" required>
        <USelect v-model="form.speciesSlug" :options="speciesOptions" placeholder="Pick a species" />
      </UFormGroup>
      <UFormGroup label="Place" required>
        <USelect v-model="form.placeId" :options="placeOptions" placeholder="Pick a place" />
      </UFormGroup>
      <UFormGroup label="Nickname">
        <UInput v-model="form.nickname" placeholder="e.g. Monty" />
      </UFormGroup>
      <UFormGroup label="Acquired on" required>
        <UInput v-model="form.acquiredOn" type="date" />
      </UFormGroup>
      <p v-if="error" class="text-sm text-red-500">{{ error }}</p>
      <UButton type="submit" :disabled="!form.speciesSlug || !form.placeId">Add plant</UButton>
    </UForm>
  </div>
</template>
```

- [ ] **Step 3: Plant detail**

Create `repos/my-plants-web/pages/plants/[id].vue`:

```vue
<script setup lang="ts">
const route = useRoute();
const api = useApi();
const id = route.params.id as string;
const { data: plant } = await useAsyncData(`plant-${id}`, () => api.getPlant(id));
</script>

<template>
  <div v-if="plant">
    <NuxtLink to="/plants" class="text-sm text-gray-500 hover:underline">← All plants</NuxtLink>
    <h2 class="text-xl font-bold mt-2">{{ plant.nickname ?? plant.speciesSlug }}</h2>
    <p class="text-gray-500">{{ plant.speciesSlug }}</p>
    <p class="text-sm text-gray-500 mt-1">Acquired {{ plant.acquiredOn.slice(0, 10) }}</p>
  </div>
  <p v-else class="text-gray-500">Loading…</p>
</template>
```

- [ ] **Step 4: Commit**

```bash
git -C repos/my-plants-web add pages/plants
git -C repos/my-plants-web commit -m "feat: add plants list, create, and detail pages"
```

---

## Task 7: Places, Cities, and Moving pages

**Files:** `pages/places/index.vue`, `pages/cities/index.vue`, `pages/moving.vue`

- [ ] **Step 1: Places (list + create)**

Create `repos/my-plants-web/pages/places/index.vue`:

```vue
<script setup lang="ts">
import type { CreatePlace, LightType } from '../../types/api.js';

const api = useApi();
const { data: places, refresh } = await useAsyncData('places', () => api.listPlaces());
const { data: cities } = await useAsyncData('cities', () => api.listCities());

const lightOptions: { label: string; value: LightType }[] = [
  { label: 'Direct sun', value: 'DIRECT' },
  { label: 'Bright indirect', value: 'BRIGHT_INDIRECT' },
  { label: 'Medium', value: 'MEDIUM' },
  { label: 'Low', value: 'LOW' },
];

const form = reactive<CreatePlace>({ cityId: '', name: '', indoor: true, lightType: 'BRIGHT_INDIRECT' });
const cityOptions = computed(() => (cities.value ?? []).map((c) => ({ label: c.name, value: c.id })));

async function submit() {
  await api.createPlace({ ...form });
  Object.assign(form, { name: '' });
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
      <UFormGroup label="Light"><USelect v-model="form.lightType" :options="lightOptions" /></UFormGroup>
      <UButton type="submit" :disabled="!form.cityId || !form.name">Add place</UButton>
    </UForm>
  </div>
</template>
```

- [ ] **Step 2: Cities (list + create + make primary)**

Create `repos/my-plants-web/pages/cities/index.vue`:

```vue
<script setup lang="ts">
import type { CreateCity } from '../../types/api.js';

const api = useApi();
const { data: cities, refresh } = await useAsyncData('cities', () => api.listCities());

const form = reactive<CreateCity>({ name: '', latitude: 0, longitude: 0, timezone: 'America/Mexico_City', isPrimary: false });

async function submit() {
  await api.createCity({ ...form });
  Object.assign(form, { name: '' });
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
    <UForm :state="form" class="grid gap-3 max-w-md" @submit="submit">
      <UFormGroup label="Name" required><UInput v-model="form.name" /></UFormGroup>
      <UFormGroup label="Latitude" required><UInput v-model.number="form.latitude" type="number" step="0.0001" /></UFormGroup>
      <UFormGroup label="Longitude" required><UInput v-model.number="form.longitude" type="number" step="0.0001" /></UFormGroup>
      <UFormGroup label="Timezone" required><UInput v-model="form.timezone" /></UFormGroup>
      <UFormGroup label="Primary"><UToggle v-model="form.isPrimary" /></UFormGroup>
      <UButton type="submit" :disabled="!form.name">Add city</UButton>
    </UForm>
  </div>
</template>
```

- [ ] **Step 3: Moving simulator**

Create `repos/my-plants-web/pages/moving.vue`:

```vue
<script setup lang="ts">
import type { PlantViability } from '../types/api.js';

const api = useApi();
const { data: cities } = await useAsyncData('cities', () => api.listCities());
const targetCityId = ref('');
const results = ref<PlantViability[] | null>(null);
const cityOptions = computed(() => (cities.value ?? []).map((c) => ({ label: c.name, value: c.id })));

async function simulate() {
  results.value = await api.simulateMove(targetCityId.value);
}
</script>

<template>
  <div>
    <h2 class="text-lg font-semibold mb-3">Moving — what-if</h2>
    <div class="flex gap-2 items-end max-w-md mb-6">
      <UFormGroup label="Target city" class="flex-1">
        <USelect v-model="targetCityId" :options="cityOptions" placeholder="Pick a city" />
      </UFormGroup>
      <UButton :disabled="!targetCityId" @click="simulate">Simulate</UButton>
    </div>
    <div v-if="results" class="grid gap-2">
      <UCard v-for="r in results" :key="r.plantId">
        <div class="flex items-center justify-between">
          <span class="font-medium">{{ r.nickname ?? r.plantId }}</span>
          <ViabilityBadge :level="r.level" :reasons="r.reasons" />
        </div>
      </UCard>
    </div>
  </div>
</template>
```

- [ ] **Step 4: Commit**

```bash
git -C repos/my-plants-web add pages/places pages/cities pages/moving.vue
git -C repos/my-plants-web commit -m "feat: add places, cities, and moving pages"
```

---

## Task 8: Build, typecheck, and live QA

- [ ] **Step 1: Unit tests, typecheck, and build**

Run (inside `repos/my-plants-web`):
```bash
npm test
npm run typecheck
npm run build
```
Expected: util tests green; `nuxt typecheck` reports no type errors; `nuxt build` succeeds.

- [ ] **Step 2: Live QA against the running API**

Start the API (`./run.sh --api` from the workspace root, with MariaDB up + seeded) on port 8000
and the web (`./run.sh --web`) on port 8001. Then **delegate to the `qa-engineer` subagent** (per
the workspace constitution — never self-verify UI) to confirm the real-user flow: create a city →
place → plant, then see the plant's tasks on Today and mark one done. Brief it with (1) what to
test, (2) how (the steps above against `http://localhost:8001`), and (3) the expected result (the
task disappears/refreshes after "Done"). Fix any real defect at the root; never mask it.

- [ ] **Step 3: Commit any fixes**

```bash
git -C repos/my-plants-web add -A
git -C repos/my-plants-web commit -m "fix: address live-QA findings"   # only if there were fixes
```

---

## Task 9: Register the submodule pointer in the workspace root

- [ ] **Step 1: Push the submodule and bump the pointer**

Run (from the **workspace root**):
```bash
git -C repos/my-plants-web push -u origin main
git add .gitmodules repos/my-plants-web
git commit -m "chore: add my-plants-web submodule"
git push origin main
```

---

## Self-Review

**Spec coverage** (against architecture spec → `my-plants-web` + product vision):
- Today's tasks with done/postpone via feedback → Tasks 4–5. ✅
- Plant/place/city management → Tasks 6–7. ✅
- Viability semaphore surfaced (moving simulator; component reusable) → Tasks 4, 7. ✅
- Moving what-if simulator → Task 7. ✅
- Typed single API client pointed at runtime `apiBase`; no business logic in the web (engines live in the API) → Task 3. ✅
- Pure helpers unit-tested; pages verified by build/typecheck + delegated live QA → Tasks 2, 8. ✅
- Submodule + workspace pointer → Tasks 1, 9. ✅

**Placeholder scan:** All pages, components, composable, types, and the pure util are complete code. Live-QA fixes are conditional (only commit if needed). No "TODO"/"TBD".

**Type consistency:** `TaskCode`/`DueTask` from `utils/tasks.ts` are reused by `types/api.ts`, `useApi`, and the components; `useApi` method names (`todaysTasks`, `sendFeedback`, `simulateMove`, …) match every page caller; request/response shapes (`CreatePlant.lastDone`, `Feedback`, `PlantViability`) mirror the Phase 3 DTOs/controllers.
