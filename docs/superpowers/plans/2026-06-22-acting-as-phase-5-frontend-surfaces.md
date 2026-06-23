# Acting As — Phase 5: Frontend Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the admin-only Owners view, the account-menu entry + Stop control, the persistent global "Acting as" banner, and the Moving off-primary warning — all gated so a normal USER never sees the admin surfaces.

**Architecture:** Admin gating reads the **real** session role (`useUserSession().user.role`). The impersonation state is read from `useUserSession().session.actingAs` (a top-level session field from Phase 4, client-visible). Starting/stopping acting-as hard-reloads the app (`reloadNuxtApp({ path: '/' })`) so every owner-scoped page refetches under the new effective owner — no per-composable refresh bugs.

**Tech Stack:** Nuxt 3, Vue 3, the in-house design-system components under `components/ui/`.

**Reference:** spec §5.3, §5.4, §5.5, §6. Verify each task with `npm run typecheck && NUXT_IGNORE_LOCK=1 npm run build`. All commands run from `repos/my-plants-web/`.

---

### Task 1: Admin-only Owners view

**Files:**
- Create: `pages/admin/owners.vue`

- [ ] **Step 1:** Create `pages/admin/owners.vue`. It is gated by the real role (a USER gets a 404 — the surface does not render at all), lists owners, and starts acting-as:

```vue
<script setup lang="ts">
const { user } = useUserSession();

// Admin-only: a non-admin session 404s, so the view never renders for a USER (the global auth
// middleware already requires a session). GET /owners is the hard backend gate (403).
if (user.value?.role !== 'ADMIN') {
  throw createError({ statusCode: 404, statusMessage: 'Page not found' });
}

const api = useApi();
const { data: owners } = await useAsyncData('admin-owners', () => api.listOwners(), { default: () => [] });

async function act(ownerId: string) {
  await api.actAs(ownerId);
  // Hard reload so every owner-scoped page refetches as the target owner.
  reloadNuxtApp({ path: '/' });
}
</script>

<template>
  <div>
    <UiScreenHeader
      eyebrow="Admin"
      title="Switch user"
      subtitle="Act on behalf of another owner. You can stop at any time."
    />

    <UiCard v-if="!owners?.length" padded>
      <UiEmptyState>No owners found.</UiEmptyState>
    </UiCard>

    <UiCardGrid v-else :min="260" :gap="12">
      <UiCard v-for="o in owners" :key="o.ownerId" padded>
        <div class="mp-owner-row">
          <UiIconTile icon="user" tone="cafe" :size="40" />
          <div class="mp-owner-row__info">
            <div class="mp-owner-row__name-line">
              <span class="mp-owner-row__name">{{ o.username }}</span>
              <UiBadge v-if="o.role" color="green" size="xs">{{ o.role }}</UiBadge>
            </div>
          </div>
          <UiBadge v-if="o.username === user?.username" color="green" size="xs">You</UiBadge>
          <UiButton v-else size="xs" variant="ghost" color="neutral" @click="act(o.ownerId)">
            Act as
          </UiButton>
        </div>
      </UiCard>
    </UiCardGrid>
  </div>
</template>

<style scoped>
.mp-owner-row {
  display: flex;
  align-items: center;
  gap: 12px;
}
.mp-owner-row__info {
  flex: 1;
  min-width: 0;
}
.mp-owner-row__name-line {
  display: flex;
  align-items: center;
  gap: 8px;
}
.mp-owner-row__name {
  font: 700 15px var(--font-sans);
  color: var(--text-strong);
}
</style>
```

- [ ] **Step 2 (verify):** `npm run typecheck && NUXT_IGNORE_LOCK=1 npm run build` → PASS.

---

### Task 2: Account menu — admin entry + Stop acting as

**Files:**
- Modify: `components/AccountMenu.vue`

- [ ] **Step 1:** In `components/AccountMenu.vue` `<script setup>`, add the API + role/acting-as reads and a stop handler. Replace the top of the script (the `const { user, clear } = useUserSession();` line and the `api` setup) with:

```ts
import AppIcon from './ui/AppIcon.vue';

const { user, session, clear } = useUserSession();
const api = useApi();

const isAdmin = computed(() => user.value?.role === 'ADMIN');
const actingAs = computed(() => session.value?.actingAs ?? null);

const { data: cities } = await useAsyncData('account-cities', () => api.listCities(), {
  default: () => [],
});
```

