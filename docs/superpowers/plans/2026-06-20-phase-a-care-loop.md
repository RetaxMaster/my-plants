# Phase A — Care Loop (learning + mark-done) — Implementation Plan

**Goal:** Make the care engine learn from *early* waterings (asymmetric, safety-biased) and let the
owner mark any applicable task **Done** (with optional back-dating) and **Postpone** directly from the
plant page. This delivers the spec's Phase A (A.1–A.5) plus the cross-cutting **Startup recompute**
hook. Source of truth: `docs/superpowers/specs/2026-06-20-mvp-enrichment-design.md` (read Phase A and
"Cross-cutting: Startup recompute").

**Architecture:** Two repos under the workspace.
- `repos/my-plants-api` — NestJS + Prisma + MariaDB. The deterministic care engine lives in pure
  modules under `src/engines/*` (no DB), orchestrated by services under feature folders
  (`src/feedback`, `src/care-plan`, …). Day boundaries and date math live in `src/common/time/*`.
  Adherence per cycle is persisted in the existing `CareEvent.payload` JSON column — **no migration**.
- `repos/my-plants-web` — Nuxt 3 + Vue 3 (Nuxt UI). API access is centralized in
  `composables/useApi.ts`; response shapes in `types/api.ts`. The plant page is `pages/plants/[id].vue`.

**Tech Stack:** TypeScript (ESM throughout — every relative import ends in `.js`), NestJS 10,
Prisma (MySQL/MariaDB, snake_case via `@map`), Vitest (`npm test` = `vitest run`) for API unit tests,
Nuxt 3 + `@nuxt/ui` for web (verified with `npm run build` for the build and `npm run typecheck` =
`nuxt typecheck`/vue-tsc for type errors — `npm run build` alone does NOT typecheck because
`typescript.typeCheck` is off in `nuxt.config.ts`). Owner scoping is done
via `OwnerService.currentOwnerId()`. **MariaDB date rule:** day differences are computed on `@db.Date`
(UTC-midnight) values as integer day counts — **never** compare against `toISOString()` strings.

---

## For agentic workers

