# Edit Phase 5 — Web editing UI (modals) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add edit modals — a plant's nickname + place (with a viability preview before confirming) on `/plants/[id]`, and a place's name + climate-controlled on `/places`. Browser talks only to the `/api` BFF proxy.

**Architecture:** Inline `UModal`s on the existing pages (matches the inline-form style already there; avoids a two-way-bound child component). `useApi` gains `updatePlant`, `previewPlantViability`, `updatePlace`. `Plant`/`Place` types gain `ownerId` (already returned by the API) so the plant's place selector filters to the plant's owner. The web gate is `npm run typecheck` + `npm run build` (no component test runner); functional behavior is verified by the Phase 6 E2E.

**Tech Stack:** Nuxt 3, Vue 3, Nuxt UI.

**Repo:** `repos/my-plants-web`. Branch: `feature/edit-modules`.

---

### Task 1: Types + `useApi` methods

**Files:** Modify `types/api.ts`, `composables/useApi.ts`

- [ ] **Step 1: Types** — in `types/api.ts`:
  - Add `ownerId: string;` to `interface Place` and to `interface Plant`.
  - Add:
    ```ts
    export interface Viability { level: ViabilityLevel; reasons: string[] }
    export interface UpdatePlant { nickname?: string; placeId?: string }
    export interface UpdatePlace { name?: string; climateControlled?: boolean }
    ```

- [ ] **Step 2: `useApi`** — import the new types and add three methods (alongside the existing plant/place ones):

```ts
updatePlant: (id: string, body: UpdatePlant) => api<Plant>(`/plants/${id}`, { method: 'PATCH', body }),
previewPlantViability: (id: string, placeId: string) =>
  api<Viability>(`/plants/${id}/viability-preview?placeId=${encodeURIComponent(placeId)}`),
updatePlace: (id: string, body: UpdatePlace) => api<Place>(`/places/${id}`, { method: 'PATCH', body }),
```

(Add `Viability, UpdatePlant, UpdatePlace` to the type import at the top of `useApi.ts`.)

- [ ] **Step 3: Typecheck** — `npm run typecheck` → clean.

- [ ] **Step 4: Commit** — `git add types/api.ts composables/useApi.ts && git commit -m "feat(web): api client for plant/place edit + viability preview"`

---

### Task 2: Plant edit modal (`/plants/[id]`)

**Files:** Modify `pages/plants/[id].vue`

- [ ] **Step 1: Script** — capture the plant refresh and add edit state:
  - Change `const { data: plant } = await useAsyncData(...)` to `const { data: plant, refresh: refreshPlant } = await useAsyncData(...)`.
  - Add (after the `care` line):
    ```ts
    import type { Viability } from '../../types/api.js';

    const { data: places } = await useAsyncData('places-for-edit', () => api.listPlaces());

    const editing = ref(false);
    const editNickname = ref('');
    const editPlaceId = ref('');
    const preview = ref<Viability | null>(null);
    const savingEdit = ref(false);

    const placeOptions = computed(() =>
      (places.value ?? [])
        .filter((p) => plant.value && p.ownerId === plant.value.ownerId)
        .map((p) => ({ label: `${p.name} (${p.indoor ? 'Indoor' : 'Outdoor'})`, value: p.id })),
    );

    function openEdit() {
      if (!plant.value) return;
      editNickname.value = plant.value.nickname ?? '';
      editPlaceId.value = plant.value.placeId;
      preview.value = null;
      editing.value = true;
    }

    watch(editPlaceId, async (pid) => {
      preview.value =
        plant.value && pid && pid !== plant.value.placeId
          ? await api.previewPlantViability(plant.value.id, pid)
          : null;
    });

    async function saveEdit() {
      if (!plant.value) return;
      savingEdit.value = true;
      try {
        await api.updatePlant(plant.value.id, { nickname: editNickname.value, placeId: editPlaceId.value });
        await Promise.all([refreshPlant(), refresh()]); // title/place AND care
        editing.value = false;
      } finally { savingEdit.value = false; }
    }
    ```

