# Frontend redesign — Claude Design system import

**Status:** approved design (pending Codex review gate)
**Date:** 2026-06-22
**Area:** `repos/my-plants-web`
**Related:** `docs/frontend-design-system.md` (the import/sync procedure this spec executes), Frontend / UI rules in `CLAUDE.md` ≡ `AGENTS.md`.

## Goal

Replace the current Nuxt UI / Tailwind presentation layer of `my-plants-web` with an in-house design system imported from **Claude Design** (delivered as `new-frontend.zip`), translated to reusable Vue 3 components, while **preserving every real feature and the real API integration**. The visual design is given; this spec defines how it maps onto the real app.

## Source material (the zip)

`new-frontend.zip` is a **runnable React prototype** (React + Babel + `marked`, all via CDN) — a faithful *visual* recreation of our app, NOT production code. It contains:

- **`_ds/.../tokens/*.css`** — clean CSS custom-property tokens: `colors.css` (green/café/stone scales + semantic aliases + a full `[data-theme="dark"]` remap), `typography.css` (families, scale, weights, leading, tracking), `spacing.css` (4px grid, radii, shadows, layout widths, motion), `fonts.css` (Google Fonts `@import`), `base.css` (resets + `.mp-prose` blog markdown styling). `styles.css` `@import`s them.
- **`_ds/.../_ds_bundle.js`** — the DS components, **styled with inline styles in JS** (no `.ds-*` classes exist): `Button, Badge, ViabilityBadge, Card, Icon, Input, Select, Switch, FormGroup, Alert, NavTabs, TaskRow, PlantAvatar, Prose`, plus `TASK_LABELS`/`TASK_ICONS`.
- **`app/*.jsx`** — the prototype app: `app.jsx` (shell, nav, tweaks, mock state), `screens-core.jsx` + `screens-more.jsx` (the screens), `shared.jsx` (helper components), `tweaks-panel.jsx` (the dev tweak panel), `data.js` (mock data + article markdown).
- **`My Plants App.html`** — entry point; holds a small `<style>` block with the `.mp-*` chrome classes (topbar, bottom nav, icon button, menu, backlink, eyebrow, form, login, city-search popover, `.mp-hide-sci`).

**What we reuse vs rebuild:**
- **Reuse near-verbatim:** all token CSS (incl. dark mode and `.mp-prose`) and the `.mp-*` chrome CSS.
- **Rebuild as Vue:** every DS component (from inline-styled JS → Vue SFC), every helper, every screen (→ our real pages), discarding all mock data/handlers in favor of the real API.

## Decisions

1. **No Tailwind / no Nuxt UI.** Remove `@nuxt/ui` and its config; the design system CSS + Vue components replace it. Removal is **surface-by-surface** (port a page, then drop its Nuxt UI usage), never a big-bang delete that leaves the app unbuildable mid-way.
2. **Assets offline / self-hosted** (confirmed): fonts via **`@nuxt/fonts`** (drop the Google Fonts `@import`; keep the `font-family` tokens — the module downloads & serves Hanken Grotesk / Newsreader / JetBrains Mono locally). Icons via **`@nuxt/icon`** with **`@iconify-json/heroicons`** installed locally (no Iconify CDN at runtime).
3. **Adopt the design's responsive navigation** (confirmed): desktop = top ghost-row (Today/Plants/Places/Cities/Moving/Blog); mobile = sticky bottom tab bar (Today/Plants/Places/Blog/More) + a **More** page grouping Cities, Moving, and Sign out.
4. **Tweaks reduced to one real control:** keep only the **light/dark theme toggle**. Density is fixed **cozy**, corners fixed **soft**, scientific names **always shown** — these become baked-in defaults, not user toggles. The `tweaks-panel.jsx` dev panel and the `density`/`radius`/`showSci` machinery are NOT ported.
5. **Dark mode via `@nuxtjs/color-mode`** configured with `dataValue: 'theme'` so it sets `data-theme="dark"` on `<html>` (matching the tokens) with SSR-safe persistence and no flash-of-wrong-theme. The toggle in the app bar flips it.
6. **Preserve all real features** (the prototype omits some): plant editing (nickname/place + viability preview), place editing (name/climate-controlled), the real Moving (current-city-scoped simulate + apply), the real login wall (redirect + BFF), real cities (make-primary). Presentation changes; behavior does not.
7. **i18n is deferred** (per `CLAUDE.md`): keep user-facing strings in English in place. Blog article *content* stays as-is (Spanish Markdown from the API). Do not wire an i18n layer in this wave.
8. **Centralized API unchanged:** all data continues to flow through `composables/useApi.ts` + `types/api.ts` over the `/api` BFF proxy. No component fetches directly.

