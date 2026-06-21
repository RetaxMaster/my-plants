# Auth Phase 3 — Global guard, CLS actor, ownership + admin bypass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn on the login wall server-side: a global JWT guard, a per-request actor in CLS, ownership enforcement with a per-operation admin bypass, and a system-job (cron/startup) refactor so owner-agnostic jobs never read the actor.

**Architecture:** `nestjs-cls` establishes a per-request store (mounted as middleware → exists before guards). A global `JwtAuthGuard` verifies the bearer (or allows `@Public()` routes), then writes `{ userId, ownerId, role, jti, exp, username? }` into CLS and `req.user`. `OwnerService` is refactored to read the actor from CLS (`currentOwnerId`, `currentRole`, `ownerFilter`). Services apply ownership by operation kind. `MovingService.applyDueMoves` is split into an all-owners job form. `CarePlanController.recompute` gates a system-wide sweep on role.

**Tech Stack:** NestJS, `nestjs-cls`, Vitest + supertest.

**Repo:** `repos/my-plants-api`. Branch: `feature/user-auth`.

---

### Task 1: Install + register `nestjs-cls`

**Files:** `package.json`, `src/app.module.ts`

- [ ] **Step 1: Install**

Run: `npm install nestjs-cls`

- [ ] **Step 2: Register globally (middleware-mounted, so CLS exists before guards)**

In `src/app.module.ts` imports:

```ts
import { ClsModule } from 'nestjs-cls';
// ...
ClsModule.forRoot({ global: true, middleware: { mount: true } }),
```

- [ ] **Step 3: Commit**

```bash
git add package.json package-lock.json src/app.module.ts
git commit -m "chore(auth): add nestjs-cls (per-request store)"
```

---

### Task 2: Refactor `OwnerService` to read the CLS actor

**Files:**
- Modify: `src/owner/owner.service.ts`
- Test: `src/owner/owner.service.test.ts`

Actor shape stored in CLS under key `'actor'`: `{ userId: string; username: string; ownerId: string; role: 'USER'|'ADMIN'; jti: string; exp: number }`. Define and export an `Actor` type (e.g. in `src/auth/actor.ts`).

- [ ] **Step 1: Write the failing test** (CLS run wrapper)

```ts
import { describe, expect, it } from 'vitest';
import { AsyncLocalStorage } from 'node:async_hooks';
import { ClsService } from 'nestjs-cls';
import { OwnerService } from './owner.service.js';

function withActor<T>(cls: ClsService, actor: any, fn: () => T): Promise<T> {
  return cls.run(async () => { cls.set('actor', actor); return fn(); });
}

describe('OwnerService (actor-aware)', () => {
  // ClsService takes an AsyncLocalStorage, NOT a Map (a Map has no .run()).
  const cls = new ClsService(new AsyncLocalStorage());
  const svc = new OwnerService(cls);

  it('currentOwnerId returns the actor ownerId', async () => {
    await withActor(cls, { ownerId: 'o1', role: 'USER' }, () => {
      expect(svc.currentOwnerId()).toBe('o1');
    });
  });

  it('ownerFilter is {} for ADMIN and {ownerId} for USER', async () => {
    await withActor(cls, { ownerId: 'o1', role: 'ADMIN' }, () => {
      expect(svc.ownerFilter()).toEqual({});
    });
    await withActor(cls, { ownerId: 'o1', role: 'USER' }, () => {
      expect(svc.ownerFilter()).toEqual({ ownerId: 'o1' });
    });
  });

  it('currentOwnerId throws with no actor', async () => {
    await cls.run(async () => { expect(() => svc.currentOwnerId()).toThrow(); });
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/owner/owner.service.test.ts`
Expected: FAIL.

- [ ] **Step 3: Implement (sync, reads CLS)**

```ts
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { AsyncLocalStorage } from 'node:async_hooks';
import { ClsService } from 'nestjs-cls';
import type { Actor } from '../auth/actor.js';

@Injectable()
export class OwnerService {
  constructor(private readonly cls: ClsService) {}

  currentActor(): Actor | null { return this.cls.get('actor') ?? null; }

  private require(): Actor {
    const a = this.currentActor();
    if (!a) throw new UnauthorizedException('No authenticated actor');
    return a;
  }

  currentOwnerId(): string { return this.require().ownerId; }
  currentRole(): 'USER' | 'ADMIN' { return this.require().role; }
  ownerFilter(): { ownerId: string } | Record<string, never> {
    const a = this.require();
    return a.role === 'ADMIN' ? {} : { ownerId: a.ownerId };
  }
}
```

