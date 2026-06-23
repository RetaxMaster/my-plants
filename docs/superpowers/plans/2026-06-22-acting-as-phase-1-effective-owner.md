# Acting As — Phase 1: Effective-Owner Model + Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blanket "ADMIN sees all" (`ownerFilter()` → `{}`) with an explicit **effective-owner** model: an admin defaults to their own resources and can act on behalf of another owner via a role-gated `X-Act-As-Owner` request header that the guard validates.

**Architecture:** The change is centralized in `OwnerService` (every owner-scoped service reads `ownerFilter()`/`currentOwnerId()`, so they all inherit it). The guard reads/validates the header and stamps `actingAsOwnerId` onto the request `Actor` only for admins. A new `AuthService.ownerExists()` backs the guard's existence check (the guard already injects `AuthService`, so no constructor change).

**Tech Stack:** NestJS, nestjs-cls (per-request actor store), Prisma, Vitest.

**Reference:** spec `docs/superpowers/specs/2026-06-22-acting-as-and-honest-moving-fallback-design.md` §2, §4.1, §4.2, §6. All commands run from `repos/my-plants-api/`.

---

### Task 1: Add `actingAsOwnerId` to the Actor

**Files:**
- Modify: `src/auth/actor.ts`

- [ ] **Step 1:** Add the optional field to the `Actor` interface (after `role`):

```ts
export interface Actor {
  userId: string;
  username: string;
  ownerId: string;
  role: 'USER' | 'ADMIN';
  // The impersonation target, set by the guard ONLY when role === 'ADMIN' and a valid
  // X-Act-As-Owner header is present. OwnerService trusts this: a USER actor never carries it.
  actingAsOwnerId?: string;
  jti: string;
  exp: number;
}
```

- [ ] **Step 2 (verify):** `npm run build` → PASS (type-only change).

---

### Task 2: OwnerService — effective owner

**Files:**
- Modify: `src/owner/owner.service.ts`
- Modify: `src/owner/owner.service.test.ts`

- [ ] **Step 1: Rewrite the failing tests first.** Replace the `ownerFilter is {} for ADMIN ...` test and add effective-owner cases. In `src/owner/owner.service.test.ts`, replace the existing `it('ownerFilter is {} for ADMIN and {ownerId} for USER', ...)` block with:

```ts
  it('ownerFilter is {ownerId} for USER and for ADMIN (no more {} bypass)', async () => {
    await withActor(cls, { ownerId: 'o1', role: 'USER' }, () => {
      expect(svc.ownerFilter()).toEqual({ ownerId: 'o1' });
    });
    await withActor(cls, { ownerId: 'oAdmin', role: 'ADMIN' }, () => {
      expect(svc.ownerFilter()).toEqual({ ownerId: 'oAdmin' });
    });
  });

  it('acting-as: an ADMIN with actingAsOwnerId scopes to the target for filter and currentOwnerId', async () => {
    await withActor(cls, { ownerId: 'oAdmin', role: 'ADMIN', actingAsOwnerId: 'oTarget' }, () => {
      expect(svc.ownerFilter()).toEqual({ ownerId: 'oTarget' });
      expect(svc.currentOwnerId()).toBe('oTarget');
      expect(svc.currentRole()).toBe('ADMIN'); // role is the REAL role, unaffected by acting-as
      expect(svc.currentActingAsOwnerId()).toBe('oTarget');
    });
  });

  it('currentActingAsOwnerId is null when not impersonating', async () => {
    await withActor(cls, { ownerId: 'o1', role: 'ADMIN' }, () => {
      expect(svc.currentActingAsOwnerId()).toBeNull();
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail.** Run: `npm test -- owner.service.test` → Expected: FAIL (`ownerFilter()` still returns `{}` for ADMIN; `currentActingAsOwnerId` is not a function).

- [ ] **Step 3: Implement the effective-owner logic.** In `src/owner/owner.service.ts`, replace the `currentOwnerId()` and `ownerFilter()` methods and add `currentActingAsOwnerId()`:

```ts
  // The effective owner = the impersonation target when an ADMIN is acting-as, else the actor's
  // own owner. Trusting actor.actingAsOwnerId here is safe: the guard sets it ONLY for an ADMIN.
  private effectiveOwnerId(): string {
    const a = this.require();
    return a.actingAsOwnerId ?? a.ownerId;
  }

  // Synchronous (reads CLS). The single owner a write is stamped against and reads are scoped to.
  currentOwnerId(): string {
    return this.effectiveOwnerId();
  }

  // Prisma `where` fragment for owner scoping. Always constrains by the EFFECTIVE owner — there is
  // no longer an unconstrained ADMIN branch (that was bug B7). Admin reach across owners now comes
  // ONLY from impersonation (actingAsOwnerId), never from a blanket {}.
  ownerFilter(): { ownerId: string } {
    return { ownerId: this.effectiveOwnerId() };
  }

  // The impersonation target, or null when not acting-as (for GET /auth/me).
  currentActingAsOwnerId(): string | null {
    return this.currentActor()?.actingAsOwnerId ?? null;
  }