**REQUIRED SUB-SKILL: Before doing ANYTHING else, read and follow `~/.claude/skills/superpowers/skills/testing/test-driven-development/SKILL.md` (or the project's equivalent TDD skill). Use the RED → GREEN → REFACTOR loop for every task below: write a failing test first, watch it fail, write the minimal code to pass, watch it pass, then commit.**

Rules for this plan:
- **One repo per change set.** API work happens inside `repos/my-plants-api`; web work inside
  `repos/my-plants-web`. Run all commands from inside the relevant repo (the agent's cwd resets
  between bash calls — always `cd` into the repo first in each command).
- **ESM imports:** every relative import path ends in `.js` even for `.ts` files. Match the existing style.
- **Commits:** Conventional Commits, imperative, English. Commit after every GREEN step. Do **not**
  merge, push, or bump submodule pointers in this plan (that is the workspace feature-workflow's
  closing step, done later with explicit approval).
- **No `.env` writes.** No new env vars are introduced by Phase A.
- **Pure-first testing discipline:** anything that can be expressed as a pure function (date math,
  the early-signal scorer, the adaptation formula) gets a focused Vitest unit test. DB-touching
  orchestration (the feedback sequence, the new endpoint, the startup hook) is verified by extracting
  pure helpers where possible and by a documented **manual verification** against the local stack, run
  through the real, unmodified code path.

### Phase A task checklist

- [ ] Task 1 — `dayDiff` helper on `common/time/local-date.ts`
- [ ] Task 2 — pure `computeEarlyRatio` in `engines/punctuality.ts`
- [ ] Task 3 — convergent, early-only `nextAdjustment` in `engines/adaptation.ts`
- [ ] Task 4 — DONE-on-WATER adherence + adapt sequence in `feedback.service.ts`
- [ ] Task 5 — `GET /plants/:id/care` endpoint (owner-scoped, on-demand recompute)
- [ ] Task 6 — Startup recompute provider (`OnApplicationBootstrap`)
- [ ] Task 7 — Frontend care panel on `pages/plants/[id].vue` (+ `useApi` + types)

---

## Shared contract (use these EXACT names — other phases' plans depend on them)

```ts
// types/api.ts (web)  — viability is added later in Phase C; leave the seam now.
export type PlantCare = {
  plantId: string;
  tasks: {
    task: TaskCode;
    nextDueOn: string;          // YYYY-MM-DD
    daysUntilDue: number;       // <0 overdue, 0 today, >0 upcoming
    status: 'overdue' | 'today' | 'upcoming';
  }[];
  viability?: { level: 'good' | 'caution' | 'poor'; reasons: string[] };  // ADDED IN PHASE C
};

// composables/useApi.ts (web)
api.getPlantCare(id: string) => api<PlantCare>(`/plants/${id}/care`)
```

The DONE/POSTPONE feedback endpoint already exists and is unchanged:
`POST /plants/:id/feedback` with body `{ task, type: 'DONE', occurredOn }` or
`{ task, type: 'POSTPONED', occurredOn, postponeToOn }`.

> **Phase C seam (do NOT implement here):** the `GET /plants/:id/care` response will gain a top-level
> `viability` field in Phase C. In this phase the endpoint returns only `{ plantId, tasks }`, and the
> web `PlantCare` type already declares `viability?` as optional so the contract is forward-compatible.
> Build the controller/service so adding `viability` later is a pure addition (a new field on the
> returned object), not a reshape.

---

## Task 1 — `dayDiff(a, b)` integer day count on `@db.Date` values

Adds the date-math primitive the whole learning loop depends on, obeying the MariaDB rule (no ISO strings).

**Files**
- Modify: `repos/my-plants-api/src/common/time/local-date.ts` (append after line 26)
- Modify: `repos/my-plants-api/src/common/time/local-date.test.ts` (extend the existing test file)

**Steps**

- [ ] **Write the failing test.** Append a new `describe` block to
  `repos/my-plants-api/src/common/time/local-date.test.ts`:

```ts
import { startOfTodayUtc, startOfTomorrowUtc, dayDiff } from './local-date.js';

// ...existing describe stays unchanged above...

describe('dayDiff on @db.Date (UTC-midnight) values', () => {
  const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);

  it('counts whole days between two UTC-midnight dates', () => {
    expect(dayDiff(day('2026-06-20'), day('2026-06-13'))).toBe(7);
  });

  it('is signed: a before b yields a negative count', () => {
    expect(dayDiff(day('2026-06-13'), day('2026-06-20'))).toBe(-7);
  });

  it('returns 0 for the same calendar day', () => {
    expect(dayDiff(day('2026-06-20'), day('2026-06-20'))).toBe(0);
  });

  it('rounds across a DST-style sub-day skew to the nearest whole day', () => {
    // Even if a stored value is off by a few hours, round() snaps to the day count.
    expect(dayDiff(new Date('2026-06-20T01:00:00.000Z'), day('2026-06-13'))).toBe(7);
  });
});
```

- [ ] **Run it — expect FAIL** (the import `dayDiff` does not exist yet → `vitest` reports it as
  undefined / not a function):

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm test -- src/common/time/local-date.test.ts
```
Expected: the new `dayDiff` cases FAIL (the existing boundary cases still pass).

- [ ] **Minimal implementation.** Append to `repos/my-plants-api/src/common/time/local-date.ts`:

```ts
// Integer day count between two @db.Date (UTC-midnight) values: round((a - b) / 86_400_000).
// Signed (a before b → negative). Never uses toISOString — the MariaDB date rule. round() absorbs
// any sub-day skew (e.g. a value stored a few hours off midnight) into the nearest whole day.
export function dayDiff(a: Date, b: Date): number {
  return Math.round((a.getTime() - b.getTime()) / 86_400_000);
}
```

- [ ] **Run it — expect PASS:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm test -- src/common/time/local-date.test.ts
```
Expected: all cases (existing + new) PASS.

- [ ] **Commit:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && git add src/common/time/local-date.ts src/common/time/local-date.test.ts && git commit -m "feat(time): add dayDiff integer day-count helper on @db.Date values"
```

---

## Task 2 — pure `computeEarlyRatio` in `engines/punctuality.ts`

The early-signal scorer (spec A.3). Pure, DB-free, unit-tested across every branch. This is the
confidence gate that makes the loop converge instead of ratcheting to the floor.

**Files**
- Create: `repos/my-plants-api/src/engines/punctuality.ts`
- Create: `repos/my-plants-api/src/engines/punctuality.test.ts`

**Steps**

- [ ] **Write the failing test.** Create `repos/my-plants-api/src/engines/punctuality.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { computeEarlyRatio, type AdherenceCycle } from './punctuality.js';

const cycle = (observedDays: number, scheduledDays: number): AdherenceCycle => ({ observedDays, scheduledDays });

describe('computeEarlyRatio', () => {
  it('returns 1 when there are no cycles', () => {
    expect(computeEarlyRatio([], { deadband: 0.1, minSamples: 2 })).toBe(1);
  });

  it('returns 1 when only one cycle is early (below the minSamples confidence gate)', () => {
    // newest early, but only 1 early cycle total → gate not met.
    const cycles = [cycle(6, 10), cycle(10, 10), cycle(11, 10)];
    expect(computeEarlyRatio(cycles, { deadband: 0.1, minSamples: 2 })).toBe(1);
  });

  it('returns the NEWEST cycle ratio when the gate passes and the newest cycle is early', () => {
    // newest-first; two cycles early (6/10 and 7/10), gate met (>=2), newest is early.
    const cycles = [cycle(6, 10), cycle(7, 10), cycle(10, 10)];
    expect(computeEarlyRatio(cycles, { deadband: 0.1, minSamples: 2 })).toBeCloseTo(0.6, 5);
  });

  it('returns 1 when the gate passes but the NEWEST cycle is NOT early', () => {
    // two older cycles early, but newest (10/10) is on-time → no nudge.
    const cycles = [cycle(10, 10), cycle(6, 10), cycle(7, 10)];
    expect(computeEarlyRatio(cycles, { deadband: 0.1, minSamples: 2 })).toBe(1);
  });

  it('respects the deadband: a cycle just inside the band is NOT early', () => {
    // 9.5/10 = 0.95 > 1 - 0.1 = 0.9 → not early; even repeated it never trips the gate.
    const cycles = [cycle(9.5, 10), cycle(9.5, 10), cycle(9.5, 10)];
    expect(computeEarlyRatio(cycles, { deadband: 0.1, minSamples: 2 })).toBe(1);
  });

  it('applies default deadband=0.1 and minSamples=2 when options are omitted', () => {
    const cycles = [cycle(6, 10), cycle(7, 10)];
    expect(computeEarlyRatio(cycles)).toBeCloseTo(0.6, 5);
  });
});
```

- [ ] **Run it — expect FAIL** (module does not exist):

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm test -- src/engines/punctuality.test.ts
```
Expected: FAIL — cannot resolve `./punctuality.js`.

- [ ] **Minimal implementation.** Create `repos/my-plants-api/src/engines/punctuality.ts`:

```ts
// Pure early-signal scorer (spec A.3). Input cycles are the recent ELIGIBLE adherence records for
// (plant, WATER), newest first. Late/on-time cycles never push the cadence — early only.
export interface AdherenceCycle {
  observedDays: number;  // actual interval since the previous anchor
  scheduledDays: number; // interval the schedule predicted for that cycle
}

export interface EarlyRatioOptions {
  deadband: number;   // a cycle counts as "early" only below scheduled * (1 - deadband)
  minSamples: number; // confidence gate: at least this many recent cycles must be early
}

const DEFAULTS: EarlyRatioOptions = { deadband: 0.1, minSamples: 2 };

// Returns the NEWEST eligible cycle's ratio (observed/scheduled, < 1) when BOTH hold:
//   (1) at least minSamples of the recent cycles are early (confidence gate), AND
//   (2) the newest cycle itself is early.
// Otherwise returns 1 (no change). The window is ONLY a confidence gate — never an averaged value
// re-applied each event (that is the ratchet-to-floor design the spec explicitly rejects).
export function computeEarlyRatio(
  cycles: AdherenceCycle[],
  options: EarlyRatioOptions = DEFAULTS,
): number {
  const { deadband, minSamples } = options;
  if (cycles.length === 0) return 1;

  const isEarly = (c: AdherenceCycle): boolean => c.observedDays < c.scheduledDays * (1 - deadband);

  const earlyCount = cycles.filter(isEarly).length;
  if (earlyCount < minSamples) return 1;

  const newest = cycles[0];
  if (!isEarly(newest)) return 1;

  return newest.observedDays / newest.scheduledDays;
}
```

- [ ] **Run it — expect PASS:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm test -- src/engines/punctuality.test.ts
```
Expected: all 6 cases PASS.

- [ ] **Commit:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && git add src/engines/punctuality.ts src/engines/punctuality.test.ts && git commit -m "feat(engine): add pure computeEarlyRatio confidence-gated early signal"
```

---

## Task 3 — convergent, early-only `nextAdjustment`

Reshape the adaptation formula (spec A.4): the cadence nudge fires **only when early**, at **reduced
gain** (`EARLY_GAIN = 0.15`, down from the old symmetric `0.3`). Postpone behavior is unchanged.

**Files**
- Modify: `repos/my-plants-api/src/engines/adaptation.ts` (lines 9–14)
- Modify: `repos/my-plants-api/src/engines/adaptation.test.ts` (extend existing tests)

**Steps**

- [ ] **Write the failing tests.** Replace the body of
  `repos/my-plants-api/src/engines/adaptation.test.ts` with the existing cases plus the new
  early-only and convergence cases:

```ts
import { describe, expect, it } from 'vitest';
import { nextAdjustment } from './adaptation.js';

describe('nextAdjustment', () => {
  it('keeps the multiplier when there is no signal', () => {
    expect(nextAdjustment({ current: 1, recentPostpones: 0, earlyLateRatio: 1 })).toBeCloseTo(1, 5);
  });

  it('lengthens the interval after repeated postpones', () => {
    expect(nextAdjustment({ current: 1, recentPostpones: 3, earlyLateRatio: 1 })).toBeGreaterThan(1);
  });

  it('shortens when the owner acts early (ratio < 1)', () => {
    expect(nextAdjustment({ current: 1, recentPostpones: 0, earlyLateRatio: 0.7 })).toBeLessThan(1);
  });

  it('does NOT lengthen on a late cycle (ratio > 1 → no cadence change)', () => {
    // Early-only policy: late waterings are forgetfulness, not a signal.
    expect(nextAdjustment({ current: 1, recentPostpones: 0, earlyLateRatio: 1.4 })).toBeCloseTo(1, 5);
  });

  it('applies reduced gain: ratio 0.7 nudges by (0.7-1)*0.15 = -0.045', () => {
    expect(nextAdjustment({ current: 1, recentPostpones: 0, earlyLateRatio: 0.7 })).toBeCloseTo(0.955, 5);
  });

  it('clamps within [0.5, 2]', () => {
    expect(nextAdjustment({ current: 2, recentPostpones: 10, earlyLateRatio: 1 })).toBeLessThanOrEqual(2);
    expect(nextAdjustment({ current: 0.5, recentPostpones: 0, earlyLateRatio: 0.1 })).toBeGreaterThanOrEqual(0.5);
  });

  it('CONVERGES: a consistently-early waterer settles and does NOT slide to the 0.5 floor', () => {
    // The owner waters every ~7 days. The schedule (= base 10 * multiplier) shrinks each DONE; once
    // it reaches the owner's real rhythm the cycle stops being early (ratio enters the deadband),
    // so the nudge stops. Simulate the loop and assert it settles well above the floor.
    const baseSchedule = 10; // days the schedule predicts at multiplier 1
    const ownerInterval = 7; // the owner's true rhythm
    let multiplier = 1;
    for (let i = 0; i < 50; i++) {
      const scheduledDays = baseSchedule * multiplier;
      const ratio = ownerInterval / scheduledDays;
      // mirror computeEarlyRatio's gate: only nudge while the newest cycle is early (deadband 0.1).
      const earlyLateRatio = ratio < 1 - 0.1 ? ratio : 1;
      multiplier = nextAdjustment({ current: multiplier, recentPostpones: 0, earlyLateRatio });
    }
    // Settles near 7/10 = 0.7 (where scheduled ≈ owner interval), NOT pinned at the 0.5 floor.
    expect(multiplier).toBeGreaterThan(0.6);
    expect(multiplier).toBeLessThan(0.85);
  });
});
```

- [ ] **Run it — expect FAIL** (old symmetric formula lengthens on `ratio > 1` and uses gain `0.3`,
  so the "no lengthen on late", "reduced gain", and "converges" cases fail):

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm test -- src/engines/adaptation.test.ts
```
Expected: the three new cases FAIL.

- [ ] **Minimal implementation.** Edit `repos/my-plants-api/src/engines/adaptation.ts`, replacing the
  comment + `nextAdjustment` body (lines 9–14):

```ts
const EARLY_GAIN = 0.15; // reduced gain: acting early shortens weakly. Late is NOT a signal (A.1).

// Small, bounded nudges so the plan adapts gradually rather than oscillating. The cadence nudge is
// EARLY-ONLY (ratio < 1); ratio >= 1 contributes nothing — late waterings never lengthen the rhythm.
export function nextAdjustment(i: AdaptationInput): number {
  const postponeNudge = i.recentPostpones * 0.05; // each postpone lengthens slightly
  const cadenceNudge = i.earlyLateRatio < 1 ? (i.earlyLateRatio - 1) * EARLY_GAIN : 0;
  return clamp(i.current + postponeNudge + cadenceNudge, 0.5, 2);
}
```

Also update the `earlyLateRatio` doc comment on `AdaptationInput` (line 4) to reflect the new
semantics:

```ts
  earlyLateRatio: number; // newest eligible cycle's observed/scheduled (< 1 = early); 1 = no signal
```

- [ ] **Run it — expect PASS:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm test -- src/engines/adaptation.test.ts
```
Expected: all cases PASS, including the convergence case.

- [ ] **Commit:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && git add src/engines/adaptation.ts src/engines/adaptation.test.ts && git commit -m "feat(engine): make cadence nudge early-only with reduced gain (convergent loop)"
```

---

## Task 4 — DONE-on-WATER adherence capture + adapt sequence

Implement the exact 6-step sequence from spec A.2 in `feedback.service.record`. The adherence reads
MUST happen **before** the override is deleted (an active override is the postpone signal). A pure
helper is extracted for the eligibility math so it is unit-tested; the DB glue is verified manually.

**Files**
- Create: `repos/my-plants-api/src/feedback/adherence.ts` (pure helper)
- Create: `repos/my-plants-api/src/feedback/adherence.test.ts`
- Modify: `repos/my-plants-api/src/feedback/feedback.service.ts` (the `record` method, lines 13–51, and a new private method)

### 4a — pure adherence helper (TDD)

- [ ] **Write the failing test.** Create `repos/my-plants-api/src/feedback/adherence.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { computeAdherence, eligibleCycles, type AdherencePayload } from './adherence.js';

const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);

