# Frontend Redesign — Phase 7: Nuxt UI Removal, Perf & E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Nuxt UI / Tailwind entirely, delete superseded components, run the mandatory performance review on every page, run E2E, and update docs.

**Architecture:** With all surfaces ported (Phases 5–6), no `U*` usage should remain. Verify with the broad gate, then strip `@nuxt/ui`. Perf + E2E are delegated to the `qa-engineer` subagent.

**Tech Stack:** Nuxt 3, the perf probe from `claude-skills`, `qa-engineer` subagent.

**Reference:** spec §"Tailwind / Nuxt UI removal", §"Performance review", §"Testing & verification". Commands from `repos/my-plants-web/` unless noted.

---

### Task 1: Confirm no Nuxt UI usage remains

- [ ] **Step 1 (pre-removal gate — component usage ONLY):** From the web repo cwd, confirm no Nuxt UI *components* remain in any template: `rg '<U[A-Z]' . -g '!node_modules/**' -g '!.nuxt/**' -g '!.output/**' -g '!.design-import/**'` → zero hits. Do NOT include `@nuxt/ui`/`\bui:` in this pre-removal gate — the module and the `app.config.ts` `ui:` block are removed in Task 2, so they legitimately still exist right now (the broad gate runs AFTER removal, in Task 2 Step 4). If any `<U…>` remain, port them (Phase 5/6 scope) before continuing.

### Task 2: Remove Nuxt UI

**Files:** modify `nuxt.config.ts`, `app.config.ts`, `package.json`

- [ ] **Step 1:** Remove `'@nuxt/ui'` from `nuxt.config.ts` modules.
- [ ] **Step 2:** Remove the `ui: { primary, gray }` block from `app.config.ts` (delete the file if now empty, or leave a valid empty `defineAppConfig({})`).
- [ ] **Step 3:** `npm rm @nuxt/ui`.
- [ ] **Step 4 (verify + post-removal broad gate):** `npm run typecheck && npm run build` green WITHOUT Nuxt UI. Then the broad gate must be clean: `rg '<U[A-Z]|@nuxt/ui|\bui:' . -g '!node_modules/**' -g '!.nuxt/**' -g '!.output/**' -g '!.design-import/**'` → zero hits (no component usage, no module ref, no `ui:` config left).

### Task 3: Delete superseded components (dead-code rule)

**Files:** delete `components/AppNav.vue`, `components/TaskCard.vue`, `components/ViabilityBadge.vue`

- [ ] **Step 1:** For each, confirm dead: (a) no longer referenced (the new shell/components replaced them), (b) from the web repo cwd `rg '<AppNav|AppNav|TaskCard|ViabilityBadge' . -g '!.design-import/**'` shows only the new `ui/ViabilityBadge.vue` definition/usages, not the old paths. Note: `ui/ViabilityBadge.vue` (new) replaces the old `components/ViabilityBadge.vue` — ensure all usages import the new one.
- [ ] **Step 2:** Delete the three old files.
- [ ] **Step 3 (verify):** `npm run typecheck && npm run build` green; existing unit tests (`utils/*.test.ts`) green via `npm test`.
- [ ] **Step 4:** Commit: `git commit -am "refactor(web): remove Nuxt UI/Tailwind + superseded components"`

### Task 4: Performance review (mandatory, every page)

- [ ] **Step 1:** Copy the perf probe into the repo: `mkdir -p scripts && cp ~/projects/claude-skills/skills/web-perf-seo-audit/scripts/perf-probe.mjs scripts/perf-probe.mjs`, then `git add scripts/perf-probe.mjs && git commit -m "chore(web): vendor perf-probe script"`.
- [ ] **Step 2:** With the stack running (`./run.sh` from the workspace root), delegate to the **`qa-engineer`** subagent: run the perf probe against every route (`/`, `/plants`, `/plants/<id>`, `/plants/new`, `/places`, `/cities`, `/moving`, `/blog`, `/blog/<slug>`, `/login`, `/more`) in a real browser, in BOTH light and dark themes. Brief it with the invariant: flag any animated blurred/`mix-blend-mode` full-viewport element or infinite layout/paint animation (the tokens avoid these — confirm none crept in). Expected: no main-thread compositing red flags.

### Task 5: E2E (delegate to qa-engineer)

- [ ] **Step 1:** With the stack runnable, brief the `qa-engineer` to verify as a real user (LOCAL ONLY): login (retax/123) with `?redirect=`; Today Done/Postpone; plant edit (nickname/place) with live viability preview; plant-detail back-date Done; place edit (name/climate-controlled); add plant/place/city; make-primary; moving simulate + schedule; blog list + article render; **dark-mode toggle persists across reload**; **responsive nav** (desktop top row vs mobile bottom bar + More); logged-out shows only Blog + Sign in. Provide (1) what, (2) how, (3) expected per item.
- [ ] **Step 2:** Diagnose every failure as a real bug (fix at root) or a brittle test; never mask.

### Task 6: Docs (WORKSPACE ROOT, not the web submodule)

**Context:** these docs live in the **workspace root repo** (`/home/retaxmaster/projects/my-plants/docs/…`), already on its own `feature/frontend-redesign` branch — NOT in `repos/my-plants-web`. Run these from the workspace root, and commit them in the ROOT repo (separate from every web-submodule commit above).

**Files:** modify `docs/frontend-design-system.md`, `docs/architecture.md`, `docs/mvp-roadmap.md`, `docs/local-development.md`

- [ ] **Step 1:** Fill the **component↔source map** in `docs/frontend-design-system.md` (each prototype piece → its `components/ui/*` SFC).
- [ ] **Step 2:** Update `docs/architecture.md` (web stack: in-house design system, no Nuxt UI/Tailwind; dark mode; offline assets) and `docs/mvp-roadmap.md` (redesign done).
- [ ] **Step 3:** Note in `docs/local-development.md` that the first build downloads webfonts via `@nuxt/fonts` (needs network once).
- [ ] **Step 4:** Commit in the ROOT repo: `cd /home/retaxmaster/projects/my-plants && git add docs/ && git commit -m "docs: frontend redesign — component map, architecture, roadmap, local-dev"`
- [ ] **Step 5 (note):** the submodule-pointer bump + merges/pushes are NOT part of this plan — they happen only with explicit user approval per the Multi-repo feature workflow.
