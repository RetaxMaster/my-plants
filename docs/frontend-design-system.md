# Frontend design system & component library

Procedure behind the **Frontend / UI** rules in `CLAUDE.md` ≡ `AGENTS.md`. The *rules* (reuse before rewrite; tokens are the single source of visual truth; centralized API access; i18n; performance review; "sync, don't rebuild") live there; this doc is the **how** for importing and maintaining the design system in `repos/my-plants-web`.

The design system is authored externally with **Claude Design** and delivered as a `*.zip` (dropped at the workspace root). It evolves over time — token/CSS updates and/or new components. We are migrating the web app off **Tailwind / Nuxt UI** onto this in-house system.

## Where the design system lives in `my-plants-web`

- `assets/css/design-system.css` — **tokens**: global CSS variables for colors, type, spacing, radii, shadows. The single source of visual truth. Synced from the zip's token CSS.
- `assets/css/ds-components.css` — the **global component-class library** (the raw `.ds-*` classes), imported once in `nuxt.config.ts` (`css: [...]`).
- `components/ui/*` — **Vue wrappers** (`<script setup lang="ts">`) that consume the global classes. One component per design piece; props expose the class modifiers as variants, accept a `class` passthrough, and forward native attributes.

> The exact file names above are the target layout; create them as the first zip import lands and update this doc if they differ. Until the migration completes, Tailwind/Nuxt UI may still be present — remove it surface by surface as each is ported, never in a big-bang rewrite.

## Sync workflow — perform every time the user says there is a new `*.zip`

1. Unzip and **diff** the root CSS against `assets/css/design-system.css` and `assets/css/ds-components.css`. Apply any token/class updates. Preserve any Nuxt font wiring (`@nuxt/fonts` / `nuxt.config.ts`) — do not re-import fonts Nuxt already injects.
2. For each component in the zip, **check the map below** for an existing Vue wrapper. **Only create wrappers for NEW pieces — never rebuild existing ones.**
3. New wrappers are thin `<script setup>` components over the `.ds-*` classes: modifiers become typed props (variants), accept `class` passthrough, and spread `$attrs` (`inheritAttrs: false` + `v-bind="$attrs"` where needed). Add a scoped `<style>` only when a piece uses classes that are NOT in the global library.
4. **Refactor** the app to use the new/updated components wherever the equivalent markup is currently hand-written (or still Nuxt UI). **i18n is deferred** (see CLAUDE.md): keep visible strings in English in place for now; do not hardcode-then-forget — when i18n lands, every string moves to the i18n layer.
5. **Run the performance review** on every new/imported page (the `/web-perf-seo-audit` skill). Claude Design markup is imported as-is and has shipped CPU-melting patterns before (full-viewport blurred / `mix-blend-mode` auroras animated on the main thread). Verify in a **real browser** — never trust static CSS reasoning. Acting-as-a-real-user verification is delegated to the `qa-engineer` subagent.
6. **Verify** with `npm run typecheck && npm run build`.

## Component ↔ source map (do NOT recreate)

Maintain an explicit map from each zip preview (`comp-*.html`) to its Vue wrapper, so future syncs never recreate an existing component. Update it whenever a wrapper is added. Page-specific layout stays in the page/component; everything else must use design-system tokens and reach for an existing component before writing markup by hand.

| Design piece (zip preview) | Vue component (`components/ui/`) |
|---|---|
| _(to be filled when the first Claude Design zip is imported)_ | — |