describe('computeAdherence', () => {
  it('builds an eligible adherence record for a normal cycle', () => {
    const a = computeAdherence({
      occurredOn: day('2026-06-20'),
      previousAnchor: day('2026-06-13'),
      scheduledDueOn: day('2026-06-23'),
      hadOverride: false,
    });
    expect(a).toEqual({
      previousAnchorOn: day('2026-06-13'),
      scheduledDueOn: day('2026-06-23'),
      observedDays: 7,
      scheduledDays: 10,
      eligible: true,
    });
  });

  it('is ineligible when an override was active (postponed cycle)', () => {
    const a = computeAdherence({
      occurredOn: day('2026-06-20'),
      previousAnchor: day('2026-06-13'),
      scheduledDueOn: day('2026-06-23'),
      hadOverride: true,
    });
    expect(a.eligible).toBe(false);
  });

  it('is ineligible for a same-day / back-dated DONE (observedDays < 1)', () => {
    const a = computeAdherence({
      occurredOn: day('2026-06-13'),
      previousAnchor: day('2026-06-13'),
      scheduledDueOn: day('2026-06-23'),
      hadOverride: false,
    });
    expect(a.eligible).toBe(false);
  });

  it('is ineligible when scheduledDays < 1', () => {
    const a = computeAdherence({
      occurredOn: day('2026-06-20'),
      previousAnchor: day('2026-06-13'),
      scheduledDueOn: day('2026-06-13'),
      hadOverride: false,
    });
    expect(a.eligible).toBe(false);
  });

  it('returns null when there is no due-cache row (scheduledDueOn = null)', () => {
    const a = computeAdherence({
      occurredOn: day('2026-06-20'),
      previousAnchor: day('2026-06-13'),
      scheduledDueOn: null,
      hadOverride: false,
    });
    expect(a).toBeNull();
  });
});

