# Auth Phase 7 — Docs, runnable stack, E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document the auth layer, leave the stack locally runnable (migration applied, env set, admin user created, deps installed), and verify the login wall end-to-end with the qa-engineer.

**Architecture:** Docs in the root `docs/`; runnable means `./run.sh` boots a working, login-gated app; E2E is delegated to the `qa-engineer` subagent (local only).

**Repos:** root docs; `repos/my-plants-api`, `repos/my-plants-web` (already implemented in Phases 1-6).

---

### Task 1: Update architecture + local-development + roadmap docs

**Files:**
- Modify: `docs/architecture.md`, `docs/local-development.md`, `docs/mvp-roadmap.md`

- [ ] **Step 1: `docs/architecture.md`** — add an "Authentication / login wall" subsection: JWT + revocation blocklist; the `owner` seam now resolves the per-request actor from CLS (was hardcoded `"default"`); `users` 1:1 with `Owner` + `UserRole`; per-operation admin bypass; system jobs (cron/startup) are owner-agnostic (`applyAllDueMoves`); the public surface (`POST /auth/login`, `GET /species`, `GET /species/:slug/brief`) vs everything else protected. Note the BFF: browser ↔ Nitro only; token in a sealed `httpOnly` session (`secure` key); Nitro proxies to NestJS.

- [ ] **Step 2: `docs/local-development.md`** — add: new env vars (`JWT_SECRET`, `JWT_EXPIRES_IN` in API `.env`; `NUXT_SESSION_PASSWORD`, `NUXT_API_BASE` in web `.env`); apply migration `0006` with `npm run prisma:migrate`; create your account with `npm run user:create -- --username <u> --password <p> --role admin [--adopt-default]`; note that all routes require login except the blog.

- [ ] **Step 3: `docs/mvp-roadmap.md`** — mark the auth/login-wall milestone done; note deployment is the next prerequisite and still needs `docs/deploy.md` (not defined yet).

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.md docs/local-development.md docs/mvp-roadmap.md
git commit -m "docs: document the auth / login wall layer"
```

---

### Task 2: Leave the stack runnable (local only)

**Files:** local `.env` files (NOT committed), local DB.

- [ ] **Step 1: API env** — ensure `repos/my-plants-api/.env` has a real random `JWT_SECRET` (≥32 chars) and `JWT_EXPIRES_IN=30d`, plus the existing `DB_*`.

- [ ] **Step 2: Apply migration** — `cd repos/my-plants-api && npm run prisma:migrate` (idempotent if already applied in Phase 1).

- [ ] **Step 3: Web env** — ensure `repos/my-plants-web/.env` has `NUXT_SESSION_PASSWORD` (≥32 chars) and `NUXT_API_BASE=http://localhost:8000`.

- [ ] **Step 4: Create an admin user** — `cd repos/my-plants-api && set -a; source .env; set +a && npm run user:create -- --username carlos --password <chosen> --role admin --adopt-default` (adopt-default so the existing local seed data is visible under this account). Document the chosen credentials in the final summary to the user (local only).

- [ ] **Step 5: Boot** — from the workspace root run `./run.sh`; confirm API on :8000 and web on :8001 come up. Leave it running for the E2E task.

- [ ] **Step 6:** No commit (env/DB are local). Record in the plan output what was set.

---

### Task 3: E2E verification via the qa-engineer (local only)

- [ ] **Step 1: Dispatch the `qa-engineer` subagent** with a precise brief — what to test, how, expected results:
  1. **Login wall (web):** visiting `/` (or `/plants`) while logged out redirects to `/login`. Expected: redirect, no plant data leaked.
  2. **Login wall (API):** `GET http://localhost:8001/api/plants` with no session → `401`; `GET /api/species` with no session → `200` with the catalog (public).
  3. **Login works:** submit valid admin credentials at `/login` → lands on the app; protected pages load; the user's plants/places render (adopt-default data).
  4. **Ownership/admin:** (single user) confirm the logged-in admin sees the existing garden. (If a second non-admin user is created via `user:create` against a fresh owner, that user sees an empty garden — optional deeper check.)
  5. **Logout revokes:** after logout, navigating to a protected page redirects to `/login`; the prior session no longer accesses protected data.
  6. **Blog stays public:** `/blog` and a `/blog/[id]` article render WITHOUT logging in, and the article still renders Markdown.

- [ ] **Step 2: Triage findings.** For each red, diagnose root cause and fix it at the source (no workarounds, no faking state). Re-run the failing check through the real flow until green. Document every fix.

- [ ] **Step 3: Full regression** — run `./scripts/test-all.sh` (or per-repo `npm test` / `npm run build` + `npm run typecheck`). Expected: all green.

- [ ] **Step 4: Commit** any fixes made during E2E.

```bash
git add -A
git commit -m "fix(auth): address E2E findings"
```

---

### Task 4: Final code review gate (Codex, degrade to Claudex)

- [ ] **Step 1:** Run the implemented diff through Codex (`using-codex-workflow`); if Codex is rate-limited, degrade to Claudex (`using-claudex-workflow`). Hand it the full auth change across both repos + the spec. Iterate fixes until GREEN. (This is the constitution's "Final Code Review phase".)

- [ ] **Step 2:** Apply accepted findings at the root; re-review until GREEN. Document deferred items with rationale.

- [ ] **Step 3:** Final summary to the user: what was built, how to start testing (`./run.sh`, login at `/login` with the created admin, verify a protected page, logout, blog public), every autonomous decision + justification, and an explicit note that NOTHING was merged/pushed/pointer-bumped (awaiting explicit approval). Plus a `/compact` compaction prompt.
