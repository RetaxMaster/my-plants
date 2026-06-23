# Acting As — Phase 6: E2E + Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify the whole wave as a real user via the `qa-engineer` subagent (LOCAL ONLY), then update the docs the change touches.

**Architecture:** E2E is delegated — never run Playwright yourself. Docs live in the **workspace root repo** (`/home/retaxmaster/projects/my-plants/docs/…`), committed separately from the two submodules.

**Tech Stack:** `qa-engineer` subagent; Markdown docs.

**Reference:** spec §6, §7. Stack runs via `./run.sh` from the workspace root (api:8000, web:8001); admin login `retax`/`123`.

---

### Task 1: Make the stack runnable & seed a second owner for impersonation

**Context:** Acting As needs at least two owners to be meaningful. The dev DB already has `retax` (ADMIN) plus a couple of test owners; that is enough. No migration is introduced by this wave (no schema change), so nothing to migrate.

- [ ] **Step 1:** From the workspace root, start the stack: `./run.sh` (api:8000 + web:8001). Confirm the API answers (`curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/` → any HTTP code) and the web responds.
- [ ] **Step 2:** Confirm there are ≥2 owners with at least one non-admin user to act as. If only `retax` exists, create a second user via the API's user-creation npm script (see `docs/local-development.md`), e.g. a `USER` named `tester`. Add at least one plant for that user (or for `retax`) so the impersonated views have content. Document whatever you created.

---

### Task 2: E2E via the qa-engineer subagent (delegate — LOCAL ONLY)

- [ ] **Step 1:** Invoke the `qa-engineer` subagent with this brief (what / how / expected). Do NOT run Playwright yourself.

  **What to verify (acting as a real user, http://localhost:8001):**

  1. **B7 fixed — admin's own view shows a single primary.** Log in as `retax`/`123`. Go to `/cities`. *Expected:* only `retax`'s own cities appear, with exactly **one** "Primary" badge (no other owner's cities/primaries leak in). The account menu's primary city is unambiguous.
  2. **Owners view is admin-only.** As `retax` (ADMIN), the account menu shows **"Switch user"**, and `/admin/owners` lists every owner with an "Act as" button (own row marked "You"). *Expected for a USER:* logged in as the non-admin user, the account menu has **no** "Switch user" entry and visiting `/admin/owners` returns a 404 (the surface does not render).
  3. **Acting As round-trip.** As `retax`, open `/admin/owners` → "Act as" the other owner. *Expected:* a persistent banner **"Acting as <username> — Stop acting as"** appears; `/plants`, `/places`, `/cities` now show **that owner's** resources (not retax's). Click **Stop acting as** (banner or account menu). *Expected:* the banner disappears and the views return to retax's own resources.
  4. **Write while acting-as is attributed to the target.** While acting as the other owner, create a place or city. *Expected:* it is created under the **target** owner (visible while acting-as; gone after Stop).
  5. **B8 fixed — Moving fallback + warning.** Arrange (or use existing) state where the primary city has **no** plants while plants live in another city (the diagnosed `retax` state qualifies: primary Guadalajara empty, plants in "Test City"). Go to `/moving`, simulate against any target city. *Expected:* results are **not empty** — all the owner's plants appear, and each plant not in the current city shows the amber warning **"This plant is not in your current city — it is in <city>."** When the primary *does* contain plants, simulate shows only those, with no warning.

  **How:** real browser against the running stack; judge semantically; explore edge cases (e.g., a USER forging the admin surface, stop-then-reload persistence).

  **Expected overall:** every item above passes; report anything that does not.

- [ ] **Step 2:** Triage every failure as a real bug (fix at root, re-run through the unmodified flow) or a brittle test. Never mask. If a fix touches the API or web, add/adjust unit tests and re-run `./scripts/test-all.sh`.

---

### Task 3: Docs (WORKSPACE ROOT repo)

**Context:** Run these from the workspace root and commit in the ROOT repo (separate from the submodule commits).

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/care-engine.md`
- Modify: `docs/mvp-roadmap.md`
- Create or modify: `docs/api/` collection (seed `docs/api/README.md` if absent)

- [ ] **Step 1:** In `docs/architecture.md`, document the **effective-owner / Acting As** model: an admin defaults to own-scope (the old "ADMIN sees all" `{}` is gone); admin reach across owners comes only from impersonation carried by the role-gated `X-Act-As-Owner` header (set in the BFF sealed session, validated in the guard); role is always the real token role.
- [ ] **Step 2:** In `docs/care-engine.md`, near the Moving section, document the **empty-primary simulate fallback**: when the primary city holds none of the owner's plants, `simulate` returns all owner plants with per-plant `placeCityName` + `inPrimaryCity` so the UI warns; the normal "only current-city plants" behavior is unchanged.
- [ ] **Step 3:** In `docs/mvp-roadmap.md`, mark the B7/B8 fixes (admin Acting As + honest-moving fallback) done.
- [ ] **Step 4:** Update the **API collection** under `docs/api/` (the API exists and this wave changes its contract, so document it rather than defer). If `docs/api/` already exists, add/extend its entries; if it does not exist yet, create `docs/api/README.md` to seed the collection with these endpoints (a simple per-endpoint Markdown table: method, path, auth, request, response). Document:
  - `GET /owners` — admin-only (403 for a USER); response `[{ ownerId, username, role }]`.
  - The `X-Act-As-Owner: <ownerId>` request header — honored only for an ADMIN token; unknown owner → 403; sets the effective owner for that request.
  - `GET /auth/me` — now returns `{ username, role, actingAs: { ownerId } | null }`.
  - `POST /moving/simulate` — each result now includes `placeCityName` and `inPrimaryCity`; behavior note on the empty-primary fallback.
  - `POST /care-plan/recompute` — now scopes to the effective owner (no all-owners recompute over HTTP).
- [ ] **Step 5: Commit (ROOT repo).**

```bash
cd /home/retaxmaster/projects/my-plants
git add docs/
git commit -m "docs: effective-owner/Acting As model + simulate empty-primary fallback"
```

- [ ] **Step 6 (note):** Submodule merges/pushes and the workspace pointer bump are NOT part of this plan — they happen only with explicit user approval per the Multi-repo feature workflow.

---

### Task 4: Final whole-workspace verification

- [ ] **Step 1 (verify):** `./scripts/test-all.sh` → all green (API unit tests + web typecheck/build).
- [ ] **Step 2:** Confirm the stack still starts cleanly via `./run.sh` and the acting-as flow works end to end (already covered by Task 2, re-confirm after any doc-time changes).