describe('eligibleCycles', () => {
  it('keeps only eligible adherence payloads, in input order (newest first)', () => {
    const payloads: (AdherencePayload | undefined)[] = [
      { previousAnchorOn: day('2026-06-13'), scheduledDueOn: day('2026-06-23'), observedDays: 7, scheduledDays: 10, eligible: true },
      undefined,
      { previousAnchorOn: day('2026-06-01'), scheduledDueOn: day('2026-06-11'), observedDays: 6, scheduledDays: 10, eligible: false },
      { previousAnchorOn: day('2026-05-20'), scheduledDueOn: day('2026-05-30'), observedDays: 8, scheduledDays: 10, eligible: true },
    ];
    expect(eligibleCycles(payloads)).toEqual([
      { observedDays: 7, scheduledDays: 10 },
      { observedDays: 8, scheduledDays: 10 },
    ]);
  });
});
```

- [ ] **Run it — expect FAIL** (module missing):

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm test -- src/feedback/adherence.test.ts
```
Expected: FAIL — cannot resolve `./adherence.js`.

- [ ] **Minimal implementation.** Create `repos/my-plants-api/src/feedback/adherence.ts`:

```ts
import { dayDiff } from '../common/time/local-date.js';
import type { AdherenceCycle } from '../engines/punctuality.js';

// Stamped into CareEvent.payload.adherence for each closed DONE-on-WATER cycle (spec A.2).
export interface AdherencePayload {
  previousAnchorOn: Date;
  scheduledDueOn: Date;
  observedDays: number;
  scheduledDays: number;
  eligible: boolean;
}

// Pure eligibility math. Returns null only when there is no schedule to measure against
// (no due-cache row). Otherwise returns the record with `eligible` set per the A.2 guards:
// eligible = !hadOverride && scheduledDays >= 1 && observedDays >= 1.
export function computeAdherence(input: {
  occurredOn: Date;
  previousAnchor: Date;
  scheduledDueOn: Date | null;
  hadOverride: boolean;
}): AdherencePayload | null {
  if (input.scheduledDueOn === null) return null;
  const observedDays = dayDiff(input.occurredOn, input.previousAnchor);
  const scheduledDays = dayDiff(input.scheduledDueOn, input.previousAnchor);
  const eligible = !input.hadOverride && scheduledDays >= 1 && observedDays >= 1;
  return {
    previousAnchorOn: input.previousAnchor,
    scheduledDueOn: input.scheduledDueOn,
    observedDays,
    scheduledDays,
    eligible,
  };
}

// Filters a newest-first list of parsed payloads down to the eligible cycles the scorer consumes.
export function eligibleCycles(payloads: (AdherencePayload | undefined)[]): AdherenceCycle[] {
  return payloads
    .filter((p): p is AdherencePayload => p !== undefined && p.eligible)
    .map((p) => ({ observedDays: p.observedDays, scheduledDays: p.scheduledDays }));
}
```

- [ ] **Run it — expect PASS:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm test -- src/feedback/adherence.test.ts
```
Expected: all cases PASS.

- [ ] **Commit:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && git add src/feedback/adherence.ts src/feedback/adherence.test.ts && git commit -m "feat(feedback): add pure adherence eligibility + cycle-filter helpers"
```

### 4b — integrate the 6-step sequence into `feedback.service.ts`

- [ ] **Implement the sequence.** Edit `repos/my-plants-api/src/feedback/feedback.service.ts`. Update
  the imports at the top:

```ts
import { Injectable } from '@nestjs/common';
import { Prisma, type CareEventType, type Task } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service.js';
import { CarePlanService } from '../care-plan/care-plan.service.js';
import { nextAdjustment } from '../engines/adaptation.js';
import { computeEarlyRatio } from '../engines/punctuality.js';
import { computeAdherence, eligibleCycles, type AdherencePayload } from './adherence.js';
```

  Replace the `record` method (current lines 13–51) with the version that runs the exact A.2
  ordering. The key invariant: read `previousAnchor`, `scheduledDueOn`, and `hadOverride` **before**
  any write, and adapt **only** when the just-closed cycle is eligible:

```ts
  async record(input: {
    plantId: string;
    task: Task;
    type: CareEventType;
    occurredOn: Date;
    postponeToOn?: Date;
    payload?: unknown;
  }): Promise<void> {
    // DONE-on-WATER closes a punctuality cycle (spec A.2). Capture adherence BEFORE any write —
    // an active override here is precisely the "this cycle was postponed" signal; deleting it first
    // would make every cycle look eligible (the double-count A.1 forbids).
    let adherence: AdherencePayload | null = null;
    if (input.type === 'DONE' && input.task === 'WATER') {
      // (1) read previousAnchor, current scheduled due, and whether an override is active.
      const previous = await this.prisma.careEvent.findFirst({
        where: { plantId: input.plantId, task: 'WATER', type: 'DONE' },
        orderBy: [{ occurredOn: 'desc' }, { createdAt: 'desc' }],
        select: { occurredOn: true },
      });
      const previousAnchor = previous?.occurredOn ?? (await this.prisma.plant.findUniqueOrThrow({
        where: { id: input.plantId },
        select: { acquiredOn: true },
      })).acquiredOn;
      const dueRow = await this.prisma.dueCache.findUnique({
        where: { plantId_task: { plantId: input.plantId, task: 'WATER' } },
        select: { nextDueOn: true },
      });
      const hadOverride = (await this.prisma.taskOverride.count({
        where: { plantId: input.plantId, task: 'WATER' },
      })) > 0;
      // (2) compute observed/scheduled days + eligibility.
      adherence = computeAdherence({
        occurredOn: input.occurredOn,
        previousAnchor,
        scheduledDueOn: dueRow?.nextDueOn ?? null,
        hadOverride,
      });
    }

    // (3) create the event, merging adherence into the client payload (keeps previousAnchor
    //     uncontaminated by this new event because we read it in step 1).
    const mergedPayload =
      adherence !== null
        ? { ...(input.payload as Record<string, unknown> | undefined), adherence }
        : input.payload;
    await this.prisma.careEvent.create({
      data: {
        plantId: input.plantId,
        task: input.task,
        type: input.type,
        occurredOn: input.occurredOn,
        ...(mergedPayload === undefined
          ? {}
          : { payload: mergedPayload as Prisma.InputJsonValue }),
      },
    });

    if (input.type === 'DONE') {
      // (4) delete the override (existing DONE behaviour).
      await this.prisma.taskOverride.deleteMany({ where: { plantId: input.plantId, task: input.task } });
      // (5) adapt ONLY if the just-closed cycle is eligible — exactly one nudge per eligible cycle.
      if (adherence !== null && adherence.eligible) {
        await this.adaptFromPunctuality(input.plantId);
      }
    }

    if (input.type === 'POSTPONED' && input.postponeToOn) {
      await this.prisma.taskOverride.upsert({
        where: { plantId_task: { plantId: input.plantId, task: input.task } },
        create: { plantId: input.plantId, task: input.task, nextDueOn: input.postponeToOn },
        update: { nextDueOn: input.postponeToOn },
      });
      await this.adapt(input.plantId, input.task);
    }

    if (input.type === 'SYMPTOM') {
      await this.adaptForSymptom(input.plantId, input.payload);
    }

    // (6) recompute the plant (existing behaviour).
    await this.carePlan.recomputePlant(input.plantId);
  }
```

  Then add the new private method (the non-pure glue: fetch recent DONE WATER events, parse + filter
  eligible payloads **in JS**, score with the pure function, upsert). Place it next to the existing
  `adapt` method:

```ts
  // DONE-path WATER adaptation: read the recent window, score the early signal with the pure
  // function, persist the multiplier. recentPostpones = 0 (postpones adapt on their own events).
  private async adaptFromPunctuality(plantId: string): Promise<void> {
    const recent = await this.prisma.careEvent.findMany({
      where: { plantId, task: 'WATER', type: 'DONE' },
      orderBy: [{ occurredOn: 'desc' }, { createdAt: 'desc' }],
      take: 5,
      select: { payload: true },
    });
    // Parse adherence out of each payload IN JS (not MySQL JSON-path, which is brittle), newest first.
    const cycles = eligibleCycles(
      recent.map((e) => {
        const adherence = (e.payload as { adherence?: AdherencePayload } | null)?.adherence;
        return adherence
          ? {
              ...adherence,
              previousAnchorOn: new Date(adherence.previousAnchorOn),
              scheduledDueOn: new Date(adherence.scheduledDueOn),
            }
          : undefined;
      }),
    );
    const ratio = computeEarlyRatio(cycles, { deadband: 0.1, minSamples: 2 });
    const current = (await this.prisma.plantTaskAdjustment.findUnique({
      where: { plantId_task: { plantId, task: 'WATER' } },
    }))?.multiplier ?? 1;
    const multiplier = nextAdjustment({ current, recentPostpones: 0, earlyLateRatio: ratio });
    await this.prisma.plantTaskAdjustment.upsert({
      where: { plantId_task: { plantId, task: 'WATER' } },
      create: { plantId, task: 'WATER', multiplier },
      update: { multiplier },
    });
  }
```

> **Why `eligibleCycles` re-wraps dates:** values read back from a JSON column arrive as strings, not
> `Date`s. `computeEarlyRatio` only reads `observedDays`/`scheduledDays` (plain numbers stored in the
> payload), so re-hydrating the dates is defensive/forward-safe; the numbers are authoritative.

- [ ] **Verify it compiles + the whole suite stays green:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm run build && npm test
```
Expected: build succeeds (TypeScript clean), all unit tests PASS (Tasks 1–3 + adherence helper).

- [ ] **Manual verification (real path, local stack).** This is DB-touching orchestration with no
  service-level unit harness in the repo, so verify against the running stack through the unmodified
  endpoint. Ensure the stack is up (`./run.sh` from the workspace root) with at least one plant that
  has a WATER due date. Then exercise the real DONE path twice to close two early cycles:

```bash
# Replace <PLANT_ID> with a real owned plant id (GET http://localhost:8000/plants).
# Pick occurredOn dates that are EARLY vs the plant's scheduled WATER due (observed < scheduled*0.9).
curl -s -X POST http://localhost:8000/plants/<PLANT_ID>/feedback \
  -H 'content-type: application/json' \
  -d '{"task":"WATER","type":"DONE","occurredOn":"2026-06-14"}'
curl -s -X POST http://localhost:8000/plants/<PLANT_ID>/feedback \
  -H 'content-type: application/json' \
  -d '{"task":"WATER","type":"DONE","occurredOn":"2026-06-20"}'
```

  Confirm in MariaDB (read-only): the two `care_events` rows carry `payload.adherence` with
  `observedDays`/`scheduledDays`/`eligible`, and that `plant_task_adjustments.multiplier` for
  `(plant, WATER)` dropped **below 1** only after two eligible early cycles (a single early DONE must
  leave it at 1 — the confidence gate). Also do one POSTPONED DONE and confirm that closed cycle is
  stamped `eligible: false` and does NOT move the multiplier. Document the observed values in the
  commit body or the session summary. If anything is off, fix the root cause (do not work around it).

- [ ] **Commit:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && git add src/feedback/feedback.service.ts && git commit -m "feat(feedback): capture adherence and adapt WATER cadence on eligible early DONEs"
```

---

## Task 5 — `GET /plants/:id/care` endpoint (owner-scoped, on-demand recompute)

The read model that powers the plant page. **This phase returns only `{ plantId, tasks }`.** The
`status`/`daysUntilDue` are computed server-side in the owner's primary-city timezone. If the due
cache is empty for the plant, recompute it on demand first.

> **Phase C seam:** Phase C will ADD a `viability` field to this same response. Build the service so
> that is a pure addition. Do **not** implement viability here.

**Files**
- Create: `repos/my-plants-api/src/plants/plant-care.ts` (pure status/daysUntilDue helper)
- Create: `repos/my-plants-api/src/plants/plant-care.test.ts`
- Modify: `repos/my-plants-api/src/plants/plants.service.ts` (new `getCare` method + deps)
- Modify: `repos/my-plants-api/src/plants/plants.controller.ts` (new route)
- Modify: `repos/my-plants-api/src/plants/plants.module.ts` (import `CarePlanModule`)

### 5a — pure status helper (TDD)

- [ ] **Write the failing test.** Create `repos/my-plants-api/src/plants/plant-care.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { careTaskStatus } from './plant-care.js';

const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);

describe('careTaskStatus', () => {
  const today = day('2026-06-20'); // startOfTodayUtc(tz) result

  it('marks a past due date as overdue with a negative count', () => {
    expect(careTaskStatus(day('2026-06-18'), today)).toEqual({ daysUntilDue: -2, status: 'overdue' });
  });

  it('marks the same day as today with zero', () => {
    expect(careTaskStatus(day('2026-06-20'), today)).toEqual({ daysUntilDue: 0, status: 'today' });
  });

  it('marks a future due date as upcoming with a positive count', () => {
    expect(careTaskStatus(day('2026-06-25'), today)).toEqual({ daysUntilDue: 5, status: 'upcoming' });
  });
});
```

