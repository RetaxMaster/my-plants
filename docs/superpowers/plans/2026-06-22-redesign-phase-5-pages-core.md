# Frontend Redesign — Phase 5: Core Pages Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the core pages — Today, Plants list, Plant detail (incl. the real edit + viability preview + back-date feedback), Add plant — onto the new components, keeping the real `useApi` data flow and all real behavior.

**Architecture:** Replace each page's Nuxt UI markup with `components/ui/*`. Data, composables, and API calls are unchanged. The plant edit modal moves to the new `Modal`. Build stays green at each page.

**Tech Stack:** Nuxt 3 pages, Vue 3, `composables/useApi.ts`, `marked` (n/a here).

**Reference:** spec §"Page-by-page port mapping"; current pages `pages/index.vue`, `pages/plants/index.vue`, `pages/plants/[id].vue`, `pages/plants/new.vue` (preserve their real logic); prototype screens in `.design-import/app/screens-core.jsx`. Commands from `repos/my-plants-web/`. Verify each task with `npm run typecheck && npm run build`.

**Method for every page port (critical — avoids logic regressions):** "re-skin" means **replace the `<template>` markup only**. Preserve every existing `<script setup>` handler, `computed`, `useAsyncData`, and `useApi` call **verbatim** unless a step says otherwise. The `TaskRow` from Phase 3 emits `{ task, occurredOn? }` / `{ task }`, so wire it as `@done="e => markDone(plantId, e.task, e.occurredOn)"` and `@postpone="e => postpone(plantId, e.task)"`, keeping the real `sendFeedback(plantId, { task, type, occurredOn })` body (Today passes `occurredOn: todayYmd()`; detail passes the optional back-date).

---

### Task 1: Today (`pages/index.vue`)

- [ ] Keep the real data: today's due tasks (`useApi().todaysTasks()` joined to plants, as the current page does). Re-skin with `ScreenHeader` (eyebrow "Today", title "Today's care", subtitle date + due count), `CardGrid`, `Card` per plant with `PlantAvatar` + `PlantName` + place + `TaskRow` (simple mode) wired to the real Done/Postpone feedback (`sendFeedback`). Empty state "Nothing due today. 🌿". Verify build.

### Task 2: Plants list (`pages/plants/index.vue`)

- [ ] Keep `useApi().listPlants()`. **Add one** `useApi().todaysTasks()` call; build a per-plant due count map and pass `:dueCount` to `PlantStatusBadge`. Re-skin: `ScreenHeader` ("Your plants", count, action = `Button` "Add plant" → `/plants/new`), `CardGrid`, `Card` per plant (`PlantAvatar`, `PlantName`, place, `PlantStatusBadge`, chevron). Verify build.

### Task 3: Plant detail (`pages/plants/[id].vue`) — identity + care

- [ ] Keep all real data (`getPlant`, `getPlantCare`) and the existing edit/preview logic. Re-skin: `ScreenHeader` (back "All plants", title, scientific subtitle); identity `Card` (`PlantAvatar`, `PlantName` size 18, acquired+place, `ViabilityBadge`, `Button` soft cafe "Read the care guide" → `/blog/<slug>`); care block with `Alert` for caution/poor, `SectionTitle` "Care", `Card` of `TaskRow` **`withDoneDate`** wired to the real `sendFeedback` (preserve the `occurredOn` back-date + Postpone). Two-column on desktop via `useIsDesktop`. Verify build.

### Task 4: Plant detail — edit modal on the new Modal

**Files:** Create `components/PlantEditModal.vue`; modify `pages/plants/[id].vue`

- [ ] Move the existing edit UI (nickname `Input`, place `SelectField` filtered to the plant's owner, live viability preview via `previewPlantViability` with the existing out-of-order guard) into `PlantEditModal.vue` built on `ui/Modal`. Keep the real `updatePlant` + refresh of both plant & care datasets. Add the "Edit" `Button` on the detail page to open it. Verify build.

### Task 5: Add plant (`pages/plants/new.vue`)

- [ ] Keep the real `createPlant` submit + species/place option loading. Re-skin: `ScreenHeader` (back "Plants", title "Add a plant"), `.mp-form` with `FormGroup` + `SelectField` (species options `common (scientific)`), `SelectField` (place), `Input` (nickname, hint), `Input type=date` (acquired), `Button block` disabled until valid. Verify build.

- [ ] **Verify:** full `npm run typecheck && npm run build` green.
- [ ] **Commit:** `git add -A && git commit -m "feat(web): port Today, Plants, Plant detail (+edit modal), Add plant"` (new `PlantEditModal.vue` — use `git add -A`, not `-am`).