## Target architecture in `my-plants-web`

```
assets/css/
  design-system.css        # entry: @imports tokens + chrome (no @import of Google fonts)
  tokens/{colors,typography,spacing,base}.css   # synced from the zip
  chrome.css               # the .mp-* app-chrome classes (from the kit HTML <style>)
components/ui/             # the reusable DS components (one SFC each)
  Button.vue Badge.vue ViabilityBadge.vue Card.vue AppIcon.vue Modal.vue
  Input.vue SelectField.vue Switch.vue FormGroup.vue Alert.vue
  NavTabs.vue TaskRow.vue PlantAvatar.vue Prose.vue
components/ui/             # shared helpers (also reusable)
  ScreenHeader.vue SectionTitle.vue EmptyState.vue PlantName.vue
  IconTile.vue CardGrid.vue PlantStatusBadge.vue
components/                # feature components (compose ui/*)
  AppShell.vue (or layout)  AccountMenu.vue
  PlantEditModal.vue PlaceEditModal.vue   # re-skinned real edit features
  CitySearch.vue            # existing, re-skinned
layouts/default.vue        # top bar + responsive nav + bottom bar + <slot/>
layouts/auth.vue           # chrome-free, theme toggle only (login)
pages/…                    # existing routes, re-skinned to ui/* components
composables/useApi.ts      # unchanged
composables/useTaskMeta.ts # TASK_LABELS / TASK_ICONS (ported from the bundle)
```

Existing `components/AppNav.vue`, `components/TaskCard.vue`, `components/ViabilityBadge.vue` are replaced by their `ui/` equivalents and deleted per the dead-code rule (static-unreachable + basename grep clean + green build).

## Token & global CSS setup

- Copy `tokens/{colors,typography,spacing,base}.css` from the zip into `assets/css/tokens/` **verbatim** (they are clean and theme-complete).
- Create `assets/css/chrome.css` from the kit HTML `<style>` block (`.mp-*` classes). Drop `.mp-hide-sci` (sci names always shown).
- Create `assets/css/design-system.css` that `@import`s tokens (colors, typography, spacing, base) + chrome. Do **not** `@import` `fonts.css` (Google Fonts) — `@nuxt/fonts` provides the families. Register it via `nuxt.config.ts` `css: ['~/assets/css/design-system.css']`.
- `app.config.ts`: remove the `ui: {...}` Nuxt UI block.

## Component library (Vue SFCs under `components/ui/`)

Each is a thin, reusable SFC built on tokens (scoped `<style>` or chrome classes — **no inline styles duplicating tokens**), props mirroring the prototype's contract. Contracts (derived from prototype usage; exact visuals reconstructed from `_ds_bundle.js`):