- [ ] **Run it — expect FAIL** (module missing):

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm test -- src/plants/plant-care.test.ts
```
Expected: FAIL — cannot resolve `./plant-care.js`.

- [ ] **Minimal implementation.** Create `repos/my-plants-api/src/plants/plant-care.ts`:

```ts
import { dayDiff } from '../common/time/local-date.js';

export type CareStatus = 'overdue' | 'today' | 'upcoming';

// Pure: daysUntilDue/status of a @db.Date due relative to startOfTodayUtc(tz). Computed on the
// backend so the client never subtracts a UTC-midnight date from a local now (off-by-one at midnight).
export function careTaskStatus(
  nextDueOn: Date,
  startOfToday: Date,
): { daysUntilDue: number; status: CareStatus } {
  const daysUntilDue = dayDiff(nextDueOn, startOfToday);
  const status: CareStatus = daysUntilDue < 0 ? 'overdue' : daysUntilDue === 0 ? 'today' : 'upcoming';
  return { daysUntilDue, status };
}
```

- [ ] **Run it — expect PASS:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm test -- src/plants/plant-care.test.ts
```
Expected: all cases PASS.

- [ ] **Commit:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && git add src/plants/plant-care.ts src/plants/plant-care.test.ts && git commit -m "feat(plants): add pure care-task status/daysUntilDue helper"
```

### 5b — service + controller + module wiring

- [ ] **Add the `getCare` method.** Edit `repos/my-plants-api/src/plants/plants.service.ts`. Update
  the constructor/imports to inject `CarePlanService` and reach the primary-city timezone, and add the
  method. New imports at the top:

```ts
import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { OwnerService } from '../owner/owner.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { CarePlanService } from '../care-plan/care-plan.service.js';
import { startOfTodayUtc } from '../common/time/local-date.js';
import { careTaskStatus, type CareStatus } from './plant-care.js';
import type { Task } from '@prisma/client';
import type { CreatePlantDto } from './create-plant.dto.js';
```

  Constructor:

```ts
  constructor(
    private readonly prisma: PrismaService,
    private readonly owner: OwnerService,
    private readonly carePlan: CarePlanService,
  ) {}
```

  Add the return type + method (the response is `{ plantId, tasks }` — leave the Phase C `viability`
  seam by keeping the shape additive):

```ts
  // Read model for the plant page (spec A.5 / C.2). Phase A returns { plantId, tasks }; Phase C will
  // ADD a top-level `viability` field to this same object (pure addition — do not reshape this).
  async getCare(id: string): Promise<{
    plantId: string;
    tasks: { task: Task; nextDueOn: string; daysUntilDue: number; status: CareStatus }[];
  }> {
    const ownerId = await this.owner.currentOwnerId();
    const plant = await this.prisma.plant.findFirst({ where: { id, ownerId } });
    if (!plant) throw new NotFoundException(`Unknown plant: ${id}`);

    // If the cache is empty (e.g. plant created before any recompute), recompute on demand so the
    // page is never spuriously empty.
    let due = await this.prisma.dueCache.findMany({
      where: { plantId: id },
      select: { task: true, nextDueOn: true },
      orderBy: { nextDueOn: 'asc' },
    });
    if (due.length === 0) {
      await this.carePlan.recomputePlant(id);
      due = await this.prisma.dueCache.findMany({
        where: { plantId: id },
        select: { task: true, nextDueOn: true },
        orderBy: { nextDueOn: 'asc' },
      });
    }

    const primary = await this.prisma.city.findFirst({ where: { ownerId, isPrimary: true } });
    const startOfToday = startOfTodayUtc(primary?.timezone ?? 'UTC');

    const tasks = due.map((d) => {
      const { daysUntilDue, status } = careTaskStatus(d.nextDueOn, startOfToday);
      return {
        task: d.task,
        nextDueOn: formatYmd(d.nextDueOn),
        daysUntilDue,
        status,
      };
    });

    return { plantId: id, tasks };
  }
```

  Add a small private/module-level formatter that renders a `@db.Date` (UTC-midnight) as `YYYY-MM-DD`
  **without** `toISOString` round-tripping risk — slicing the ISO of a pure UTC-midnight date is safe
  here because the value is already UTC-midnight, but to stay consistent with the MariaDB-date
  discipline we build it from the UTC parts. Add at the bottom of the file (module scope):

```ts
// Render a @db.Date (UTC-midnight) as YYYY-MM-DD from its UTC calendar parts.
function formatYmd(d: Date): string {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}
```

- [ ] **Add the route.** Edit `repos/my-plants-api/src/plants/plants.controller.ts` — add a `care`
  route. Order matters: keep `:id/care` defined before the bare `:id` is irrelevant here since they
  do not collide, but add it explicitly:

```ts
  @Get(':id/care') getCare(@Param('id') id: string) { return this.plants.getCare(id); }
```

  Final controller body:

```ts
  @Get() list() { return this.plants.list(); }
  @Post() create(@Body() dto: CreatePlantDto) { return this.plants.create(dto); }
  @Get(':id/care') getCare(@Param('id') id: string) { return this.plants.getCare(id); }
  @Get(':id') get(@Param('id') id: string) { return this.plants.get(id); }
```

- [ ] **Wire the module dependency.** Edit `repos/my-plants-api/src/plants/plants.module.ts` to import
  `CarePlanModule` (which exports `CarePlanService`):

```ts
import { Module } from '@nestjs/common';
import { CarePlanModule } from '../care-plan/care-plan.module.js';
import { PlantsController } from './plants.controller.js';
import { PlantsService } from './plants.service.js';

@Module({
  imports: [CarePlanModule],
  controllers: [PlantsController],
  providers: [PlantsService],
  exports: [PlantsService],
})
export class PlantsModule {}
```

- [ ] **Verify it compiles + suite green:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm run build && npm test
```
Expected: build clean, all tests PASS.

- [ ] **Manual verification (real path).** With the stack up (`./run.sh`), hit the new endpoint for an
  owned plant and for a foreign id:

```bash
curl -s http://localhost:8000/plants/<PLANT_ID>/care
# Expect: {"plantId":"<PLANT_ID>","tasks":[{"task":"WATER","nextDueOn":"2026-06-2X","daysUntilDue":N,"status":"..."}, ...]} ordered by nextDueOn asc.
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8000/plants/not-a-real-id/care
# Expect: 404
```

  Confirm `status`/`daysUntilDue` agree with the plant's primary-city timezone (e.g. a due date equal
  to the local "today" reads `status:"today"`, `daysUntilDue:0`). To verify on-demand recompute,
  create a fresh plant (which does not recompute on create) and confirm `/care` returns a non-empty
  `tasks` array on the first call. Document results.

