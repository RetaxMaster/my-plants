# Edit Phase 6 — Docs, runnable stack, E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document the new editing surfaces and the location-semantics changes, confirm the stack runs (no migration this wave), and verify everything end-to-end with the `qa-engineer`.

**Architecture:** Docs in root `docs/`. "Runnable" means `./run.sh` boots a working app — no DB migration is introduced this wave. E2E is delegated to the `qa-engineer` (local only).

**Repos:** root docs; `repos/my-plants-api`, `repos/my-plants-web` (implemented in Phases 1–5).

---

### Task 1: Update docs

**Files:** Modify `docs/architecture.md`, `docs/mvp-roadmap.md`

- [ ] **Step 1: `docs/architecture.md`** — add/extend the care-engine notes:
  - **Editing surfaces:** `PATCH /plants/:id` (nickname/place; place change recomputes the plant), `GET /plants/:id/viability-preview?placeId=` (read-only projected viability), `PATCH /places/:id` (name/climateControlled; a climate-controlled change recomputes every plant in the place).
  - **Per-plant day boundary:** the "today" cutoff now derives from each plant's place-city timezone (was the owner's primary city). The `isPrimary` flag remains, used only by Moving.
  - **Honest Moving:** `simulate`/`apply` scope to the plants/places at the current (primary) city; the documented indoor/outdoor asymmetry (apply repoints only outdoor places) is unchanged.

- [ ] **Step 2: `docs/mvp-roadmap.md`** — mark the plant/place editing + per-plant cutoff + honest-Moving milestone done.

- [ ] **Step 3: Commit** — `git add docs/architecture.md docs/mvp-roadmap.md && git commit -m "docs: document editing surfaces, per-plant cutoff, honest moving"`

---

### Task 2: Leave the stack runnable (local only)

- [ ] **Step 1:** No migration this wave — confirm `npx prisma generate` is current and nothing schema-side changed. Apply nothing.
- [ ] **Step 2:** From the workspace root run `./run.sh`; confirm API on :8000 and web on :8001 come up. Leave it running for the E2E task. (If orphaned dev servers hold the ports, clean them first.)
- [ ] **Step 3:** No commit (local runtime only).

---

### Task 3: E2E verification via the `qa-engineer` (local only)

- [ ] **Step 1: Dispatch the `qa-engineer`** with a precise brief — what to test, how, expected results. Credentials: admin `retax` / `123`. Checks:
  1. **Edit a plant's nickname:** on `/plants/[id]`, open Edit, change the nickname, Save. Expected: the title updates immediately (both plant and care refresh), no full reload needed.
  2. **Move a plant to another place with preview:** open Edit, pick a different place. Expected: a projected viability semaphore appears BEFORE saving. Save. Expected: the plant's place is updated and its care/viability reflect the new place.
  3. **Login page / nav unaffected:** the edit modal opens over the page; navigation still works.
  4. **Edit a place's name:** on `/places`, open Edit on a place, rename it, Save. Expected: the list shows the new name; no recompute side effects on unrelated plants.
  5. **Edit a place's climate-controlled:** toggle it and Save. Expected: plants in that place have their care recomputed (their due dates may shift); the change persists.
  6. **Ownership sanity (single user):** the place selector in the plant edit modal shows the user's own places only.

- [ ] **Step 2: Triage findings.** For each red, diagnose root cause and fix at the source (no workarounds). Re-run through the real flow until green. Document every fix.

- [ ] **Step 3: Full regression** — `./scripts/test-all.sh` (API `npm test`, web `npm run typecheck` + build, schema/engine). Expected: all green.

- [ ] **Step 4: Commit** any fixes — `git add -A && git commit -m "fix(edit): address E2E findings"`

---

### Task 4: Final code review gate (Codex, degrade to Claudex only if Codex is unavailable)

- [ ] **Step 1:** Run the implemented diff across both repos through Codex (`using-codex-workflow`), handing it the spec + the full edit-modules change. Iterate fixes until GREEN.
- [ ] **Step 2:** Apply accepted findings at the root; re-review until GREEN. Document deferred items with rationale.
- [ ] **Step 3:** Summary to the user: what was built, how to test (`./run.sh`, edit a plant/place, observe the preview and recompute), every autonomous decision + justification, and an explicit note on branch state (nothing merged/pushed/pointer-bumped without approval).
