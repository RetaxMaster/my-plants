# Enrichment v2 — Phase 6: Web misting task + permissive place alert Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the `MIST` cycle in the web UI (care panel + today's view) and make the indoor place fields optional on the create form with an informational alert nudging the owner to provide them.

**Architecture:** The web has a closed `TaskCode` union in `utils/tasks.ts` (re-used by `types/api.ts`); `MIST` must be added there + in the label map, after which the existing generic task rows render it. The place form drops the required indoor fields and shows an alert; the web `Place` type allows `humidityCharacter: null`.

**Tech Stack:** Nuxt 3 / Vue 3, Nuxt UI, TypeScript, Vitest. Gate: `npm run build` + `npm run typecheck` (nuxt build does NOT typecheck).

**Repo:** `repos/my-plants-web`. Depends on Phase 4 (`MIST` exists API-side) and Phase 3 (nullable humidity).

---

### Task 1: Add `MIST` to the web task vocabulary

**Files:**
- Modify: `repos/my-plants-web/utils/tasks.ts`
- Test: `repos/my-plants-web/utils/tasks.test.ts` (create if absent)

- [ ] **Step 1: Write the failing test** — `utils/tasks.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { TASK_LABELS } from './tasks.js';

it('has a label for the MIST task', () => {
  expect(TASK_LABELS.MIST).toBe('Mist leaves');
});
```

- [ ] **Step 2: Run → fail** — `cd repos/my-plants-web && npx vitest run utils/tasks.test.ts` → FAIL.

- [ ] **Step 3: Implement** — in `utils/tasks.ts`, extend the union and the label map:

```ts
export type TaskCode = 'WATER' | 'FERTILIZE' | 'REPOT' | 'ROTATE' | 'CLEAN_LEAVES' | 'MIST';
```

```ts
export const TASK_LABELS: Record<TaskCode, string> = {
  WATER: 'Water',
  FERTILIZE: 'Fertilize',
  REPOT: 'Repot',
  ROTATE: 'Rotate',
  CLEAN_LEAVES: 'Clean leaves',
  MIST: 'Mist leaves',
};
```

- [ ] **Step 4: Run → pass** — `npx vitest run utils/tasks.test.ts` → PASS. (`types/api.ts` imports `TaskCode`, so `DueTaskResponse`, `Feedback`, and `PlantCareTask` accept `MIST` automatically — there is no separate `Task` type to change.)

- [ ] **Step 5: Commit**

```bash
git add utils/tasks.ts utils/tasks.test.ts
git commit -m "feat: add MIST to the web task vocabulary"
```

---

### Task 2: Verify MIST renders in the care panel & today's view

**Files:**
- Verify: `repos/my-plants-web/pages/plants/[id].vue` (iterates `care.tasks` → `TASK_LABELS[t.task]`)
- Verify: `repos/my-plants-web/pages/index.vue` + `components/TaskCard.vue` (iterate grouped tasks → `TASK_LABELS[task]`)

- [ ] **Step 1: Confirm no per-task allow-list blocks MIST.** Both surfaces map over whatever tasks the API returns and look up `TASK_LABELS`. With Task 1 done, a `MIST` due now renders with the "Mist leaves" label and the generic Done/Postpone buttons. No code change expected.

- [ ] **Step 2: Build + typecheck**

Run: `cd repos/my-plants-web && npm run build && npm run typecheck`
Expected: PASS.

- [ ] **Step 3: Commit (only if a change was needed; otherwise skip)**

```bash
git add pages components
git commit -m "chore: confirm MIST task renders in care panel and today view" 2>/dev/null || true
```

---

### Task 3: Web `Place` type allows null humidity; place form makes indoor fields optional + alert

**Files:**
- Modify: `repos/my-plants-web/types/api.ts` (`Place`)
- Modify: `repos/my-plants-web/pages/places/index.vue`