```

Leave `currentActor()`, `currentRole()` (still `this.require().role` — the REAL role), and `require()` unchanged. Update the `ownerFilter()` return type at its declaration to `{ ownerId: string }`.

- [ ] **Step 4: Run the tests to verify they pass.** Run: `npm test -- owner.service.test` → Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/auth/actor.ts src/owner/owner.service.ts src/owner/owner.service.test.ts
git commit -m "feat(auth): effective-owner scoping (drop ADMIN {} bypass)"
```

---

### Task 3: `AuthService.ownerExists`

**Files:**
- Modify: `src/auth/auth.service.ts`
- Modify: `src/auth/auth.service.test.ts`

- [ ] **Step 1: Write the failing test.** Append to `src/auth/auth.service.test.ts` a focused test (it has a Prisma fake convention — match the existing one in that file; the snippet below shows the intent and the minimal fake shape):

```ts
  it('ownerExists returns true for a known owner and false otherwise', async () => {
    const prisma = { owner: { findUnique: async ({ where }: any) => (where.id === 'o1' ? { id: 'o1' } : null) } } as any;
    const svc = new AuthService(prisma, {} as any);
    expect(await svc.ownerExists('o1')).toBe(true);
    expect(await svc.ownerExists('nope')).toBe(false);
  });
```