(Keep the existing `primaryCity`, `open`, `root`, `toggle`, `onDocumentClick`, lifecycle hooks, and `logout` exactly as they are.)

- [ ] **Step 2:** Add a stop handler next to `logout`:

```ts
async function stopActingAs() {
  open.value = false;
  await api.stopActingAs();
  reloadNuxtApp({ path: '/' });
}
```

- [ ] **Step 3:** In the dropdown template (`<div v-if="open" class="mp-menu">`), add the admin entry and the conditional stop item BEFORE the Sign out button:

```vue
      <NuxtLink v-if="isAdmin" to="/admin/owners" class="mp-menu-item" @click="open = false">
        <AppIcon name="user-group" :size="16" color="currentColor" />
        Switch user
      </NuxtLink>
      <button v-if="actingAs" type="button" class="mp-menu-item" @click="stopActingAs">
        <AppIcon name="arrow-uturn-left" :size="16" color="currentColor" />
        Stop acting as {{ actingAs.label }}
      </button>
```

- [ ] **Step 4 (verify):** `npm run typecheck && NUXT_IGNORE_LOCK=1 npm run build` → PASS.

---

### Task 3: Global "Acting as" banner

**Files:**
- Modify: `layouts/default.vue`

- [ ] **Step 1:** In `layouts/default.vue` `<script setup>`, extend the session destructure and add the acting-as state + stop handler (place after `const { loggedIn } = useUserSession();` → change it to include `session`):

```ts
const { loggedIn, session } = useUserSession();
const api = useApi();
const actingAs = computed(() => session.value?.actingAs ?? null);

async function stopActingAs() {
  await api.stopActingAs();
  reloadNuxtApp({ path: '/' });
}
```

- [ ] **Step 2:** Render a persistent banner directly under the `<header>` (before `<main>`):

```vue
    <div v-if="actingAs" class="mp-actingas" role="status">
      <AppIcon name="user" :size="16" color="currentColor" />
      <span class="mp-actingas__text">Acting as <strong>{{ actingAs.label }}</strong></span>
      <button type="button" class="mp-actingas__stop" @click="stopActingAs">Stop acting as</button>
    </div>
```

- [ ] **Step 3:** Add the banner styles inside the `<style scoped>` block:

```css
.mp-actingas {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 22px;
  background: var(--care-caution-bg);
  border-bottom: 1px solid color-mix(in oklch, var(--care-caution) 35%, transparent);
  color: var(--care-caution-text);
  font: 13px var(--font-sans);
}
.mp-actingas__text strong {
  font-weight: var(--weight-semibold);
}
.mp-actingas__stop {
  margin-left: auto;
  background: none;
  border: 1px solid currentColor;
  border-radius: var(--radius-sm);
  padding: 3px 10px;
  font: 600 12px var(--font-sans);
  color: inherit;
  cursor: pointer;
}
```

- [ ] **Step 4 (verify):** `npm run typecheck && NUXT_IGNORE_LOCK=1 npm run build` → PASS.

- [ ] **Step 5: Commit.**

```bash
git add pages/admin/owners.vue components/AccountMenu.vue layouts/default.vue
git commit -m "feat(web): admin Owners view, account-menu switch/stop, acting-as banner"
```

---

### Task 4: Moving off-primary warning

**Files:**
- Modify: `pages/moving.vue`

- [ ] **Step 1:** In `pages/moving.vue`, inside the results `UiCard` loop, add a per-plant warning after the viability badge block. Replace the `<div class="mp-moving__viability">...</div>` block with:

```vue
            <div class="mp-moving__viability">
              <UiViabilityBadge :level="r.level" :reasons="r.reasons" />
            </div>
            <UiAlert
              v-if="!r.inPrimaryCity"
              color="amber"
              class="mp-moving__warning"
              :description="`This plant is not in your current city — it is in ${r.placeCityName}.`"
            />
```

- [ ] **Step 2:** Add the spacing style inside `<style scoped>`:

```css
.mp-moving__warning {
  margin-top: 10px;
}
```

- [ ] **Step 3 (verify):** `npm run typecheck && NUXT_IGNORE_LOCK=1 npm run build` → PASS.

- [ ] **Step 4: Commit.**

```bash
git add pages/moving.vue
git commit -m "feat(web): Moving warns when a simulated plant is not in the current city"
```
