# Frontend Redesign — Phase 4: App Shell & Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recreate the responsive, auth-aware app shell — top bar (wordmark + desktop nav + theme toggle + account menu), mobile bottom nav + a `More` page — using the new components, replacing `layouts/default.vue` and `auth.vue` and `components/AppNav.vue`'s role.

**Architecture:** Both navs render in the DOM; CSS media queries decide visibility (no JS `matchMedia` for nav structure → no FOUC/hydration mismatch). Auth state from `useUserSession()` (nuxt-auth-utils). Theme toggle via `useColorMode()`.

**Tech Stack:** Nuxt 3 layouts, Vue 3, `@nuxtjs/color-mode`, nuxt-auth-utils session.

**Reference:** spec §"App shell & navigation"; prototype `.design-import/app/app.jsx` (shell, `AccountMenu`, nav models, `MoreScreen`). Keep the real login wall + `middleware/auth.global.ts` (do not touch routing/redirect). Commands from `repos/my-plants-web/`. Verify each task with `npm run typecheck && npm run build`.

---

### Task 1: BrandMark (wordmark) component

**Files:** Create `components/ui/BrandMark.vue`

- [ ] Single canonical 🌱 + "MyPlants" lockup (`--text-brand`, 800/18px). Optional `to` prop (default `/`) → `NuxtLink`. Per the brand-in-one-component rule, this is the only place the wordmark is authored. Verify build.

### Task 2: Theme toggle + AccountMenu

**Files:** Create `components/ui/ThemeToggle.vue`, `components/AccountMenu.vue`

- [ ] **ThemeToggle** — `.mp-iconbtn` button with `AppIcon` `moon`/`sun`; on click flip `useColorMode().preference` between `'light'`/`'dark'`. SSR-safe.
- [ ] **AccountMenu** — logged-in only. Shows username (`useUserSession().user`) + the **primary city**: load via `useApi().listCities()`, display the `isPrimary` one (`"No primary city"` fallback); never assume city in auth state, never raw-fetch outside `useApi`. Dropdown (`.mp-menu`) with Sign out. **Mirror the existing `AppNav` logout exactly** (do not reinvent): `const { user, clear } = useUserSession(); async function logout() { await $fetch('/api/auth/logout', { method: 'POST' }); await clear(); await navigateTo('/login'); }`. Verify build.

### Task 3: Default layout (shell + responsive auth-aware nav)

**Files:** Modify `layouts/default.vue`; Create `composables/useIsDesktop.ts` (non-structural use only)

- [ ] Build the shell: sticky `.mp-topbar` with `BrandMark` + desktop `NavTabs variant="top"` + `ThemeToggle` + `AccountMenu`; `<main>` centered ≤1120px with cozy padding; sticky mobile `NavTabs variant="bottom"`.
- [ ] **Nav items:** top = Today/Plants/Places/Cities/Moving/Blog; bottom = Today/Plants/Places/Blog/More. Map current route → active key (incl. `plant`/`new`→plants, `article`→blog, `cities`/`moving`/`more`→more on mobile).
- [ ] **Auth-aware:** read `useUserSession().loggedIn`. Logged-out → show only Blog + a "Sign in" link (mirror current `AppNav` hiding protected links); logged-out hides `AccountMenu`. Logged-in → full nav.
- [ ] **Responsive via CSS only:** render both `NavTabs`; show top at `≥880px`, bottom at `<880px` via media queries. No JS branch deciding which to render.
- [ ] `useIsDesktop` may be used later for the plant-detail two-column layout, not for nav presence.
- [ ] Verify build.

### Task 4: Auth layout

**Files:** Modify `layouts/auth.vue`

- [ ] Chrome-free centered slot + only the `ThemeToggle` (top-right). Used by `pages/login.vue`. Verify build.

### Task 5: More page (mobile nav grouping)

**Files:** Create `pages/more.vue`

- [ ] Cards linking to Cities and Moving + a Sign out card (same logout as AccountMenu). Authenticated-only (the global middleware already gates it). On desktop the user reaches these from the top row; `more` simply isn't in the top nav. Verify build.

### Task 6: Verify shell end-to-end

- [ ] **Step 1:** `npm run typecheck && npm run build` green.
- [ ] **Step 2:** Note: pages still use Nuxt UI internals; the shell now wraps them. That's expected until Phases 5–6 port the page bodies.
- [ ] **Commit:** `git add -A && git commit -m "feat(web): responsive auth-aware app shell + nav + theme toggle"` (new files — use `git add -A`, not `-am`).