- [ ] **Commit:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && git add src/plants/plants.service.ts src/plants/plants.controller.ts src/plants/plants.module.ts && git commit -m "feat(plants): add owner-scoped GET /plants/:id/care read endpoint"
```

---

## Task 6 — Startup recompute provider (`OnApplicationBootstrap`)

On boot: apply any due moves; only if **0** moves were applied, run `recomputeAll()`. The 05:00 cron
stays. `applyDueMoves` already recomputes the whole garden when it applies at least one move, so
guarding the `recomputeAll` avoids a redundant double recompute.

**Files**
- Create: `repos/my-plants-api/src/startup/startup.service.ts`
- Create: `repos/my-plants-api/src/startup/startup.module.ts`
- Modify: `repos/my-plants-api/src/app.module.ts` (register the module)

**Steps**

- [ ] **Create the provider.** `repos/my-plants-api/src/startup/startup.service.ts`:

```ts
import { Injectable, Logger, type OnApplicationBootstrap } from '@nestjs/common';
import { MovingService } from '../moving/moving.service.js';
import { CarePlanService } from '../care-plan/care-plan.service.js';

// The app runs locally and is turned on to be used. On boot: apply any move whose date arrived while
// the app was off, then — ONLY if no move was applied — recompute the whole garden (applyDueMoves
// already recomputes when it applies a move). Mirrors the 05:00 cron, which stays.
@Injectable()
export class StartupService implements OnApplicationBootstrap {
  private readonly logger = new Logger(StartupService.name);

  constructor(
    private readonly moving: MovingService,
    private readonly carePlan: CarePlanService,
  ) {}

  async onApplicationBootstrap(): Promise<void> {
    const applied = await this.moving.applyDueMoves(new Date());
    if (applied === 0) {
      await this.carePlan.recomputeAll();
      this.logger.log('Startup recompute: applied 0 due moves, recomputed the whole garden.');
    } else {
      this.logger.log(`Startup recompute: applied ${applied} due move(s) (garden recomputed by the move).`);
    }
  }
}
```

- [ ] **Create the module.** `repos/my-plants-api/src/startup/startup.module.ts`. It needs the
  providers `MovingService` and `CarePlanService`. `CarePlanModule` exports `CarePlanService`, but
  `MovingModule` does **not** export `MovingService`, so add it to `MovingModule`'s exports and import
  both modules here:

```ts
import { Module } from '@nestjs/common';
import { MovingModule } from '../moving/moving.module.js';
import { CarePlanModule } from '../care-plan/care-plan.module.js';
import { StartupService } from './startup.service.js';

@Module({
  imports: [MovingModule, CarePlanModule],
  providers: [StartupService],
})
export class StartupModule {}
```

- [ ] **Export `MovingService`.** Edit `repos/my-plants-api/src/moving/moving.module.ts` to export the
  service so the startup provider can inject it:

```ts
@Module({
  imports: [WeatherModule, CarePlanModule],
  controllers: [MovingController],
  providers: [MovingService, MovingCron],
  exports: [MovingService],
})
export class MovingModule {}
```

- [ ] **Register `StartupModule`.** Edit `repos/my-plants-api/src/app.module.ts` — add the import and
  add `StartupModule` to the `imports` array (place it last so all its dependencies are constructed):

```ts
import { StartupModule } from './startup/startup.module.js';
// ...
  imports: [
    // ...existing modules...
    NotificationsModule,
    StartupModule,
  ],
```

- [ ] **Verify it compiles + suite green:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm run build && npm test
```
Expected: build clean, all tests PASS.

- [ ] **Manual verification (real path).** Start the API and watch the logs:

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm run build && node dist/main.js
```
Expected: a `StartupService` log line on boot ("applied 0 due moves, recomputed the whole garden"
when there are no due moves). Confirm the API still listens and `/plants` responds. If a move is due,
confirm it is applied (city becomes primary) and the log reflects the applied count. Stop the process
after verifying.

- [ ] **Commit:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && git add src/startup/startup.service.ts src/startup/startup.module.ts src/moving/moving.module.ts src/app.module.ts && git commit -m "feat(startup): recompute garden on boot after applying due moves"
```

---

## Task 7 — Frontend care panel on `pages/plants/[id].vue`

Rebuild the plant detail page into a care panel fed by `getPlantCare(id)`: list applicable tasks with
their next-due date + status, each with a **Done** button (occurredOn defaults to today, with an
optional date picker to back-date) and a **Postpone** button; refetch after each action.

**Files**
- Modify: `repos/my-plants-web/types/api.ts` (add `PlantCare`)
- Modify: `repos/my-plants-web/composables/useApi.ts` (add `getPlantCare`)
- Modify: `repos/my-plants-web/pages/plants/[id].vue` (rebuild)

**Steps**

- [ ] **Add the `PlantCare` type.** Edit `repos/my-plants-web/types/api.ts`. Append (keep `viability`
  optional — Phase C fills it in; the seam must already exist in the type):

```ts
export interface PlantCareTask {
  task: TaskCode;
  nextDueOn: string;        // YYYY-MM-DD
  daysUntilDue: number;     // <0 overdue, 0 today, >0 upcoming
  status: 'overdue' | 'today' | 'upcoming';
}
export interface PlantCare {
  plantId: string;
  tasks: PlantCareTask[];
  // Added in Phase C — the per-plant viability semaphore for its current place.
  viability?: { level: ViabilityLevel; reasons: string[] };
}
```

- [ ] **Add the client method.** Edit `repos/my-plants-web/composables/useApi.ts`. Add `PlantCare` to
  the type import line and add the method next to `getPlant`:

```ts
import type {
  City, CreateCity, CreatePlace, CreatePlant, DueTaskResponse, Feedback, Place, Plant,
  PlantCare, PlantViability, SpeciesSummary,
} from '../types/api.js';
```

  And inside the returned object, after `getPlant`:

```ts
    getPlantCare: (id: string) => api<PlantCare>(`/plants/${id}/care`),
```

- [ ] **Rebuild the page.** Replace `repos/my-plants-web/pages/plants/[id].vue` entirely. It uses the
  existing `TASK_LABELS` for task names and renders the server-computed `status`/`daysUntilDue`
  directly (the backend already did the timezone math — the client just renders):

