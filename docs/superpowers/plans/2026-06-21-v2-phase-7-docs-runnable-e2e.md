# Enrichment v2 — Phase 7: Docs, runnable stack & E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document the new behaviour, leave the stack locally runnable with the migrations applied and a misting-beneficial species present, then verify the whole wave end-to-end with the qa-engineer and the full suite.

**Architecture:** Docs live in `docs/`. The DB must have its two new migrations applied and at least one species whose record exercises the new fields (humidity-sensitive + misting `beneficial`) so the features are visible. E2E acts as a real user via the qa-engineer subagent against `localhost`.

**Tech Stack:** Markdown docs; MariaDB; `./run.sh`; the qa-engineer subagent.

**Repos:** workspace root `docs/`, plus operational steps across all repos.

---

### Task 1: Update the docs

**Files:**
- Modify: `docs/care-engine.md`
- Modify: `docs/architecture.md`
- Modify: `repos/my-plants-knowledge-engine/CLAUDE.md` (already edited in Phase 2 — verify it reflects the editorial step)

- [ ] **Step 1: `docs/care-engine.md`** — add/update:
  - Watering now modulated by **ambient humidity** and by **indoor temperature**, governed by the "real signal" rule (a modulator is neutral unless there's a real reading). Indoor places with no provided data fall back to real outdoor weather; climate-controlled rooms stay at the comfort baseline.
  - The **misting** cycle: species-dependent (`beneficial`/`tolerated`/`avoid`) and humidity-graded per the DRY/NORMAL/HUMID table; not season-modulated; not part of punctuality learning.
  - The `humiditySensitivity` lever.

- [ ] **Step 2: `docs/architecture.md`** — note: the new schema sections (`misting`, `humiditySensitivity`), the `primaryCommonName` helper, the new `MIST` task + the nullable `humidityCharacter`, and the new `editorial-writer` subagent in the knowledge engine (researcher now writes one raw English brief; editorial-writer produces polished EN+ES).

- [ ] **Step 3: Commit (workspace root)**

```bash
git add docs/care-engine.md docs/architecture.md
git commit -m "docs: document climate-driven watering, misting cycle, editorial voice, friendly naming"
```

---

### Task 2: Apply migrations & confirm the stack boots

**Files:** none (operational).

- [ ] **Step 1: Confirm both migrations are applied** (created in Phases 3 & 4):

Run: `cd repos/my-plants-api && set -a; source .env; set +a && npx prisma migrate status`
Expected: `humidity_character_nullable` and `add_mist_task` listed as applied. If not, run `npx prisma migrate deploy`.

- [ ] **Step 2: Boot the whole stack**

Run (workspace root): `./run.sh`
Expected: api on :8000 and web on :8001 come up without errors. Leave it running for E2E, or stop and rely on the qa-engineer to start what it needs.

---

### Task 3: Ensure a misting-beneficial, humidity-sensitive species exists

**Files:** none in git (writes only to the DB via the real `db:insert`).

The default for stored species is `misting.benefit = 'avoid'` and `humiditySensitivity = 'low'`, so no existing species demonstrates the new features. Add one whose record exercises them — a classic humidity-loving, misting-friendly plant (e.g. *Nephrolepis exaltata*, Boston fern).

- [ ] **Step 1 (preferred): Run the real knowledge-engine flow** as the operator — invoke the `plant-researcher` then the `editorial-writer` subagents for "Nephrolepis exaltata", validate, and `db:insert`. This exercises the full new authoring path (single raw EN brief → editorial EN/ES) and naturally fills `humiditySensitivity` (high) and `misting` (beneficial).

- [ ] **Step 2 (fallback if the project subagents are not resolvable in this harness): author a valid curated draft and insert it through the REAL `db:insert`** (which re-validates — this is legitimate local test-data seeding, not an engine workaround). Create `nephrolepis-exaltata.draft.json` conforming to the schema with `watering.humiditySensitivity: "high"`, `humidity` favouring moist air, and:

```json
"misting": { "benefit": "beneficial", "baseFrequencyDays": 3, "note": "Loves leaf humidity; mist or use a pebble tray." }
```

plus a non-empty `commonNames: ["Boston fern", ...]`, then a short EN and ES brief file, and run:

```bash
cd repos/my-plants-knowledge-engine
set -a; source .env; set +a
npm run validate -- --record nephrolepis-exaltata.draft.json
npm run db:insert -- --record nephrolepis-exaltata.draft.json --brief-en nephrolepis-exaltata.en.draft.md --brief-es nephrolepis-exaltata.es.draft.md
rm -f nephrolepis-exaltata.*.draft.* nephrolepis-exaltata.draft.json
```

- [ ] **Step 3: Verify the species is queryable**

Run: `curl -s localhost:8000/species | grep -i nephrolepis` (or `db:find`).
Expected: the species is present with a common name.

---

### Task 4: E2E with the qa-engineer (LOCAL only)

**Files:** none (the qa-engineer may write its own scratch test files).

- [ ] **Step 1: Delegate to the `qa-engineer` subagent** with a precise brief — what to test, how, expected result:

  1. **Friendly naming:** on the plants list, a plant page, the add-plant species dropdown, the blog list, and a blog article, the **common name** is the primary label and the **scientific name** appears in italics. Create a plant of the misting-beneficial species in a **DRY indoor** place to test against.
  2. **Misting appears & clears:** for that plant in a DRY place, a **"Mist leaves"** task appears on the plant care page; after editing the place to **HUMID** (or creating a humid place and a plant there) and recomputing, the misting task does **not** appear for a humid placement. (Use the API `POST /care-plan/recompute` then reload.)
  3. **Humidity moves watering:** the same humidity-sensitive species waters sooner in a DRY place than in a HUMID place (compare `daysUntilDue`/`nextDueOn` on the care page or `GET /plants/:id/care`).
  4. **Permissive place + alert:** on the place create form, set Indoor and leave humidity "Not specified" and the temp range empty → the informational alert shows; the place still creates successfully (humidity stored null).
  5. **No regressions:** Today's view, Done/Postpone on a task, and the viability badge still work.

  Expected: all pass; API calls 2xx; no console errors.

- [ ] **Step 2: Triage the qa-engineer report.** Every red is either a real product bug (fix at root through the real flow, then re-run) or a brittle test (fix the test). Never mask. Re-run until green. Record findings for the final summary.

---

### Task 5: Full suite + final green

**Files:** none.

- [ ] **Step 1: Run the whole workspace suite**

Run (workspace root): `./scripts/test-all.sh`
Expected: schema, knowledge-engine, api all green; web build + typecheck green.

- [ ] **Step 2: Confirm the stack still boots cleanly** with `./run.sh` and the new species/features visible.

- [ ] **Step 3: Commit any test/doc fixes** discovered during E2E (per-repo, with the standard trailer). Do NOT merge/push/bump submodule pointers — that needs explicit user approval.

---

## Self-Review

- **Spec coverage:** docs updated ✓ Task 1; migrations applied ✓ Task 2; re-curation / misting-beneficial species ✓ Task 3; E2E across naming/misting/humidity/alert/regressions ✓ Task 4; full suite ✓ Task 5.
- **No workarounds:** the fallback seeding uses the real `db:insert` (validating) — legitimate local test data, not an engine bypass; real curation is preferred.
- **Autonomy boundary:** stops at "locally runnable + green"; no merge/push/pointer-bump/deploy.
