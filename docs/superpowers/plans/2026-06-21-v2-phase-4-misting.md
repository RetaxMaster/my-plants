# Enrichment v2 — Phase 4: Misting cycle (API) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sixth, species-dependent, humidity-gated care cycle (`MIST`): a pure `computeMistingDue` function, service gating that creates or clears the misting due, and the generic Done/Postpone path — surfaced in the plant care endpoint.

**Architecture:** `MIST` joins the Prisma `Task` enum, so `DueCache`/`TaskOverride`/`PlantTaskAdjustment`/`CareEvent` support it for free. The pure `computeMistingDue` takes an already-resolved humidity **band** (from `humidityBand(effective.humidityPct)`), keeping the engine free of weather/place coupling. The service computes the band once and either upserts the misting due or deletes a stale one (a generalized cleanup also applied to skipped ROTATE/CLEAN_LEAVES).

**Tech Stack:** TypeScript, NestJS, Prisma, Vitest. Depends on Phase 1 (`misting` schema, `MistingBenefit`) and Phase 3 (`humidityBand`, `EffectiveConditions`).

**Repo:** `repos/my-plants-api`.

---

### Task 1: Prisma migration — add `MIST` to the `Task` enum

**Files:**
- Modify: `repos/my-plants-api/prisma/schema.prisma` (the `Task` enum, line ~10)
- Create: a migration under `prisma/migrations/`

- [ ] **Step 1: Edit the enum**

```prisma
enum Task {
  WATER
  FERTILIZE
  REPOT
  ROTATE
  CLEAN_LEAVES
  MIST
}
```

- [ ] **Step 2: Create + apply the migration**

Run: `cd repos/my-plants-api && set -a; source .env; set +a && npx prisma migrate dev --name add_mist_task`
Expected: migration created/applied; client regenerated; `Task` now includes `MIST`.

- [ ] **Step 3: Commit**

```bash
git add prisma/schema.prisma prisma/migrations
git commit -m "feat: add MIST to the Task enum"
```

---

### Task 2: `computeMistingDue` (pure, humidity-graded)

**Files:**
- Modify: `repos/my-plants-api/src/engines/scheduling.ts`
- Test: `repos/my-plants-api/src/engines/scheduling.test.ts`

- [ ] **Step 1: Write the failing tests** — add to `scheduling.test.ts`:

```ts
import { computeMistingDue } from './scheduling.js';

const mistBase = {
  benefit: 'beneficial' as const,
  baseFrequencyDays: 4,
  band: 'NORMAL' as const,
  adjustment: 1,
  anchor: new Date('2026-06-01'),
};
const daysFrom = (d: Date) => Math.round((d!.getTime() - mistBase.anchor.getTime()) / 86_400_000);

describe('computeMistingDue', () => {
  it('beneficial + NORMAL → base frequency', () => {
    expect(daysFrom(computeMistingDue(mistBase)!)).toBe(4);
  });
  it('beneficial + DRY → shortened (more frequent)', () => {
    expect(daysFrom(computeMistingDue({ ...mistBase, band: 'DRY' })!)).toBeLessThan(4);
  });
  it('beneficial + HUMID → no task', () => {
    expect(computeMistingDue({ ...mistBase, band: 'HUMID' })).toBeNull();
  });
  it('tolerated + DRY → base frequency', () => {
    expect(daysFrom(computeMistingDue({ ...mistBase, benefit: 'tolerated', band: 'DRY' })!)).toBe(4);
  });
  it('tolerated + NORMAL → no task', () => {
    expect(computeMistingDue({ ...mistBase, benefit: 'tolerated', band: 'NORMAL' })).toBeNull();
  });
  it('tolerated + HUMID → no task', () => {
    expect(computeMistingDue({ ...mistBase, benefit: 'tolerated', band: 'HUMID' })).toBeNull();
  });
  it('avoid → always null', () => {
    expect(computeMistingDue({ ...mistBase, benefit: 'avoid', baseFrequencyDays: null })).toBeNull();
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run src/engines/scheduling.test.ts` → FAIL (not exported).

- [ ] **Step 3: Implement** — in `scheduling.ts`, import the benefit type and add the function near the other cadence functions:

```ts
import type { DroughtTolerance, MistingBenefit, Season, Sensitivity } from '@retaxmaster/my-plants-species-schema';
```

(extend the existing import from the schema to include `MistingBenefit`.)

```ts
// Misting: opt-in per species, gated by the place's effective humidity band. Returns null when no
// misting task should exist (avoid; beneficial in a humid room; tolerated outside a dry room).
const MIST_DRY_FACTOR = 0.6; // dry air → mist more often
export interface MistingInput {
  benefit: MistingBenefit;
  baseFrequencyDays: number | null;
  band: 'DRY' | 'NORMAL' | 'HUMID';
  adjustment: number;
  anchor: Date;
}
export function computeMistingDue(i: MistingInput): Date | null {
  if (i.benefit === 'avoid' || i.baseFrequencyDays === null) return null;
  let factor: number | null;
  if (i.benefit === 'beneficial') {
    factor = i.band === 'HUMID' ? null : i.band === 'DRY' ? MIST_DRY_FACTOR : 1;
  } else {
    // tolerated: only earns a task when the room is dry.
    factor = i.band === 'DRY' ? 1 : null;
  }
  if (factor === null) return null;
  return addDays(i.anchor, Math.round(i.baseFrequencyDays * i.adjustment * factor));
}
```

- [ ] **Step 4: Run to verify it passes** — `npx vitest run src/engines/scheduling.test.ts` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/engines/scheduling.ts src/engines/scheduling.test.ts
git commit -m "feat: computeMistingDue (humidity-graded, returns null when no task)"
```

---

### Task 3: Service gating + generalized stale-due cleanup

**Files:**
- Modify: `repos/my-plants-api/src/care-plan/care-plan.service.ts`
- Test: a care-plan service test (extend the existing one, or add `src/care-plan/care-plan.misting.test.ts` using the same Prisma test setup as the existing care-plan tests)

- [ ] **Step 1: Add a `clearDue` helper** (next to `upsertDue`):

```ts
  private async clearDue(plantId: string, task: Task): Promise<void> {
    await this.prisma.dueCache.deleteMany({ where: { plantId, task } });
  }
```

- [ ] **Step 2: Generalize the skip branches** in `recomputePlant`'s loop so a skipped optional cadence also clears its stale cache:

```ts
      if (task === 'ROTATE' && record.maintenance.rotationDays === null) { await this.clearDue(plantId, task); continue; }
      if (task === 'CLEAN_LEAVES' && record.maintenance.leafCleaningDays === null) { await this.clearDue(plantId, task); continue; }
```

- [ ] **Step 3: Add the MIST block** after the `for (const task of SCHEDULED_TASKS)` loop, before the method ends. It honors an explicit override (a user postpone) first, else computes the humidity-graded due, upserting or clearing:

```ts
    // Misting (sixth cycle): humidity-graded, may produce no task at all.
    const mistOverride = plant.overrides.find((o) => o.task === 'MIST');
    if (mistOverride) {
      await this.upsertDue(plantId, 'MIST', mistOverride.nextDueOn);
    } else {
      const mistAnchor =
        (await this.prisma.careEvent.findFirst({
          where: { plantId, task: 'MIST', type: 'DONE' },
          orderBy: { occurredOn: 'desc' },
        }))?.occurredOn ?? plant.acquiredOn;
      const mistAdjustment = plant.adjustments.find((a) => a.task === 'MIST')?.multiplier ?? 1;
      const mistDue = computeMistingDue({
        benefit: record.misting.benefit,
        baseFrequencyDays: record.misting.baseFrequencyDays,
        band: humidityBand(effective.humidityPct),
        adjustment: mistAdjustment,
        anchor: mistAnchor,
      });
      if (mistDue === null) await this.clearDue(plantId, 'MIST');
      else await this.upsertDue(plantId, 'MIST', mistDue);
    }
