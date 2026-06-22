# Frontend Redesign — Phase 6: Remaining Pages Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the remaining pages — Places (incl. real edit), Cities, Moving, Blog list, Article, Login — onto the new components, preserving real `useApi` behavior.

**Architecture:** Re-skin each page; data/logic unchanged. Place edit moves to the new `Modal`. The login keeps the real auth + `?redirect=`.

**Tech Stack:** Nuxt 3 pages, Vue 3, `composables/useApi.ts`, `marked`, nuxt-auth-utils.

**Reference:** spec §"Page-by-page port mapping"; current pages `pages/places/index.vue`, `pages/cities/index.vue`, `pages/moving.vue`, `pages/blog/index.vue`, `pages/blog/[id].vue`, `pages/login.vue` (preserve real logic); prototype `.design-import/app/screens-more.jsx`; existing `components/CitySearch.vue` (re-skin, keep the real geocoder via `searchCities`). Commands from `repos/my-plants-web/`. Verify each task with `npm run typecheck && npm run build`.

**Method for every page port (critical):** "re-skin" = replace the `<template>` only; preserve every existing `<script setup>` handler, `computed`, and `useApi` call **verbatim** unless a step says otherwise. Real `useApi` names to use exactly: `listPlaces`, `createPlace`, `updatePlace`, `listCities`, `createCity`, `makePrimaryCity`, `searchCities`, `simulateMove(latitude, longitude)`, `scheduleMove(sel, moveOn)`, `listSpecies`, `getSpeciesBrief`.

---

### Task 1: Places (`pages/places/index.vue`) + edit modal

**Files:** modify `pages/places/index.vue`; Create `components/PlaceEditModal.vue`

- [ ] Keep `listPlaces`/`createPlace`/`updatePlace`. Re-skin: `ScreenHeader` "Places"; list = `CardGrid` of place `Card`s (`IconTile` home/sun by indoor, name, indoor·light, humidity `Badge`); add-place form (`SelectField` city, `Input` name, `SelectField` light, `Switch` indoor revealing `Alert` + climate `Switch` + humidity `SelectField` + temp min/max `Input`s), `Button` "Add place". Move the existing edit (name + climate-controlled) into `PlaceEditModal.vue` on `ui/Modal`, with an Edit button per place card.
- [ ] **Preserve the real form coercion verbatim (per Codex — superficial re-skin would 400):** keep the existing `toNullableNumber` bridge + `indoorTempMinC`/`indoorTempMaxC` computeds, the humidity `''` → omitted mapping, and the outdoor-vs-indoor `CreatePlace` payload split. The new `Input type="number"` must feed the same `number | null` bridge; never send `''` for `indoorTempMinC/MaxC` or `humidityCharacter`. Verify build.

### Task 2: Cities (`pages/cities/index.vue`)

- [ ] Keep `listCities`/`createCity`/`makePrimaryCity` + the real `CitySearch` (geocoder). Re-skin: `ScreenHeader` "Cities"; `CardGrid` of city `Card`s (`IconTile` map-pin, name, Primary `Badge` dot, timezone, "Make primary" `Button` ghost when not primary); add-city form (`CitySearch` re-skinned, selection preview, primary `Switch`, `Button` "Add city"). Verify build.

### Task 3: CitySearch re-skin

**Files:** modify `components/CitySearch.vue`

- [ ] Keep the real debounced `searchCities` call + selection emit. Replace Nuxt UI markup with `Input` (icon magnifying-glass) + the `.mp-search-pop`/`.mp-search-opt` popover from chrome.css + `AppIcon map-pin`. Verify build.

### Task 4: Moving (`pages/moving.vue`)

- [ ] Keep the **real** behavior: target-city search (`CitySearch`) → `useApi().simulateMove(sel.latitude, sel.longitude)` (current-city-scoped, real `PlantViability[]`) → results per plant → `useApi().scheduleMove(sel, moveOn)` on confirm. Use those exact method names/signatures. Discard the prototype's mock `MOVE_SIM`. Re-skin: `ScreenHeader` (eyebrow "What-if", title "Moving"), `Alert` green on scheduled, results `CardGrid` of `Card`s with `PlantName` + `ViabilityBadge`, "Move on" `Input type=date` + `Button` "Schedule move". Verify build.

### Task 5: Blog list (`pages/blog/index.vue`)

- [ ] Keep `listSpecies()`. Re-skin: `ScreenHeader` (eyebrow "Care guides", title "Blog"), `CardGrid` of `Card`s (`IconTile` book-open, common name, italic scientific). **No difficulty badge** (not in `SpeciesSummary`). Verify build.

### Task 6: Article (`pages/blog/[id].vue`)

- [ ] Keep `getSpeciesBrief(slug)` + `marked` render of `briefEs`. Re-skin: `.mp-backlink` "All articles", a single static `Badge` green dot "Care guide", `Prose` with the rendered HTML, capped ~680px. Verify build.

### Task 7: Login (`pages/login.vue`)

- [ ] Keep the **real** auth (POST `/api/auth/login`, `?redirect=` handling) and `definePageMeta({ layout: 'auth' })`. Re-skin: centered `.mp-login` with 🌱, "Welcome back", `FormGroup`+`Input` username/password, `Button block` "Sign in", error display. Verify build.

- [ ] **Verify:** full `npm run typecheck && npm run build` green.
- [ ] **Commit:** `git add -A && git commit -m "feat(web): port Places(+edit), Cities, Moving, Blog, Article, Login"` (new `PlaceEditModal.vue` — use `git add -A`, not `-am`).
