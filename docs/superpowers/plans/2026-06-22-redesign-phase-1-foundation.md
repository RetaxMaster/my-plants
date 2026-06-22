# Frontend Redesign — Phase 1: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the in-house design system's foundations in `my-plants-web` — token CSS, chrome CSS, self-hosted fonts, offline icons, dark mode — without breaking the still-Nuxt-UI app.

**Architecture:** Copy the Claude Design token CSS verbatim, add a CSS entry, install `@nuxt/fonts`, `@nuxt/icon` (+ `@iconify-json/heroicons`) and `@nuxtjs/color-mode` (with `dataValue: 'theme'`), and add a single `AppIcon` component. Nuxt UI stays installed; nothing is removed yet.

**Tech Stack:** Nuxt 3, Vue 3, CSS custom properties, @nuxt/fonts, @nuxt/icon, @nuxtjs/color-mode.

**Reference:** spec `docs/superpowers/specs/2026-06-22-frontend-redesign-claude-design.md`; prototype at `repos/my-plants-web/.design-import/` (tokens under `.design-import/_ds/my-plants-design-system-*/tokens/`, chrome CSS in `.design-import/My Plants App.html` `<style>`, icon names in `.design-import/_ds/.../readme.md`). All commands run from `repos/my-plants-web/`.

---

### Task 1: Copy token CSS verbatim

**Files:**
- Create: `assets/css/tokens/colors.css`, `typography.css`, `spacing.css`, `base.css`

- [ ] **Step 1:** Copy the four files from `.design-import/_ds/my-plants-design-system-*/tokens/{colors,typography,spacing,base}.css` into `assets/css/tokens/` **verbatim** (they include the `[data-theme="dark"]` remap and `.mp-prose`). Do NOT copy `fonts.css` (Google Fonts `@import`) — `@nuxt/fonts` handles families.
- [ ] **Step 2:** Confirm the files contain the dark-mode block (`grep -l 'data-theme="dark"' assets/css/tokens/colors.css`).

### Task 2: Chrome CSS

**Files:**
- Create: `assets/css/chrome.css`

- [ ] **Step 1:** Extract the `<style>` block from `.design-import/My Plants App.html` into `assets/css/chrome.css` (the `.mp-topbar`, `.mp-topbar-inner`, `.mp-bottomnav`, `.mp-iconbtn`, `.mp-menu`, `.mp-menu-item`, `.mp-backlink`, `.mp-eyebrow`, `.mp-form`, `.mp-login`, `.mp-clickable`, `.mp-search-pop`, `.mp-search-opt` rules). **Omit** `.mp-hide-sci` (scientific names are always shown). Keep the `html, body` and `#root` resets adapted: set `body { background: var(--surface-page); }` only (Nuxt has no `#root`).

### Task 3: Design-system CSS entry

**Files:**
- Create: `assets/css/design-system.css`

- [ ] **Step 1:** Create `design-system.css` with `@import`s in order: `./tokens/colors.css`, `./tokens/typography.css`, `./tokens/spacing.css`, `./tokens/base.css`, `./chrome.css`. No Google-Fonts import.

### Task 4: Install modules

**Files:**
- Modify: `package.json`

- [ ] **Step 1:** Install: `npm i -D @nuxt/fonts @nuxt/icon @nuxtjs/color-mode @iconify-json/heroicons`
- [ ] **Step 2:** Verify they land in `package.json`.

### Task 5: Wire nuxt.config.ts

**Files:**
- Modify: `nuxt.config.ts`

- [ ] **Step 1:** Add `'@nuxt/fonts'`, `'@nuxt/icon'`, `'@nuxtjs/color-mode'` to `modules` (keep `'@nuxt/ui'`, `'nuxt-auth-utils'`).
- [ ] **Step 2:** Add `css: ['~/assets/css/design-system.css']`.
- [ ] **Step 3:** Add color-mode config: `colorMode: { classSuffix: '', dataValue: 'theme', preference: 'light', fallback: 'light' }` (so it sets `<html data-theme="dark">`).

- [ ] **Step 4 (verify):** Run `npm run typecheck && npm run build`. Expected: PASS (first build downloads the woff2 fonts — needs network).

### Task 6: AppIcon component

**Files:**
- Create: `components/ui/AppIcon.vue`

- [ ] **Step 1:** Implement `AppIcon` per the spec contract. Concrete reference (props `name` short alias, `solid/<name>` → solid; `size` px; `color` default `currentColor`; renders `@nuxt/icon`'s `<Icon>` with an Iconify `heroicons:*` name — NEVER `i-heroicons-*` Tailwind classes):

```vue
<script setup lang="ts">
const props = withDefaults(defineProps<{ name: string; size?: number; color?: string }>(), {
  size: 18, color: 'currentColor',
});
const iconify = computed(() => {
  const solid = props.name.startsWith('solid/');
  const base = solid ? props.name.slice(6) : props.name;
  return `heroicons:${base}${solid ? '-solid' : ''}`;
});
</script>
<template>
  <Icon :name="iconify" :style="{ fontSize: size + 'px', color }" />
</template>
```
- [ ] **Step 2 (verify):** Drop `<AppIcon name="sun" :size="18" />` temporarily on `pages/index.vue`, run `npm run dev` mentally / `npm run build`; confirm it builds. Remove the temp usage.
- [ ] **Step 3:** Commit: `git add -A && git commit -m "feat(web): design-system foundations (tokens, fonts, icons, dark mode, AppIcon)"`

### Task 7: Sanity — dark mode token application

- [ ] **Step 1:** Confirm (by reading) that setting `<html data-theme="dark">` would remap surfaces (the tokens already do this). No code beyond the color-mode config is needed yet; the toggle UI lands in Phase 4.
- [ ] **Step 2 (verify):** Final `npm run typecheck && npm run build` green.