- **Button** — props: `variant` (`solid`|`soft`|`ghost`, default solid), `color` (`primary`/green | `cafe` | `neutral`), `size` (`xs`|`sm`|`md`), `icon` (heroicon name), `block`, `disabled`, `loading`; emits `click`. Press scale 0.97, hover brightness 0.94.
- **Badge** — `color` (`green`|`amber`|`red`|`cafe`|`neutral`), `size` (`xs`|`sm`), `dot` (leading dot). Soft-tinted pill.
- **ViabilityBadge** — `level` (`good`|`caution`|`poor`), `reasons: string[]`. Care-semaphore pill + reason list. (Replaces the current `ViabilityBadge.vue`.)
- **Card** — slots: default, `header`, `footer`; props `padded` (bool, default true), `onClick`/clickable (lifts on hover). Dominant container.
- **AppIcon** — `name` (short alias e.g. `sun`, or `solid/sun`), `size`, `color`. Renders `@nuxt/icon`'s `<Icon>` with **Iconify** names — alias → `heroicons:<name>`, solid → `heroicons:<name>-solid` (NOT `i-heroicons-*` Tailwind utility classes, which belong to the Nuxt UI layer we are removing). Buttons/nav pass our short aliases, never raw Iconify/`i-*` names. Single source for icon rendering.
- **Input** — `type`, `icon`, `placeholder`, `modelValue` (v-model), `disabled`, `error`. Green focus ring.
- **SelectField** — `options: {label,value}[]`, `placeholder`, `modelValue` (v-model). (Named `SelectField` to avoid clashing with native `<select>`/Nuxt auto-import quirks.)
- **Switch** — `modelValue` (v-model boolean). Knob slides 200ms.
- **FormGroup** — `label`, `hint`, `error`, `required`; default slot wraps the control.
- **Alert** — `color` (`amber`|`red`|`green`), `title`, `description`, `icon`.
- **NavTabs** — `items: {key,label,icon}[]`, `active`, `variant` (`top`|`bottom`); emits `select`. Active uses `--nav-active-*`.
- **TaskRow** — `task` (code), `status` (`overdue`|`today`|`upcoming`), `dueLabel`, `withDoneDate` (bool, default false); emits `done` (payload `{ occurredOn? }`), `postpone`. When `withDoneDate` is on it shows the optional back-date `<input type="date">` that the real plant-detail care-feedback flow uses (`doneDate` → `occurredOn`); Today's screen uses the simple mode (Done = today). Uses `TASK_LABELS`/`TASK_ICONS`.
- **PlantAvatar** — `size`. Tinted rounded placeholder (the prototype has no real photos; keep a botanical placeholder tile).
- **Prose** — `html` string; wraps `.mp-prose`. For blog markdown (rendered via `marked`, as today).
- **Modal** — replaces `UModal` (plant & place edit). Props: `modelValue` (v-model open), `title`; slots: default (body), `footer`. Accessible: `Teleport` to `<body>`, focus trap, Escape + backdrop-click to close, `role="dialog"`/`aria-modal` + labelled title, body scroll-lock, restore focus on close. This is the reusable infrastructure behind `PlantEditModal`/`PlaceEditModal`.

Helpers (also under `components/ui/`, reusable): **ScreenHeader** (`title`, `subtitle`, `eyebrow`, `back`, `action` slot; emits `back`), **SectionTitle**, **EmptyState** (`icon`, slot), **PlantName** (`title`, `scientific`, `size` — renders the italic scientific name; always shown), **IconTile** (`icon`, `tone` green|cafe, `size`), **CardGrid** (`min`, `gap`, `desktop`), **PlantStatusBadge** (`plant`, `dueCount` → badge). **Real-data note (per Codex):** the `Plant` list type carries no tasks/status, and `todaysTasks()` returns `DueTaskResponse {plantId, task, nextDueOn}` with **no** overdue/today split. So the badge is derived by counting that plant's entries in the owner's single `todaysTasks()` result: `N due` (amber) when >0, else `All good` (green). No overdue/today distinction on the list (that needs per-plant `getPlantCare`, out of scope here).

## App shell & navigation