> **Breaking signature change:** `currentOwnerId()` is now synchronous. All call sites currently do `await this.owner.currentOwnerId()` — `await` on a non-promise is harmless, but update them to drop `await` where touched (Tasks 5-6). The `OwnerModule` provider now depends on `ClsService` (provided globally by `ClsModule`).

- [ ] **Step 4: Run to verify it passes**, then commit.

```bash
git add src/auth/actor.ts src/owner/owner.service.ts src/owner/owner.service.test.ts
git commit -m "feat(auth): OwnerService reads CLS actor (currentOwnerId/role/ownerFilter)"
```

---

### Task 3: Global `JwtAuthGuard`

**Files:**
- Create: `src/auth/jwt-auth.guard.ts`
- Modify: `src/app.module.ts` (register as `APP_GUARD`)
- Test: `src/auth/jwt-auth.guard.test.ts`

- [ ] **Step 1: Write the failing test** — cover: `@Public()` allows without token; missing/invalid token → 401; valid token sets actor in CLS and `req.user`, returns true. Use a stub `Reflector`, a fake `AuthService.verify`, a `ClsService`, and a fake `ExecutionContext` exposing `switchToHttp().getRequest()` with a `headers.authorization`.

```ts
import { describe, expect, it } from 'vitest';
import { AsyncLocalStorage } from 'node:async_hooks';
import { ClsService } from 'nestjs-cls';
import { JwtAuthGuard } from './jwt-auth.guard.js';

const reflector = (isPublic: boolean) => ({ getAllAndOverride: () => isPublic }) as any;
const authSvc = { verify: async (t: string) => t === 'good' ? { sub: 'u1', ownerId: 'o1', role: 'USER', jti: 'j', exp: 9999999999 } : (() => { throw new Error('bad'); })() } as any;
const ctx = (auth?: string) => ({
  getHandler: () => ({}), getClass: () => ({}),
  switchToHttp: () => ({ getRequest: () => ({ headers: auth ? { authorization: auth } : {} } as any) }),
}) as any;

describe('JwtAuthGuard', () => {
  // ClsService takes an AsyncLocalStorage, NOT a Map (a Map has no .run()).
  const cls = new ClsService(new AsyncLocalStorage());
  it('allows @Public() without a token', async () => {
    const g = new JwtAuthGuard(reflector(true), authSvc, cls);
    await cls.run(async () => expect(await g.canActivate(ctx())).toBe(true));
  });
  it('rejects a missing token on a protected route', async () => {
    const g = new JwtAuthGuard(reflector(false), authSvc, cls);
    await cls.run(async () => { await expect(g.canActivate(ctx())).rejects.toThrow(); });
  });
  it('accepts a valid token and sets the actor', async () => {
    const g = new JwtAuthGuard(reflector(false), authSvc, cls);
    await cls.run(async () => {
      expect(await g.canActivate(ctx('Bearer good'))).toBe(true);
      expect((cls.get('actor') as any).ownerId).toBe('o1');
    });
  });
});
```

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Implement**

```ts
import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AsyncLocalStorage } from 'node:async_hooks';
import { ClsService } from 'nestjs-cls';
import { AuthService } from './auth.service.js';
import { IS_PUBLIC_KEY } from './public.decorator.js';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly reflector: Reflector, private readonly auth: AuthService, private readonly cls: ClsService) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [ctx.getHandler(), ctx.getClass()]);
    if (isPublic) return true;
    const req = ctx.switchToHttp().getRequest();
    const header: string | undefined = req.headers?.authorization;
    if (!header?.startsWith('Bearer ')) throw new UnauthorizedException('Missing bearer token');
    const payload = await this.auth.verify(header.slice('Bearer '.length));
    const actor = { userId: payload.sub, username: payload.username, ownerId: payload.ownerId, role: payload.role, jti: payload.jti, exp: payload.exp };
    this.cls.set('actor', actor);
    req.user = actor;
    return true;
  }
}
```

- [ ] **Step 4: Register as a global guard** in `src/app.module.ts` providers:

```ts
import { APP_GUARD } from '@nestjs/core';
import { JwtAuthGuard } from './auth/jwt-auth.guard.js';
// providers: [ { provide: APP_GUARD, useClass: JwtAuthGuard } ]
```

Ensure `AuthModule` exports `AuthService` and is imported where the guard resolves it (the guard is in `AuthModule`; register the `APP_GUARD` provider inside `AuthModule` so `AuthService`/`Reflector`/`ClsService` inject cleanly, OR import `AuthModule` in `AppModule` and add the `APP_GUARD` provider there).

- [ ] **Step 5: Run to verify it passes**, then commit.