- [ ] **Step 2: Template** — add an Edit button next to the title and the modal. Put the button right after the `<h2>…</h2>` title block:
  ```vue
  <UButton class="mt-2" size="xs" color="gray" variant="soft" icon="i-heroicons-pencil-square" @click="openEdit">Edit</UButton>
  ```
  And add the modal anywhere inside the root `<div v-if="plant">`:
  ```vue
  <UModal v-model="editing">
    <UCard>
      <template #header><h3 class="font-semibold">Edit plant</h3></template>
      <div class="grid gap-3">
        <UFormGroup label="Nickname"><UInput v-model="editNickname" /></UFormGroup>
        <UFormGroup label="Place"><USelect v-model="editPlaceId" :options="placeOptions" /></UFormGroup>
        <div v-if="preview">
          <p class="text-xs text-gray-500 mb-1">Projected viability in the new place:</p>
          <ViabilityBadge :level="preview.level" :reasons="preview.reasons" />
        </div>
      </div>
      <template #footer>
        <div class="flex justify-end gap-2">
          <UButton color="gray" variant="ghost" @click="editing = false">Cancel</UButton>
          <UButton color="green" :loading="savingEdit" @click="saveEdit">Save</UButton>
        </div>
      </template>
    </UCard>
  </UModal>
  ```

- [ ] **Step 3: Typecheck** — `npm run typecheck` → clean.

- [ ] **Step 4: Commit** — `git add pages/plants/[id].vue && git commit -m "feat(web): edit a plant nickname/place with viability preview"`

---

### Task 3: Place edit modal (`/places`)

**Files:** Modify `pages/places/index.vue`

- [ ] **Step 1: Script** — add edit state (after the `places`/`cities` data lines):
  ```ts
  const editing = ref(false);
  const editId = ref('');
  const editName = ref('');
  const editClimate = ref(false);
  const savingEdit = ref(false);

  function openEdit(p: { id: string; name: string; climateControlled: boolean }) {
    editId.value = p.id;
    editName.value = p.name;
    editClimate.value = p.climateControlled;
    editing.value = true;
  }

  async function saveEdit() {
    savingEdit.value = true;
    try {
      await api.updatePlace(editId.value, { name: editName.value, climateControlled: editClimate.value });
      editing.value = false;
      await refresh();
    } finally { savingEdit.value = false; }
  }
  ```

- [ ] **Step 2: Template** — add an Edit button to each place card and the modal. Update the place card loop:
  ```vue
  <UCard v-for="p in places" :key="p.id">
    <div class="flex items-center justify-between gap-2">
      <div>
        <span class="font-medium">{{ p.name }}</span>
        <span class="text-xs text-gray-500"> · {{ p.indoor ? 'Indoor' : 'Outdoor' }} · {{ p.lightType }}</span>
      </div>
      <UButton size="xs" color="gray" variant="soft" icon="i-heroicons-pencil-square" @click="openEdit(p)">Edit</UButton>
    </div>
  </UCard>
  ```
  Add the modal (e.g. right before the closing root `</div>`):
  ```vue
  <UModal v-model="editing">
    <UCard>
      <template #header><h3 class="font-semibold">Edit place</h3></template>
      <div class="grid gap-3">
        <UFormGroup label="Name"><UInput v-model="editName" /></UFormGroup>
        <UFormGroup label="Climate controlled"><UToggle v-model="editClimate" /></UFormGroup>
      </div>
      <template #footer>
        <div class="flex justify-end gap-2">
          <UButton color="gray" variant="ghost" @click="editing = false">Cancel</UButton>
          <UButton color="green" :loading="savingEdit" @click="saveEdit">Save</UButton>
        </div>
      </template>
    </UCard>
  </UModal>
  ```

- [ ] **Step 3: Typecheck + build** — `npm run typecheck && NUXT_IGNORE_LOCK=1 npm run build` → both clean (build only if no dev server holds the lock; otherwise the `NUXT_IGNORE_LOCK=1` flag bypasses the check).

- [ ] **Step 4: Commit** — `git add pages/places/index.vue && git commit -m "feat(web): edit a place name/climate-controlled"`