- [ ] **Step 1: Allow null humidity in the type** — in `types/api.ts`:

```ts
export interface Place {
  id: string; cityId: string; name: string; indoor: boolean; lightType: LightType;
  climateControlled: boolean; humidityCharacter: HumidityCharacter | null;
  indoorTempMinC: number | null; indoorTempMaxC: number | null;
}
```

- [ ] **Step 2: Make humidity optional in the form** — in `pages/places/index.vue`, add an explicit "Not specified" option and default the form's `humidityCharacter` to `undefined` (not `'NORMAL'`), so an indoor place can be created without it. Update the humidity options and the form init:

```ts
const humidityOptions: { label: string; value: HumidityCharacter | '' }[] = [
  { label: 'Not specified', value: '' },
  { label: 'Dry', value: 'DRY' },
  { label: 'Normal', value: 'NORMAL' },
  { label: 'Humid', value: 'HUMID' },
];

const form = reactive<CreatePlace>({
  cityId: '', name: '', indoor: true, lightType: 'BRIGHT_INDIRECT',
  climateControlled: false, humidityCharacter: undefined, indoorTempMinC: null, indoorTempMaxC: null,
});
```

Bridge the empty-string select to `undefined` on the payload (so the API stores null). In `submit`, when indoor, drop `humidityCharacter` if it is falsy:

```ts
async function submit() {
  const payload: CreatePlace = form.indoor
    ? {
        cityId: form.cityId, name: form.name, indoor: true, lightType: form.lightType,
        climateControlled: form.climateControlled,
        ...(form.humidityCharacter ? { humidityCharacter: form.humidityCharacter } : {}),
        indoorTempMinC: form.indoorTempMinC, indoorTempMaxC: form.indoorTempMaxC,
      }
    : { cityId: form.cityId, name: form.name, indoor: false, lightType: form.lightType };
  await api.createPlace(payload);
  Object.assign(form, { name: '', climateControlled: false, humidityCharacter: undefined, indoorTempMinC: null, indoorTempMaxC: null });
  await refresh();
}
```

Bind the select with a model that tolerates the empty option (the `USelect` `v-model="form.humidityCharacter"` with the `''` option will set `''`; treat `''` as "not specified" — the `form.humidityCharacter ? ...` guard above already handles `''` and `undefined`).

- [ ] **Step 3: Add the informational alert** — show it when the place is indoor and the temp range and/or humidity are missing. In the `<template v-if="form.indoor">` block, before the fields:

```vue
<UAlert
  v-if="!form.humidityCharacter || form.indoorTempMinC === null || form.indoorTempMaxC === null"
  color="amber"
  variant="subtle"
  title="Optional, but recommended"
  description="Add this room's humidity and temperature range for more accurate care. Without them we estimate from your local outdoor weather."
/>
```

- [ ] **Step 4: Build + typecheck**

Run: `cd repos/my-plants-web && npm run build && npm run typecheck`
Expected: PASS. (If `UAlert` prop names differ in the installed Nuxt UI version, adjust to the available alert component — read an existing usage if present, else use a styled `<div>` with the same copy.)

- [ ] **Step 5: Commit**

```bash
git add types/api.ts pages/places/index.vue
git commit -m "feat: optional indoor place fields + recommend-data alert; nullable humidity in web Place type"
```

---

## Self-Review

- **Spec coverage:** R3.6 MIST in the web vocabulary + rendering ✓ Tasks 1–2; Refinement A.4 optional create-form fields + alert ✓ Task 3; web `Place` nullable humidity ✓ Task 3.
- **Closed-union hazard addressed:** `MIST` added to `TaskCode` (the single union `types/api.ts` re-uses); no separate enum left stale.
- **Web gate:** every task ends on `npm run build && npm run typecheck` (not just nuxt build).
- **Type consistency:** `humidityCharacter: HumidityCharacter | null` matches the API's nullable column; the create payload omits the field when unspecified.