```bash
git add src/auth/jwt-auth.guard.ts src/auth/jwt-auth.guard.test.ts src/app.module.ts
git commit -m "feat(auth): global JwtAuthGuard (default-deny, @Public bypass, CLS actor)"
```

---

### Task 4: Mark public routes

**Files:** `src/species/species.controller.ts`, `src/auth/auth.controller.ts` (login already `@Public()`).

- [ ] **Step 1:** Add `@Public()` to `SpeciesController.list()` (`GET /species`) and `brief()` (`GET /species/:slug/brief`). Leave `one()` (`GET /species/:slug`, full record) PROTECTED. Leave `cities/search` PROTECTED (authenticated, not owner-scoped).

- [ ] **Step 2:** In `src/main.ts`, update the stale `// Note: v1 has no auth ...` comment (line ~12) to reflect that auth now exists (global JWT guard; browser talks to the BFF, not the API directly). **Keep** the existing `WEB_ORIGIN` CORS allowance (defensive; harmless under the BFF) per spec §4.6.

- [ ] **Step 3: Commit**

```bash
git add src/species/species.controller.ts src/main.ts
git commit -m "feat(auth): mark public species routes; refresh main.ts auth comment"
```

---

### Task 5: Ownership enforcement by operation kind (services)

**Files (modify + their tests):** `src/places/places.service.ts`, `src/plants/plants.service.ts`, `src/cities/cities.service.ts`, `src/care-plan/care-plan.service.ts` + `care-plan.controller.ts`, `src/feedback/feedback.service.ts`, `src/notifications/notifications.service.ts`.

Apply these rules (see spec §4.5). For each service, write/extend a test asserting USER-vs-ADMIN behavior, then implement.

- [ ] **Step 1: Reads (list/get)** — replace `where: { ownerId }` with `where: { ...this.owner.ownerFilter() }`, and `where: { id, ownerId }` with `where: { id, ...this.owner.ownerFilter() }`. (Drop the now-sync `await` on `currentOwnerId`/`ownerFilter`.)

  **Exception — `MovingService.simulate`** stays on `currentOwnerId()` ("simulate MY garden against a location"), NOT `ownerFilter()`: with `{}` an ADMIN would simulate viability across *every* owner's plants, which is not the feature's intent. Keep simulate owner-scoped to the actor; document this inline.

- [ ] **Step 2: Single-row mutations** (feedback record, plant/place/city get-before-mutate) — resolve the target with `{ id, ...ownerFilter() }`, then mutate by `id`.

- [ ] **Step 3: Per-owner sweep — `CitiesService.makePrimary(id)`** — load the target city via `get(id)` (which uses `ownerFilter()` for the access check), then scope the `isPrimary` reset to **that city's owner**:

```ts
async makePrimary(id: string) {
  const city = await this.get(id); // access check (USER: own only; ADMIN: any)
  return this.prisma.$transaction(async (tx) => {
    await tx.city.updateMany({ where: { ownerId: city.ownerId }, data: { isPrimary: false } });
    return tx.city.update({ where: { id }, data: { isPrimary: true } });
  });
}
```

- [ ] **Step 4: Creation** — set `ownerId: this.owner.currentOwnerId()` and validate parent FKs against **that** ownerId (NOT `ownerFilter()`):
  - `PlacesService.create`: `cityId` must belong to `currentOwnerId()`; the `isPrimary` reset (if any) scoped to `currentOwnerId()`.
  - `PlantsService.create`: `placeId` must belong to `currentOwnerId()`.
  - `CitiesService.create`: `isPrimary` reset scoped to `currentOwnerId()`.

- [ ] **Step 5: `notifications.service.ts`** — keep `pending()` per-actor: `const ownerId = this.owner.currentOwnerId();` (drop `await`). No admin bypass.

- [ ] **Step 6: Tests** — for plants/places/cities add a test proving: a USER actor cannot read/mutate another owner's row (NotFound), an ADMIN actor can, and creation always stamps the actor's ownerId. Run them via the CLS `withActor` wrapper (Task 2 helper) with a real/seeded Prisma test client.

- [ ] **Step 7: Commit** (one commit per service is fine)

```bash
git add src/places src/plants src/cities src/feedback src/notifications
git commit -m "feat(auth): enforce ownership with per-operation admin bypass"
```

---

### Task 6: System jobs — owner-agnostic `applyDueMoves` + recompute gating

**Files:**
- Modify: `src/moving/moving.service.ts`, `src/moving/moving.cron.ts`, `src/startup/startup.service.ts`, `src/care-plan/care-plan.service.ts`, `src/care-plan/care-plan.controller.ts`
- Test: `src/moving/moving.service.simulate.test.ts` (extend) or a new `moving.service.apply.test.ts`; `src/care-plan/*.test.ts`

