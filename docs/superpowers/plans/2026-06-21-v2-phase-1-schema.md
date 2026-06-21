# Enrichment v2 — Phase 1: Schema contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the shared species contract with `humiditySensitivity`, a `misting` section, and a `primaryCommonName` helper — all backward-compatible — then pack & install it into the consumers.

**Architecture:** `my-plants-species-schema` is a Zod schema whose inferred types are the single source of truth. New fields ship with `.default(...)` so species already stored in the DB still parse. After the change, repack the tarball and install it into `my-plants-knowledge-engine` and `my-plants-api`.

**Tech Stack:** TypeScript, Zod, Vitest.

**Repo:** `repos/my-plants-species-schema` (then pack/install into consumers).

---

### Task 1: `humiditySensitivity` on the watering section

**Files:**
- Modify: `repos/my-plants-species-schema/src/sections.ts` (the `wateringSchema`)
- Test: `repos/my-plants-species-schema/src/species-record.test.ts`

- [ ] **Step 1: Write the failing test** — add to `species-record.test.ts`:

```ts
it('defaults humiditySensitivity to low when omitted', () => {
  const rec = parseSpeciesRecord(validRecordWithout('watering.humiditySensitivity'));
  expect(rec.watering.humiditySensitivity).toBe('low');
});

it('accepts an explicit humiditySensitivity', () => {
  const rec = parseSpeciesRecord(validRecord({ watering: { humiditySensitivity: 'high' } }));
  expect(rec.watering.humiditySensitivity).toBe('high');
});
```

> If the test file has no `validRecord`/`validRecordWithout` helpers, use the existing fixtures in that file (read the top of `species-record.test.ts`); the assertions on `rec.watering.humiditySensitivity` are what matter. A valid base record is already defined there for other tests — reuse it and override `watering`.

- [ ] **Step 2: Run to verify it fails**

Run: `cd repos/my-plants-species-schema && npm test`
Expected: FAIL (`humiditySensitivity` is `undefined`).

- [ ] **Step 3: Implement** — in `sections.ts`, add the field to `wateringSchema` (note `SENSITIVITY` is already imported):

```ts
export const wateringSchema = z.object({
  baseIntervalDays: z.number().int().positive(),
  soilDrynessBeforeWatering: z.enum(SOIL_DRYNESS),
  droughtTolerance: z.enum(DROUGHT_TOLERANCE),
  temperatureSensitivity: z.enum(SENSITIVITY),
  lightSensitivity: z.enum(SENSITIVITY),
  humiditySensitivity: z.enum(SENSITIVITY).default('low'),
  reduceInDormancy: z.boolean(),
});
```

- [ ] **Step 4: Run to verify it passes** — `npm test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/sections.ts src/species-record.test.ts
git commit -m "feat: add humiditySensitivity to watering schema (default low)"
```

---

### Task 2: `MISTING_BENEFIT` enum + `mistingSchema`

**Files:**
- Modify: `repos/my-plants-species-schema/src/enums.ts`
- Modify: `repos/my-plants-species-schema/src/sections.ts`
- Test: `repos/my-plants-species-schema/src/sections.test.ts`

- [ ] **Step 1: Write the failing tests** — add to `sections.test.ts`:

```ts
import { mistingSchema } from './sections.js';

describe('mistingSchema', () => {
  it('defaults to avoid with null frequency and note', () => {
    const m = mistingSchema.parse({});
    expect(m).toEqual({ benefit: 'avoid', baseFrequencyDays: null, note: null });
  });
  it('accepts a beneficial schedule', () => {
    const m = mistingSchema.parse({ benefit: 'beneficial', baseFrequencyDays: 3, note: 'broad leaves' });
    expect(m.benefit).toBe('beneficial');
    expect(m.baseFrequencyDays).toBe(3);
  });
  it('rejects benefit !== avoid with a null baseFrequencyDays', () => {
    expect(() => mistingSchema.parse({ benefit: 'tolerated', baseFrequencyDays: null })).toThrow();
  });
  it('rejects avoid with a non-null baseFrequencyDays', () => {
    expect(() => mistingSchema.parse({ benefit: 'avoid', baseFrequencyDays: 5 })).toThrow();
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npm test` → FAIL (`mistingSchema` not exported).

- [ ] **Step 3a: Implement the enum** — in `enums.ts`, append:

```ts
export const MISTING_BENEFIT = ['beneficial', 'tolerated', 'avoid'] as const;
export type MistingBenefit = (typeof MISTING_BENEFIT)[number];
```

- [ ] **Step 3b: Implement the schema** — in `sections.ts`, import `MISTING_BENEFIT` (add to the existing `./enums.js` import list) and add:

```ts
export const mistingSchema = z
  .object({
    benefit: z.enum(MISTING_BENEFIT).default('avoid'),
    baseFrequencyDays: z.number().int().positive().nullable().default(null),
    note: z.string().min(1).nullable().default(null),
  })
  .refine(
    (m) => (m.benefit === 'avoid' ? m.baseFrequencyDays === null : m.baseFrequencyDays !== null),
    { message: 'baseFrequencyDays must be set when benefit is beneficial/tolerated, and null when avoid' },
  );
```

- [ ] **Step 4: Run to verify it passes** — `npm test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/enums.ts src/sections.ts src/sections.test.ts
git commit -m "feat: add misting section + MISTING_BENEFIT enum to schema"
```