(If `AuthService`'s constructor signature differs in that test file's existing setup, reuse that file's existing helper instead of `new AuthService(...)` directly — keep it consistent with the surrounding tests.)

- [ ] **Step 2: Run to verify it fails.** Run: `npm test -- auth.service.test` → Expected: FAIL (`ownerExists` is not a function).

- [ ] **Step 3: Implement.** Add to `src/auth/auth.service.ts` (after `verify`):

```ts
  // Cheap PK existence check used by the guard before honoring an X-Act-As-Owner header, so a bogus
  // target fails early with a controlled 403 instead of a Prisma FK error / 500 on the next write.
  async ownerExists(id: string): Promise<boolean> {
    const owner = await this.prisma.owner.findUnique({ where: { id }, select: { id: true } });
    return owner !== null;
  }
```

- [ ] **Step 4: Run to verify it passes.** Run: `npm test -- auth.service.test` → Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/auth/auth.service.ts src/auth/auth.service.test.ts
git commit -m "feat(auth): AuthService.ownerExists for act-as validation"
```

---

### Task 4: Guard — read, validate & stamp `X-Act-As-Owner`

**Files:**
- Modify: `src/auth/jwt-auth.guard.ts`
- Modify: `src/auth/jwt-auth.guard.test.ts`

- [ ] **Step 1: Write the failing tests.** In `src/auth/jwt-auth.guard.test.ts`, extend the `authSvc` fake to also verify an admin token and to answer `ownerExists`, then add acting-as cases. Replace the existing `authSvc` const with:

```ts
const authSvc = {
  verify: async (t: string) => {
    if (t === 'good') return { sub: 'u1', username: 'carlos', ownerId: 'o1', role: 'USER', jti: 'j', exp: 9999999999 };
    if (t === 'admin') return { sub: 'a1', username: 'root', ownerId: 'oAdmin', role: 'ADMIN', jti: 'j', exp: 9999999999 };
    throw new Error('bad');
  },
  ownerExists: async (id: string) => id === 'oTarget',
} as any;
```

Add these tests inside the `describe('JwtAuthGuard', ...)` block:

```ts
  const ctxWith = (auth: string, actAs?: string) => {
    const req = { headers: { authorization: auth, ...(actAs !== undefined ? { 'x-act-as-owner': actAs } : {}) } } as any;
    return {
      req,
      context: { getHandler: () => ({}), getClass: () => ({}), switchToHttp: () => ({ getRequest: () => req }) } as any,
    };
  };

  it('an ADMIN with a valid x-act-as-owner gets actingAsOwnerId set', async () => {
    const g = new JwtAuthGuard(reflector(false), authSvc, cls);
    await cls.run(async () => {
      const { req, context } = ctxWith('Bearer admin', 'oTarget');
      expect(await g.canActivate(context)).toBe(true);
      expect(req.user.actingAsOwnerId).toBe('oTarget');
      expect((cls.get('actor') as any).actingAsOwnerId).toBe('oTarget');
    });
  });

  it('an ADMIN acting-as an unknown owner is rejected (403)', async () => {
    const g = new JwtAuthGuard(reflector(false), authSvc, cls);
    await cls.run(async () => {
      const { context } = ctxWith('Bearer admin', 'ghost');
      await expect(g.canActivate(context)).rejects.toThrow();
    });
  });

  it('a USER cannot impersonate: x-act-as-owner is ignored', async () => {
    const g = new JwtAuthGuard(reflector(false), authSvc, cls);
    await cls.run(async () => {
      const { req, context } = ctxWith('Bearer good', 'oTarget');
      expect(await g.canActivate(context)).toBe(true);
      expect(req.user.actingAsOwnerId).toBeUndefined();
    });
  });

  it('an empty / whitespace x-act-as-owner is ignored for an ADMIN', async () => {
    const g = new JwtAuthGuard(reflector(false), authSvc, cls);
    await cls.run(async () => {
      const { req, context } = ctxWith('Bearer admin', '   ');
      expect(await g.canActivate(context)).toBe(true);
      expect(req.user.actingAsOwnerId).toBeUndefined();
    });
  });
```

- [ ] **Step 2: Run to verify they fail.** Run: `npm test -- jwt-auth.guard.test` → Expected: FAIL (guard does not read the header yet).

- [ ] **Step 3: Implement.** In `src/auth/jwt-auth.guard.ts`, import `ForbiddenException` and insert the header handling **after** building `actor` and **before** `this.cls.set(ACTOR_KEY, actor)`:

```ts
import { CanActivate, ExecutionContext, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
```

```ts
    // Acting As: honor X-Act-As-Owner ONLY for an ADMIN (a USER's header is ignored — no escalation).
    // Validate existence here so a bogus target fails with a controlled 403 instead of a later FK/500.
    const actAs = req.headers?.['x-act-as-owner'];
    if (actor.role === 'ADMIN' && typeof actAs === 'string' && actAs.trim().length > 0) {
      const target = actAs.trim();
      if (!(await this.auth.ownerExists(target))) {
        throw new ForbiddenException('Unknown act-as owner');
      }
      actor.actingAsOwnerId = target;
    }
    this.cls.set(ACTOR_KEY, actor);
    req.user = actor;
    return true;
```

(Replace the existing final three lines — `this.cls.set(...)`, `req.user = actor;`, `return true;` — with the block above so the header handling precedes them.)

- [ ] **Step 4: Run to verify they pass.** Run: `npm test -- jwt-auth.guard.test` → Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/auth/jwt-auth.guard.ts src/auth/jwt-auth.guard.test.ts
git commit -m "feat(auth): guard honors role-gated X-Act-As-Owner with existence check"
```

---

### Task 5: Rewrite ownership tests broken by dropping the `{}` bypass

**Context:** Five tests asserted "an ADMIN reaches any owner" via the old `{}`. Under the new model an ADMIN defaults to own-scope and reaches another owner ONLY by impersonating (an actor with `actingAsOwnerId`). The in-memory Prisma fakes already honor `where.ownerId`, so setting `actingAsOwnerId` on the actor makes `ownerFilter()` return `{ ownerId: target }` and the fake returns that owner's rows.

**Files:**
- Modify: `src/cities/cities.service.ownership.test.ts`
- Modify: `src/places/places.service.ownership.test.ts`
- Modify: `src/plants/plants.service.ownership.test.ts`
- Modify: `src/plants/plants.service.edit.test.ts`

- [ ] **Step 1: cities.** In `src/cities/cities.service.ownership.test.ts`, replace the `it('an ADMIN can read any owner city', ...)` test and the `it('makePrimary as ADMIN on another owner city scopes the reset to THAT owner only', ...)` test with acting-as equivalents:

```ts
  it('an ADMIN defaults to own-scope and cannot read another owner city', async () => {
    const { svc, run } = setup();
    await run(actor('owner-1', 'ADMIN'), async () => {
      await expect(svc.get('o2-a')).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  it('an ADMIN acting-as another owner can read that owner city', async () => {
    const { svc, run } = setup();
    await run({ ...actor('owner-1', 'ADMIN'), actingAsOwnerId: 'owner-2' }, async () => {
      expect((await svc.get('o2-a')).id).toBe('o2-a');
    });
  });

  it('makePrimary while acting-as scopes the reset to the TARGET owner only', async () => {
    const { svc, cities, run } = setup();
    await run({ ...actor('owner-1', 'ADMIN'), actingAsOwnerId: 'owner-2' }, async () => {
      await svc.makePrimary('o2-b');
    });
    expect(cities.find((c) => c.id === 'o2-b')!.isPrimary).toBe(true);
    expect(cities.find((c) => c.id === 'o2-a')!.isPrimary).toBe(false);
    expect(cities.find((c) => c.id === 'o1-a')!.isPrimary).toBe(true); // owner-1 untouched
  });
```

Also update the `it('creation stamps the acting actor ownerId and scopes the isPrimary reset to that owner', ...)` test: it runs as ADMIN with NO `actingAsOwnerId`, so `currentOwnerId()` is now `owner-1` (own) — the assertions (`created.ownerId === 'owner-1'`, owner-2 untouched) already hold; leave it as-is.

- [ ] **Step 2: places.** In `src/places/places.service.ownership.test.ts`, replace `it('an ADMIN can read any owner row', ...)` with:

```ts
  it('an ADMIN defaults to own-scope (cannot read another owner row)', async () => {
    const { svc, run } = setup();
    await run(actor('owner-1', 'ADMIN'), async () => {
      await expect(svc.get('p-other')).rejects.toBeInstanceOf(NotFoundException);
      expect((await svc.list()).map((p: any) => p.id)).toEqual(['p-own']);
    });
  });

  it('an ADMIN acting-as another owner reads that owner rows', async () => {
    const { svc, run } = setup();
    await run({ ...actor('owner-1', 'ADMIN'), actingAsOwnerId: 'owner-2' }, async () => {
      expect((await svc.get('p-other')).id).toBe('p-other');
      expect((await svc.list()).map((p: any) => p.id)).toEqual(['p-other']);
    });
  });
```

- [ ] **Step 3: plants.** In `src/plants/plants.service.ownership.test.ts`, replace `it('an ADMIN can read any owner plant', ...)` with:

```ts
  it('an ADMIN defaults to own-scope (cannot read another owner plant)', async () => {
    const { svc, run } = setup();
    await run(actor('owner-1', 'ADMIN'), async () => {
      await expect(svc.get('pl-other')).rejects.toBeInstanceOf(NotFoundException);
      expect((await svc.list()).map((p: any) => p.id)).toEqual(['pl-own']);
    });
  });

  it('an ADMIN acting-as another owner reads that owner plant', async () => {
    const { svc, run } = setup();
    await run({ ...actor('owner-1', 'ADMIN'), actingAsOwnerId: 'owner-2' }, async () => {
      expect((await svc.get('pl-other')).id).toBe('pl-other');
      expect((await svc.list()).map((p: any) => p.id)).toEqual(['pl-other']);
    });
  });
```

- [ ] **Step 4: plants edit.** In `src/plants/plants.service.edit.test.ts`, the test `it('an ADMIN can edit another owner plant, validating the target place against the PLANT owner', ...)` relies on the old `{}` bypass (an ADMIN with no impersonation reaching `pl-other`). Make it act-as `owner-2`:

```ts
  it('an ADMIN acting-as another owner can edit that owner plant, validating the target place against the PLANT owner', async () => {
    const { svc, run } = setup();
    await run({ ...actor('owner-1', 'ADMIN'), actingAsOwnerId: 'owner-2' }, async () => {
      // pl-other belongs to owner-2; place-y also belongs to owner-2 → allowed.
      // (keep the body of the original test below this line unchanged)
```

Keep the rest of that test's body (the `svc.update('pl-other', { placeId: 'place-y' })` call and its assertions) exactly as it was — only the `run(...)` actor and the title change.

- [ ] **Step 5 (verify):** Run: `npm test -- ownership` then `npm test -- plants.service.edit` → Expected: PASS for all rewritten tests.

- [ ] **Step 6: Commit.**

```bash
git add src/cities/cities.service.ownership.test.ts src/places/places.service.ownership.test.ts src/plants/plants.service.ownership.test.ts src/plants/plants.service.edit.test.ts
git commit -m "test(auth): ownership tests use acting-as instead of ADMIN {} bypass"
```

---

### Task 6: Full suite green

- [ ] **Step 1 (verify):** Run the whole API suite: `npm test` → Expected: PASS. If any other test fails because it relied on an ADMIN actor reaching another owner via `{}`, fix it the same way (give the actor `actingAsOwnerId: '<that owner>'`, or seed the row under the actor's own owner). Do NOT weaken `OwnerService`.
- [ ] **Step 2 (verify):** `npm run build` → PASS.
- [ ] **Step 3:** If any fix was needed in Step 1, commit it: `git commit -am "test(auth): align remaining tests with effective-owner model"`.

**Note:** `src/care-plan/care-plan.controller.test.ts` should still pass after this phase (it uses `currentRole()` + `currentOwnerId()` with no impersonation, so `currentOwnerId()` resolves to the actor's own owner unchanged). The recompute endpoint itself is re-scoped in Phase 3.
