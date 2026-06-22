# Frontend design system & component library

Procedure behind the **Frontend / UI** rules in `CLAUDE.md` ≡ `AGENTS.md`. The *rules* (reuse before rewrite; tokens are the single source of visual truth; centralized API access; i18n; performance review; "sync, don't rebuild") live there; this doc is the **how** for importing and maintaining the design system in `repos/my-plants-web`.

The design system is authored externally with **Claude Design** and delivered as a `*.zip` (dropped at the workspace root). It evolves over time — token/CSS updates and/or new components. We are migrating the web app off **Tailwind / Nuxt UI** onto this in-house system.

## Where the design system lives in `my-plants-web`

- `assets/css/tokens/{colors,typography,spacing,base}.css` — the **token layer**: CSS custom properties for colors (incl. the full `[data-theme="dark"]` remap), type, spacing, radii, shadows, motion, plus `.mp-prose` blog styling. Copied **verbatim** from the zip — the single source of visual truth.
- `assets/css/chrome.css` — the small set of app-chrome classes (`.mp-topbar`, `.mp-form`, `.mp-iconbtn`, …) from the zip's kit HTML `<style>`.
- `assets/css/design-system.css` — the **entry** registered in `nuxt.config.ts` (`css: [...]`): `@import`s the tokens + chrome. It does NOT `@import` the zip's Google-Fonts CSS — `@nuxt/fonts` self-hosts the families.
- `components/ui/*` — **Vue SFCs**, one per design piece. **Important:** this design system has **no global `.ds-*` component-class library** — the zip ships its components *inline-styled inside a JS bundle* (`_ds_bundle.js`). So each Vue SFC carries its own styling in a scoped `<style>` (or the chrome classes) built on the **tokens** — read the bundle per component to match the exact visuals. There is no `ds-components.css`.

> The exact file names above are the target layout. Until the migration completes, Tailwind/Nuxt UI may still be present — remove it surface by surface as each is ported, never in a big-bang rewrite.

## Sync workflow — perform every time the user says there is a new `*.zip`

1. Unzip and **diff** the token CSS against `assets/css/tokens/*` (and the chrome `<style>` against `assets/css/chrome.css`). Apply any token/class updates. Preserve the Nuxt font wiring (`@nuxt/fonts`) — do not re-import the Google-Fonts CSS.
2. For each component in the zip, **check the map below** for an existing Vue SFC. **Only create SFCs for NEW pieces — never rebuild existing ones.**
3. New SFCs are thin `<script setup lang="ts">` components: modifiers become typed props (variants), accept a `class` passthrough, and spread `$attrs` (`inheritAttrs: false` + `v-bind="$attrs"` where needed). Their visuals come from a scoped `<style>` using the tokens — reconstruct them from the inline styles in `_ds_bundle.js` (there is no global class library to consume).
4. **Refactor** the app to use the new/updated components wherever the equivalent markup is currently hand-written (or still Nuxt UI). **i18n is deferred** (see CLAUDE.md): keep visible strings in English in place for now; do not hardcode-then-forget — when i18n lands, every string moves to the i18n layer.
5. **Run the performance review** on every new/imported page (the `/web-perf-seo-audit` skill). Claude Design markup is imported as-is and has shipped CPU-melting patterns before (full-viewport blurred / `mix-blend-mode` auroras animated on the main thread). Verify in a **real browser** — never trust static CSS reasoning. Acting-as-a-real-user verification is delegated to the `qa-engineer` subagent.
6. **Verify** with `npm run typecheck && npm run build`.

## Component ↔ source map (do NOT recreate)

Maintain an explicit map from each zip preview (`comp-*.html`) to its Vue wrapper, so future syncs never recreate an existing component. Update it whenever a wrapper is added. Page-specific layout stays in the page/component; everything else must use design-system tokens and reach for an existing component before writing markup by hand.

Filled from the first import (`new-frontend.zip`, 2026-06-22). DS-bundle components and `app/shared.jsx` helpers map to SFCs under `components/ui/`; app-chrome and real-feature pieces map to feature components.

| Design piece (prototype source) | Vue component |
|---|---|
| `core/Button` | `ui/Button.vue` |
| `core/Badge` | `ui/Badge.vue` |
| `core/ViabilityBadge` | `ui/ViabilityBadge.vue` |
| `core/Card` | `ui/Card.vue` |
| `core/Icon` | `ui/AppIcon.vue` (renders `@nuxt/icon` with `heroicons:*`) |
| `forms/Input` | `ui/Input.vue` |
| `forms/Select` | `ui/SelectField.vue` (renamed to dodge auto-import clash) |
| `forms/Switch` | `ui/Switch.vue` |
| `forms/FormGroup` | `ui/FormGroup.vue` |
| `feedback/Alert` | `ui/Alert.vue` |
| `navigation/NavTabs` | `ui/NavTabs.vue` |
| `plants/TaskRow` | `ui/TaskRow.vue` (+ `composables/useTaskMeta.ts` for labels/icons) |
| `plants/PlantAvatar` | `ui/PlantAvatar.vue` |
| `content/Prose` | `ui/Prose.vue` |
| (modal pattern — no bundle component) | `ui/Modal.vue` (accessible: focus trap, Teleport, Escape/backdrop, scroll-lock) |
| `shared.jsx` ScreenHeader | `ui/ScreenHeader.vue` |
| `shared.jsx` SectionTitle | `ui/SectionTitle.vue` |
| `shared.jsx` EmptyState | `ui/EmptyState.vue` |
| `shared.jsx` PlantName | `ui/PlantName.vue` (always shows the italic scientific name) |
| `shared.jsx` IconTile | `ui/IconTile.vue` |
| `shared.jsx` CardGrid | `ui/CardGrid.vue` |
| `shared.jsx` PlantStatusBadge | `ui/PlantStatusBadge.vue` (renders from `dueCount`) |
| `shared.jsx` CitySearch (mock) | `components/CitySearch.vue` (real `searchCities` geocoder) |
| `app.jsx` wordmark | `ui/BrandMark.vue` (the single canonical 🌱 MyPlants lockup) |
| `app.jsx` theme toggle | `ui/ThemeToggle.vue` (flips `@nuxtjs/color-mode`) |
| `app.jsx` AccountMenu | `components/AccountMenu.vue` (primary city via `useApi().listCities()`) |
| `app.jsx` shell + nav | `layouts/default.vue` (responsive, CSS-media-query nav) + `pages/more.vue` |
| `app.jsx` TweaksPanel | _not ported_ — only the light/dark toggle was kept (density=cozy, corners=soft, sci-names always on are baked in) |
| (real feature, absent in prototype) | `components/PlantEditModal.vue`, `components/PlaceEditModal.vue` (on `ui/Modal`) |