`layouts/default.vue` recreates `app.jsx`'s shell:
- Sticky **top bar**: 🌱 MyPlants wordmark (single canonical brand component, links to Today) + the `NavTabs variant="top"` (desktop) + theme toggle button + **AccountMenu**. **AccountMenu (per Codex)** is logged-in only: it shows the username and the **primary city** — the session carries only identity, so the city is loaded via `useApi().listCities()` and the one with `isPrimary` is displayed, with a `"No primary city"` fallback when none exists (never assume city lives in auth state, never fetch raw in the layout) — plus Sign out.
- **Main**: centered ≤1120px container, cozy padding.
- Sticky **bottom nav** (mobile): `NavTabs variant="bottom"` with Today/Plants/Places/Blog/More.
- **SSR-safe responsive (per Codex):** render BOTH navs in the DOM and show/hide them purely with **CSS media queries** (≥880px → top row visible, bottom hidden; <880px → vice-versa). Do NOT switch the nav *structure* via JS `matchMedia` — that risks a hydration mismatch / FOUC. A `useIsDesktop` composable may drive non-structural niceties (e.g. the two-column plant-detail layout) but never the nav's presence.
- **Auth-aware nav (per Codex, mirrors today's `AppNav`):** logged-out (no session) shows only the public **Blog** + a **Sign in** action — protected links hidden, `?redirect=` preserved by `middleware/auth.global.ts`. Logged-in shows the full nav + More. The **More** page's Cities/Moving/Sign out render only when authenticated.
- `layouts/auth.vue`: chrome-free (login), with only the theme toggle.

A new `pages/more.vue` (mobile "More") lists Cities, Moving, and Sign out as cards. On desktop these are reachable from the top row, so the `more` entry is hidden there.

## Dark mode

`@nuxtjs/color-mode` with `{ classSuffix: '', dataValue: 'theme', preference: 'light', fallback: 'light' }` → toggling sets `<html data-theme="dark">`, which the tokens already fully support. The app-bar toggle calls `useColorMode().preference = dark ? 'dark' : 'light'`. SSR-safe, persisted, no FOUC.

## Page-by-page port mapping

Every page keeps its **real data source and behavior**; only the markup/components change.

| Route | Real data / behavior (unchanged) | Design screen | Preserve / adapt |
|---|---|---|---|
| `pages/index.vue` (Today) | `useApi` today's tasks per plant | `TodayScreen` | Cards of due tasks with `TaskRow` Done/Postpone (real feedback calls). Empty: "Nothing due today. 🌿". |
| `pages/plants/index.vue` | list plants + one `todaysTasks()` call for due counts | `PlantsScreen` | Card grid; `PlantStatusBadge` derived from the `todaysTasks()` set (N due / All good); "Add plant" → `/plants/new`. |
| `pages/plants/[id].vue` | plant + care + **edit + viability preview** + **back-date feedback** | `PlantDetailScreen` | Identity card (`PlantName`, `ViabilityBadge`, "Read the care guide" → blog); care list via `TaskRow withDoneDate` (keeps the real `occurredOn` back-date Done + Postpone). **ADD the Edit button + `PlantEditModal`** (nickname/place + live viability preview, on the new `Modal`) — absent in prototype, real feature. |
| `pages/plants/new.vue` | create plant | `NewPlantScreen` | `FormGroup`+`SelectField`/`Input`; species options show `common (scientific)`. Real submit. |
| `pages/places/index.vue` | list + create + **edit** | `PlacesScreen` | List of place cards + add-place form (indoor switch reveals climate/humidity/temp). **ADD `PlaceEditModal`** (name/climate-controlled, on the new `Modal`) — real feature. |
| `pages/cities/index.vue` | list + create + make-primary | `CitiesScreen` | City cards (Primary badge, Make primary), add-city via real `CitySearch` (geocoder), primary switch. |
| `pages/moving.vue` | **real** current-city-scoped simulate + apply | `MovingScreen` | Target-city search → real viability results per plant → schedule move (real apply). Discard the mock `MOVE_SIM`. |
| `pages/blog/index.vue` | species guides list (`SpeciesSummary`: slug, commonName, scientificName only) | `BlogScreen` | Cards with common + italic scientific name. **Drop the prototype's "difficulty" badge** — not in the API (adapt to real data). |
| `pages/blog/[id].vue` | article markdown (`marked`, `briefEs`) | `ArticleScreen` | `Prose` with rendered markdown + a single static "Care guide" label badge (not data-driven). No difficulty badge. |
| `pages/login.vue` | real login (redirect + BFF) | `LoginScreen` | Re-skin only; keep real auth + `?redirect=`. Uses `auth.vue` layout. |
| `pages/more.vue` (new) | nav grouping | `MoreScreen` | Mobile-only entry to Cities/Moving/Sign out. |

## Tailwind / Nuxt UI removal

Order: (1) add the design-system CSS + components + modules first; (2) port **every surface — pages, layouts, AND components** — onto `ui/*`. The `U*` components in use today (counted across the web app) and their replacements: `UFormGroup`→`FormGroup`, `UButton`→`Button`, `UInput`→`Input`, `UCard`→`Card`, `USelect`→`SelectField`, `UToggle`→`Switch`, `UBadge`→`Badge`, `UForm`→ a plain `<form>` + our `FormGroup`/validation, `UModal`→`Modal`, `UContainer`→ the layout's centered container / a `<div>`, `UAlert`→`Alert`. (3) Only when the gate `rg '<U[A-Z]|@nuxt/ui|\bui:' repos/my-plants-web -g '!node_modules/**' -g '!.nuxt/**' -g '!.output/**'` returns **zero** hits do we remove `@nuxt/ui` from `nuxt.config.ts` modules, drop the `ui` block from `app.config.ts`, and uninstall the dependency. (4) delete the superseded `AppNav.vue`/`TaskCard.vue`/old `ViabilityBadge.vue` per the dead-code rule (static-unreachable + basename grep clean + green build). The build must stay green at each step.

## Performance review (mandatory)

Per the Frontend / UI rule, every new/imported page gets a perf review using the **perf probe** from `claude-skills` (`skills/web-perf-seo-audit/scripts/perf-probe.mjs`) — copy it into the repo (e.g. `scripts/perf-probe.mjs`) or invoke it from its skill path. The tokens already avoid the known anti-patterns (no infinite animations, no full-viewport blur/blend), but we still verify in a real browser. Acting-as-a-real-user verification + the perf probe runs are delegated to the **`qa-engineer`** subagent.

## Testing & verification

- **Gate:** `npm run typecheck && npm run build` green after every phase.
- Keep the existing unit tests (`utils/*.test.ts`) green; update any that reference removed components.
- **E2E via `qa-engineer`** once runnable: login, Today Done/Postpone, plant edit + viability preview, place edit, add plant/place/city, make-primary, moving simulate+schedule, blog render, dark-mode toggle persists, responsive nav (desktop top row vs mobile bottom bar + More).

## Out of scope / deferred

- **i18n** (planned later; strings stay English in place).
- Real plant **photos** (keep the botanical placeholder avatar).
- Any backend/API change — this is presentation-only. If a screen needs data the API doesn't expose, adapt the screen to real data, do not invent endpoints.

## Phase breakdown (plans follow)

1. **Foundation** — install modules (`@nuxt/fonts`, `@nuxt/icon` + heroicons json, `@nuxtjs/color-mode`), import tokens + chrome CSS, wire `nuxt.config.ts`, dark-mode config, `AppIcon`, fonts. App still builds on Nuxt UI.
2. **Core components** — `Button, Badge, ViabilityBadge, Card, PlantAvatar, Prose` + helpers (`ScreenHeader, SectionTitle, EmptyState, PlantName, IconTile, CardGrid, PlantStatusBadge`).
3. **Form, feedback & overlay components** — `Input, SelectField, Switch, FormGroup, Alert, NavTabs, TaskRow, Modal` + `useTaskMeta`. (`Modal` lands here so the page-port phases can build `PlantEditModal`/`PlaceEditModal` on it.)
4. **App shell & nav** — `layouts/default.vue` + `auth.vue`, wordmark, `AccountMenu`, `NavTabs` wiring, `pages/more.vue`, responsive behavior, theme toggle.
5. **Pages port (core)** — Today, Plants, Plant detail (+ `PlantEditModal`), Add plant.
6. **Pages port (rest)** — Places (+ `PlaceEditModal`), Cities, Moving, Blog list, Article, Login.
7. **Nuxt UI removal + perf + E2E** — remove `@nuxt/ui`, delete dead components, perf-probe every page, qa-engineer E2E, docs update (`docs/frontend-design-system.md` component↔source map, architecture, roadmap).

## Risks

- **Inline-styled DS components:** exact visuals live in `_ds_bundle.js`; implementers must read it per component to match spacing/shadows, not guess from the readme.
- **Nuxt auto-import name clashes** (`Card`, `Switch`, `Select`): use `ui/` SFC names that don't collide (e.g. `SelectField`); verify no global-component shadowing.
- **`@nuxt/fonts` offline fetch** happens at build; first build needs network to download the woff2 (then cached). Note in `docs/local-development.md`.
- **color-mode + SSR:** ensure the toggle and `dataValue:'theme'` don't double-apply; test no FOUC.