```

- [ ] **Step 4: Add the imports** at the top of `care-plan.service.ts`:

```ts
import { computeCadenceDue, computeFertilizingDue, computeMistingDue, computeNextDue } from '../engines/scheduling.js';
import { effectiveConditions, humidityBand, type EffectiveConditions } from '../engines/indoor-climate.js';
```

(extend the existing imports rather than duplicating.)

- [ ] **Step 5: Write the failing test** — assert a `MIST` due appears for a beneficial, dry-placed species and is cleared when the place is humid. Mirror the Prisma setup used by existing care-plan tests (read one first). Skeleton:

```ts
it('schedules MIST for a beneficial species in a dry place and clears it in a humid place', async () => {
  // ...seed owner/city/species(misting.benefit='beneficial', baseFrequencyDays=4)/place(indoor, humidityCharacter='DRY')/plant...
  await service.recomputePlant(plantId);
  let mist = await prisma.dueCache.findUnique({ where: { plantId_task: { plantId, task: 'MIST' } } });
  expect(mist).not.toBeNull();
  // move plant's place to HUMID, recompute → MIST cache cleared
  await prisma.place.update({ where: { id: placeId }, data: { humidityCharacter: 'HUMID' } });
  await service.recomputePlant(plantId);
  mist = await prisma.dueCache.findUnique({ where: { plantId_task: { plantId, task: 'MIST' } } });
  expect(mist).toBeNull();
});
```

- [ ] **Step 6: Run → green**

Run: `cd repos/my-plants-api && npm test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/care-plan/care-plan.service.ts src/care-plan/*.test.ts
git commit -m "feat: schedule/clear MIST due (humidity-graded) + generalized stale-due cleanup"
```

---

### Task 4: MIST through the generic feedback path + care endpoint

**Files:**
- Modify: `repos/my-plants-api/src/feedback/feedback.service.ts` (verify generic handling)
- Modify: `repos/my-plants-api/src/feedback/feedback.controller.ts` / DTO (verify `MIST` is an accepted task)
- Verify: `repos/my-plants-api/src/plants/plants.service.ts` `getCare` already returns every `DueCache` task, so `MIST` flows out automatically.

- [ ] **Step 1: Confirm the feedback DTO accepts `MIST`.** Read `src/feedback/*.dto.ts` / controller. If the `task` field validates against an enum/list of task codes, add `MIST`. The service's DONE/POSTPONE/SYMPTOM logic is task-generic except the WATER-only punctuality block (guarded by `input.task === 'WATER'`), so `MIST` DONE re-anchors and POSTPONE overrides with no special learning — exactly as intended. No watering-learning change.

- [ ] **Step 2: Write a failing test** — `MIST` DONE creates a `CareEvent` and re-anchors; POSTPONE creates a `TaskOverride`. Mirror existing feedback tests:

```ts
it('records a MIST done as a generic re-anchor (no punctuality learning)', async () => {
  // ...seed plant with misting beneficial in a DRY place...
  await feedback.record({ plantId, task: 'MIST', type: 'DONE', occurredOn: new Date('2026-06-10') });
  const ev = await prisma.careEvent.findFirst({ where: { plantId, task: 'MIST', type: 'DONE' } });
  expect(ev).not.toBeNull();
  const adj = await prisma.plantTaskAdjustment.findUnique({ where: { plantId_task: { plantId, task: 'MIST' } } });
  expect(adj).toBeNull(); // no learning was applied
});
```

- [ ] **Step 3: Run → green** — `npm test` → PASS.

- [ ] **Step 4: Commit**

```bash
git add src/feedback
git commit -m "feat: accept MIST feedback through the generic path (no punctuality learning)"
```

---

## Self-Review

- **Spec coverage:** R3.2 `MIST` enum/migration ✓ Task 1; R3.3 `computeMistingDue` table ✓ Task 2; R3.4 service gating + stale-due cleanup + generic feedback ✓ Tasks 3 & 4; the care endpoint surfaces MIST automatically (verified Task 4 Step beginning).
- **No-fork:** the humidity band comes from the single `humidityBand` helper (Phase 3); the engine takes a flat band.
- **Type consistency:** `MistingInput.benefit: MistingBenefit` matches the schema enum; `computeMistingDue` returns `Date | null` consumed by the service's upsert/clear.
- **Punctuality learning stays WATER-only:** the misting path never enters `adaptFromPunctuality` (guarded by `task === 'WATER'`).
