# Frontend Redesign — Phase 2: Core Components Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the core presentational components + shared helpers as reusable Vue SFCs under `components/ui/`, styled from tokens (no inline styles duplicating tokens; no `.ds-*` global classes — recreate from the inline styles in the bundle).

**Architecture:** Each component is a thin `<script setup lang="ts">` SFC with a scoped `<style>` built on the design tokens. Props mirror the prototype contracts in the spec. These do not replace any page yet — they just exist and build.

**Tech Stack:** Vue 3 `<script setup>`, TypeScript, scoped CSS on design tokens.

**Reference:** spec §"Component library" + §"helpers"; visual source = `.design-import/_ds/my-plants-design-system-*/_ds_bundle.js` (read the matching component to match spacing/shadows/states) and the prototype usage in `.design-import/app/*.jsx`. `AppIcon` from Phase 1 is the only icon path. Commands run from `repos/my-plants-web/`. Verify each task with `npm run typecheck && npm run build`.

**Method for every component:** the prototype styles each component with **inline styles in `_ds_bundle.js`** — open that bundle, find the component, and translate its inline style object into a scoped `<style>` on the design tokens (no `.ds-*` classes exist). Props/emits are the spec contract. Default-export-free `<script setup lang="ts">`; accept a `class` passthrough; spread `$attrs` where the root is a native control.

---

### Task 1: Button

**Files:** Create `components/ui/Button.vue`

- [ ] Implement per spec: props `variant` (`solid`|`soft`|`ghost`, default `solid`), `color` (`primary`|`cafe`|`neutral`, default `primary`), `size` (`xs`|`sm`|`md`, default `md`), `icon` (alias for `AppIcon`), `block`, `disabled`, `loading`; emits `click`. Default slot = label. Hover brightness 0.94, press scale 0.97, focus ring `--shadow-focus`. Read the bundle's Button for exact paddings per size and tone colors (primary→`--brand-primary`, cafe→`--brand-accent`, neutral→stone). Verify build.

### Task 2: Badge

**Files:** Create `components/ui/Badge.vue`

- [ ] Props `color` (`green`|`amber`|`red`|`cafe`|`neutral`), `size` (`xs`|`sm`), `dot` (leading dot). Soft-tinted pill using the care/accent tokens (green→`--care-good-*`, amber→`--care-caution-*`, red→`--care-poor-*`, cafe→`--accent-cafe-*`, neutral→stone). Verify build.

### Task 3: ViabilityBadge

**Files:** Create `components/ui/ViabilityBadge.vue` (will supersede the old `components/ViabilityBadge.vue`, removed in Phase 7)

- [ ] Props `level` (`good`|`caution`|`poor`), `reasons: string[]`. Render the care-semaphore pill (label "Good fit"/"Caution"/"Poor fit") + the reasons as a small list when present. Use `--care-*` tokens. Verify build.

### Task 4: Card

**Files:** Create `components/ui/Card.vue`

- [ ] Slots: default, `header`, `footer`; props `padded` (bool, default true), `clickable`/`onClick` (lifts `shadow-md` + `translateY(-1px)` on hover; emits `click`). White `--surface-card`, 1px `--border-subtle`, `--shadow-sm`, `--radius-lg`. Verify build.

### Task 5: PlantAvatar

**Files:** Create `components/ui/PlantAvatar.vue`

- [ ] Prop `size` (px). A tinted rounded placeholder tile (botanical) — the prototype has no real photos. Use `--accent-green-surface`/`-ink` with a `sparkles` or leaf `AppIcon`. Verify build.

### Task 6: Prose

**Files:** Create `components/ui/Prose.vue`

- [ ] Prop `html` (string). Render a wrapper with class `mp-prose` and `v-html="html"`. (Markdown is produced by `marked` at the call site, as today.) Verify build.

### Task 7: Helper components

**Files:** Create `components/ui/ScreenHeader.vue`, `SectionTitle.vue`, `EmptyState.vue`, `PlantName.vue`, `IconTile.vue`, `CardGrid.vue`, `PlantStatusBadge.vue`

- [ ] **ScreenHeader** — props `title`, `subtitle`, `eyebrow`, `back` (label); slot `action`; emits `back`. Uses `.mp-backlink`/`.mp-eyebrow` chrome classes.
- [ ] **SectionTitle** — default slot, 700/17px heading.
- [ ] **EmptyState** — prop `icon` (alias, default `check-circle`); default slot; centered muted row with `AppIcon`.
- [ ] **PlantName** — props `title`, `scientific`, `size` (default 15). Renders bold title + italic muted `(scientific)` when present and ≠ title. Scientific name **always shown**.
- [ ] **IconTile** — props `icon` (alias), `tone` (`green`|`cafe`), `size` (default 44). Tinted square with `AppIcon`.
- [ ] **CardGrid** — props `min` (default 280), `gap` (default 14), `desktop` (bool). Grid 1-col mobile / `auto-fill minmax(min,1fr)` when `desktop`.
- [ ] **PlantStatusBadge** — props `plant`, `dueCount` (number). Renders `Badge` `amber` `{dueCount} due` when `dueCount>0`, else `green` dot `All good`. (Data source — the owner `todaysTasks()` set — is supplied by the caller in Phase 5; this component only renders from `dueCount`.)
- [ ] **Verify:** `npm run typecheck && npm run build` green.
- [ ] **Commit:** `git add components/ui && git commit -m "feat(web): core design-system components + helpers"` (use `git add` — the files are new; `-am` would skip them).