---

### Task 3: Wire `misting` into the species record (with default)

**Files:**
- Modify: `repos/my-plants-species-schema/src/species-record.ts`
- Test: `repos/my-plants-species-schema/src/species-record.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
it('defaults the misting section to avoid when omitted (backward compatible)', () => {
  const rec = parseSpeciesRecord(validRecordWithout('misting'));
  expect(rec.misting).toEqual({ benefit: 'avoid', baseFrequencyDays: null, note: null });
});
```

- [ ] **Step 2: Run to verify it fails** — `npm test` → FAIL.

- [ ] **Step 3: Implement** — in `species-record.ts`, import `mistingSchema` (add to the `./sections.js` import) and add the field to `speciesRecordSchema`:

```ts
  misting: mistingSchema.default({ benefit: 'avoid', baseFrequencyDays: null, note: null }),
```

- [ ] **Step 4: Run to verify it passes** — `npm test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/species-record.ts src/species-record.test.ts
git commit -m "feat: add misting to species record (default avoid, backward compatible)"
```

---

### Task 4: `primaryCommonName` helper

**Files:**
- Modify: `repos/my-plants-species-schema/src/species-record.ts`
- Test: `repos/my-plants-species-schema/src/species-record.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { primaryCommonName } from './species-record.js';

describe('primaryCommonName', () => {
  it('returns the first common name', () => {
    expect(primaryCommonName({ commonNames: ['Snake plant', 'MIL'], scientificName: 'Dracaena trifasciata' }))
      .toBe('Snake plant');
  });
  it('falls back to the scientific name when there are no common names', () => {
    expect(primaryCommonName({ commonNames: [], scientificName: 'Dracaena trifasciata' }))
      .toBe('Dracaena trifasciata');
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npm test` → FAIL (not exported).

- [ ] **Step 3: Implement** — append to `species-record.ts`:

```ts
// The human-facing name: the first (most recognizable) common name, or the scientific name if none.
// Single source of the "primary name" rule so the API and any other consumer never fork it.
export function primaryCommonName(record: { commonNames: string[]; scientificName: string }): string {
  return record.commonNames[0] ?? record.scientificName;
}
```

- [ ] **Step 4: Run to verify it passes** — `npm test` → PASS. (`primaryCommonName` is re-exported automatically by `index.ts`'s `export * from './species-record.js'`.)

- [ ] **Step 5: Commit**

```bash
git add src/species-record.ts src/species-record.test.ts
git commit -m "feat: add primaryCommonName helper (single source of the display-name rule)"
```

---

### Task 5: Version bump + pack + install into consumers

**Files:**
- Modify: `repos/my-plants-species-schema/package.json` (version)
- Modify (via script): `repos/my-plants-knowledge-engine/package.json` + lockfile, `repos/my-plants-api/package.json` + lockfile

- [ ] **Step 1: Bump the version** — in `repos/my-plants-species-schema/package.json`, change `"version": "0.3.0"` to `"version": "0.4.0"`.

- [ ] **Step 2: Run the full schema suite once more**

Run: `cd repos/my-plants-species-schema && npm test`
Expected: PASS (all tasks above green).

- [ ] **Step 3: Pack & install into both consumers**

Run (from the workspace root): `./scripts/pack-species-schema-and-install.sh`
Expected: the script packs `retaxmaster-my-plants-species-schema-0.4.0.tgz` and installs it into the knowledge-engine and the api, updating their `package.json` dependency path and lockfiles.

- [ ] **Step 4: Verify consumers compile against the new contract**

Run: `cd repos/my-plants-api && npm run build` (will FAIL later phases' code is absent — but it must at least resolve the new package; if it fails only due to missing `humiditySensitivity` in seed/fixtures, that is expected and handled in Phase 3). For this phase, confirm the dependency resolves: `npm ls @retaxmaster/my-plants-species-schema` shows `0.4.0`.

> Note: the API/knowledge-engine may not fully typecheck until later phases consume the new fields; that is acceptable here. The gate for THIS task is that the new package version is installed and importable.

- [ ] **Step 5: Commit (schema repo)**

```bash
cd repos/my-plants-species-schema
git add package.json
git commit -m "chore: bump species-schema to 0.4.0 (humiditySensitivity, misting, primaryCommonName)"
```

- [ ] **Step 6: Commit the consumers' updated manifests** (done per-repo in their own phases' first commit, or now if convenient):

```bash
cd repos/my-plants-knowledge-engine && git add package.json package-lock.json && git commit -m "chore: depend on species-schema 0.4.0"
cd repos/my-plants-api && git add package.json package-lock.json && git commit -m "chore: depend on species-schema 0.4.0"
```

---

## Self-Review

- **Spec coverage:** R2.4 (`humiditySensitivity` + default low) ✓ Task 1; R3.1 (`misting` section + enum + refinement + defaults) ✓ Tasks 2–3; B.2 (`primaryCommonName`) ✓ Task 4; pack/install ✓ Task 5.
- **Backward compatibility:** every new field has a default; a record without `misting`/`humiditySensitivity` parses (Tasks 1 & 3 assert this).
- **Type consistency:** `MistingBenefit` is the exported type used by Phase 4's `computeMistingDue`. `primaryCommonName` signature matches Phase 5 usage.