- [ ] **Step 1: Write the failing test** — `applyAllDueMoves(now)` applies due moves for *every* owner (seed two owners each with a due move) and calls `recomputeAll()` once; it does NOT read the CLS actor (run it OUTSIDE any `cls.run`, proving no crash).

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Implement the split** in `moving.service.ts`:

```ts
async applyDueMovesForOwner(ownerId: string, now: Date): Promise<number> {
  const primary = await this.prisma.city.findFirst({ where: { ownerId, isPrimary: true } });
  const cutoff = startOfTomorrowUtc(primary?.timezone ?? 'UTC', now);
  const due = await this.prisma.scheduledMove.findMany({ where: { ownerId, applied: false, moveOn: { lt: cutoff } }, orderBy: { moveOn: 'asc' } });
  for (const move of due) {
    await this.prisma.$transaction(async (tx) => {
      await tx.city.updateMany({ where: { ownerId }, data: { isPrimary: false } });
      await tx.city.update({ where: { id: move.targetCityId }, data: { isPrimary: true } });
      await tx.place.updateMany({ where: { ownerId, indoor: false }, data: { cityId: move.targetCityId } });
      await tx.scheduledMove.update({ where: { id: move.id }, data: { applied: true } });
    });
  }
  return due.length; // NOTE: no recompute here
}

async applyAllDueMoves(now: Date = new Date()): Promise<number> {
  const owners = await this.prisma.owner.findMany({ select: { id: true } });
  let total = 0;
  for (const o of owners) total += await this.applyDueMovesForOwner(o.id, now);
  if (total > 0) await this.carePlan.recomputeAll();
  return total;
}
```

Keep a request-scoped `applyDueMoves(now)` ONLY if a request path needs it; otherwise remove it. The HTTP `POST /moving/schedule` path is unaffected (it still uses `currentOwnerId()`).

- [ ] **Step 4: Repoint callers** — `MovingCron.daily()` → `this.moving.applyAllDueMoves()`; `StartupService.onApplicationBootstrap()` → `applied = await this.moving.applyAllDueMoves(new Date())` (rest of the boot logic unchanged).

- [ ] **Step 5: Recompute role-gating** — add `CarePlanService.recomputeOwner(ownerId)` (filters plants by owner). In `CarePlanController.recompute()`:

```ts
@Post('recompute')
async recompute() {
  if (this.owner.currentRole() === 'ADMIN') await this.carePlan.recomputeAll();
  else await this.carePlan.recomputeOwner(this.owner.currentOwnerId());
  return { ok: true };
}
```

(Inject `OwnerService` into `CarePlanController`.)

- [ ] **Step 6: Run to verify it passes.**

- [ ] **Step 7: Commit**

```bash
git add src/moving src/startup src/care-plan
git commit -m "feat(auth): owner-agnostic applyAllDueMoves; role-gate recompute"
```

---

### Task 7: Fix existing tests/e2e for the login wall + full suite

**Files:** any existing `*.e2e` / controller tests that hit protected routes without auth.

- [ ] **Step 1:** Update existing tests that exercise protected endpoints to either (a) run within a `cls.run` + set actor when unit-testing services, or (b) for HTTP/e2e via supertest, send a valid `Authorization: Bearer` (mint one with the test `JwtService`/seeded user) — or mark the test's app with a seeded admin and log in first.

  **Concretely, these existing fakes use an async `currentOwnerId` and lack `ownerFilter` — update them to sync + add `ownerFilter`:**
  - `src/moving/moving.service.simulate.test.ts` (~line 48)
  - `src/plants/plants.service.names.test.ts` (~line 38)
  - `src/moving/moving.service.find-or-create-city.test.ts` (~line 24)

  Transform each `OwnerService` fake from `{ currentOwnerId: vi.fn(async () => 'owner-1') }` to:
  `{ currentOwnerId: () => 'owner-1', currentRole: () => 'USER', ownerFilter: () => ({ ownerId: 'owner-1' }) }`.

  **Note on green state:** the full suite is intentionally partially red from Task 2 (sync `currentOwnerId`) through Task 6; the intermediate "Run to verify it passes" steps refer to the *specific* test under edit. Global green is restored here in Task 7. (Confirmed there is no existing supertest/`.e2e.` suite, so the blast radius is unit tests only.)

- [ ] **Step 2: Run the full suite**

Run: `npm test`
Expected: all green (login wall on; tests authenticate).

- [ ] **Step 3: Build + typecheck**

Run: `npm run build`
Expected: success.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test(auth): authenticate existing tests under the login wall"
```