```vue
<script setup lang="ts">
import { TASK_LABELS, type TaskCode } from '../../utils/tasks.js';

const route = useRoute();
const api = useApi();
const id = route.params.id as string;

const { data: plant } = await useAsyncData(`plant-${id}`, () => api.getPlant(id));
const { data: care, refresh } = await useAsyncData(`care-${id}`, () => api.getPlantCare(id));

const today = () => new Date().toISOString().slice(0, 10);

// Per-task optional back-date for Done. Empty string = use today.
const doneDate = reactive<Record<string, string>>({});

function dueLabel(t: { daysUntilDue: number; status: string }): string {
  if (t.status === 'overdue') return `Overdue by ${Math.abs(t.daysUntilDue)} day(s)`;
  if (t.status === 'today') return 'Due today';
  return t.daysUntilDue === 1 ? 'Due tomorrow' : `Due in ${t.daysUntilDue} days`;
}

function dueColor(status: string): string {
  return status === 'overdue' ? 'red' : status === 'today' ? 'amber' : 'gray';
}

async function markDone(task: TaskCode) {
  const occurredOn = doneDate[task] || today();
  await api.sendFeedback(id, { task, type: 'DONE', occurredOn });
  doneDate[task] = '';
  await refresh();
}

async function postpone(task: TaskCode) {
  const tomorrow = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
  await api.sendFeedback(id, { task, type: 'POSTPONED', occurredOn: today(), postponeToOn: tomorrow });
  await refresh();
}
</script>

<template>
  <div v-if="plant">
    <NuxtLink to="/plants" class="text-sm text-gray-500 hover:underline">← All plants</NuxtLink>
    <h2 class="text-xl font-bold mt-2">{{ plant.nickname ?? plant.speciesSlug }}</h2>
    <p class="text-gray-500">{{ plant.speciesSlug }}</p>
    <p class="text-sm text-gray-500 mt-1">Acquired {{ plant.acquiredOn.slice(0, 10) }}</p>

    <!-- Phase C will render a ViabilityBadge here from care.viability. -->

    <h3 class="text-lg font-semibold mt-6 mb-2">Care</h3>
    <p v-if="!care || !care.tasks.length" class="text-gray-500">Nothing to do right now. 🌿</p>
    <UCard v-else>
      <div
        v-for="t in care.tasks"
        :key="t.task"
        class="flex flex-wrap items-center justify-between gap-2 py-2 border-b last:border-b-0 border-gray-100"
      >
        <div class="flex items-center gap-2">
          <span class="font-medium">{{ TASK_LABELS[t.task] }}</span>
          <UBadge :color="dueColor(t.status)" variant="subtle" size="xs">{{ dueLabel(t) }}</UBadge>
        </div>
        <div class="flex items-center gap-2">
          <UInput
            v-model="doneDate[t.task]"
            type="date"
            size="xs"
            :placeholder="today()"
            aria-label="Back-date this done"
          />
          <UButton size="xs" color="green" icon="i-heroicons-check" @click="markDone(t.task)">Done</UButton>
          <UButton size="xs" color="gray" variant="ghost" icon="i-heroicons-clock" @click="postpone(t.task)">
            Postpone
          </UButton>
        </div>
      </div>
    </UCard>
  </div>
  <p v-else class="text-gray-500">Loading…</p>
</template>
```

> **Default-today behaviour:** the date input defaults to empty; `markDone` falls back to today when
> empty, so the owner never has to touch the date for the common case (spec A.5). Setting the input
> back-dates that one action; it is cleared after submit.

- [ ] **Verify build + typecheck:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-web && npm run build && npm run typecheck
```
Expected: build + typecheck succeed (no TS errors; `PlantCare` and `getPlantCare` resolve). Note:
`npm run build` (nuxt build) does NOT catch type errors here because `typescript.typeCheck` is off in
`nuxt.config.ts`; type errors are caught by `npm run typecheck` (`nuxt typecheck`, which runs vue-tsc).

- [ ] **Manual verification (real path).** With both API and web up (`./run.sh`), open
  `http://localhost:8001/plants/<PLANT_ID>`. Confirm: the care panel lists the plant's applicable
  tasks with their status badge; clicking **Done** (no date set) posts `occurredOn = today` and the
  panel refetches with updated due dates; setting the date input then clicking **Done** back-dates the
  event; **Postpone** pushes the task and the panel refetches. Document results.

- [ ] **Commit:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-web && git add types/api.ts composables/useApi.ts pages/plants/[id].vue && git commit -m "feat(web): rebuild plant page into a care panel with Done/Postpone"
```

---

## Closing verification (run before handing back)

- [ ] **API suite green:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm test
```
Expected: all unit tests PASS (local-date, punctuality, adaptation incl. convergence, adherence,
plant-care, plus the pre-existing engine/config tests).

- [ ] **API build clean:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-api && npm run build
```

- [ ] **Web build + typecheck clean:**

```bash
cd /home/retaxmaster/projects/my-plants/repos/my-plants-web && npm run build && npm run typecheck
```

- [ ] **Leave it runnable:** Phase A introduces **no migration** (adherence rides the existing
  `CareEvent.payload` JSON column) and **no new env vars**, so no `prisma migrate`/`.env` change is
  needed. Confirm the full stack still starts via `./run.sh` from the workspace root and the plant
  page works end-to-end.

> Do **not** merge to `main`, push, or bump submodule pointers as part of this plan — those are the
> closing steps of the workspace Multi-repo feature workflow, performed later with explicit approval.

---

## Notes, decisions & assumptions

- **`previousAnchor` query (A.2 step 1).** The "most recent prior DONE, tie-break `createdAt desc`" is
  read **before** the new event is created, so it never sees the event being recorded — exactly the
  spec's "keep `previousAnchor` uncontaminated". Ordering uses `[{ occurredOn: 'desc' }, { createdAt:
  'desc' }]`, matching the spec's tie-break.
- **API port assumption.** Manual-verification `curl`s assume the API on `http://localhost:8000` and
  the web on `http://localhost:8001` (the CORS origin default in `src/main.ts`). If `./run.sh` uses
  different ports, substitute them — the behavior to verify is unchanged.
- **Pure-helper extraction over service unit tests.** The repo has **no** DB-touching service test
  harness (all existing tests are pure engine/helper unit tests under `src/engines`, `src/common`,
  `src/config`). Rather than introduce a Prisma test harness in this phase, the plan extracts every
  testable rule into pure helpers (`computeEarlyRatio`, `computeAdherence`/`eligibleCycles`,
  `careTaskStatus`, the convergent `nextAdjustment`) with focused Vitest tests, and verifies the thin
  DB orchestration (the feedback sequence, the endpoint, the startup hook) by manual runs through the
  real, unmodified code path against the local stack. This matches the project's testing conventions
  and the "test pure helpers; manual-verify the glue" guidance in the task brief.
- **`MovingService` export.** `MovingModule` did not previously export `MovingService`; the startup
  module needs it, so the plan adds it to the module's `exports`. No behavior change for existing
  consumers.
- **`formatYmd` instead of `toISOString().slice(0,10)`.** Although the due value is already
  UTC-midnight (so slicing would be correct), the plan builds the `YYYY-MM-DD` string from the UTC
  calendar parts to stay strictly consistent with the MariaDB-date discipline and avoid any future
  foot-gun if a non-midnight value ever flows through.
- **Web date input.** Uses Nuxt UI's `UInput type="date"` (already in the stack) for the optional
  back-date, avoiding a new dependency.
