# Acting As — Phase 2: Owners Endpoint + `/auth/me` Acting-As Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose the admin-only `GET /owners` picker source (every owner + its linked user's username/role), and extend the API `GET /auth/me` to report the resolved impersonation state.

**Architecture:** A new `OwnersModule` (controller + service) gated by the **real role** (`currentRole() === 'ADMIN'`), reachable without owner scoping because it IS the impersonation picker. `auth.controller.ts` adds `actingAs` to `me` from the request actor.

**Tech Stack:** NestJS, Prisma, Vitest.

**Reference:** spec §4.3, §4.4. `Owner.user` is optional (`User?`); `User.ownerId` is unique (1:1). Mirror `CitiesModule` for wiring (PrismaModule/OwnerModule are global — no explicit import needed). All commands run from `repos/my-plants-api/`.

---

### Task 1: OwnersService (admin-only) + tests

**Files:**
- Create: `src/owners/owners.service.ts`
- Create: `src/owners/owners.service.test.ts`

- [ ] **Step 1: Write the failing test.** Create `src/owners/owners.service.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { AsyncLocalStorage } from 'node:async_hooks';
import { ClsService } from 'nestjs-cls';
import { ForbiddenException } from '@nestjs/common';
import { OwnerService } from '../owner/owner.service.js';
import { OwnersService } from './owners.service.js';

const actor = (ownerId: string, role: 'USER' | 'ADMIN') => ({ userId: 'u', username: 'n', ownerId, role, jti: 'j', exp: 9e9 });

function setup() {
  const cls = new ClsService(new AsyncLocalStorage());
  const owner = new OwnerService(cls);
  const prisma = {
    owner: {
      findMany: async () => [
        { id: 'o1', name: 'Owner One', user: { username: 'retax', role: 'ADMIN' } },
        { id: 'o2', name: 'Headless Owner', user: null }, // owner with no linked user
      ],
    },
  } as any;
  const svc = new OwnersService(prisma, owner);
  const run = <T>(a: any, fn: () => Promise<T>) => cls.run(async () => { cls.set('actor', a); return fn(); });
  return { svc, run };
}

describe('OwnersService', () => {
  it('rejects a USER (403)', async () => {
    const { svc, run } = setup();
    await run(actor('o1', 'USER'), async () => {
      await expect(svc.list()).rejects.toBeInstanceOf(ForbiddenException);
    });
  });

  it('lists every owner with username/role for an ADMIN, falling back to owner name when no user', async () => {
    const { svc, run } = setup();
    const out = await run(actor('o1', 'ADMIN'), () => svc.list());
    expect(out).toEqual([
      { ownerId: 'o1', username: 'retax', role: 'ADMIN' },
      { ownerId: 'o2', username: 'Headless Owner', role: null },
    ]);
  });
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `npm test -- owners.service.test` → Expected: FAIL (module does not exist).

- [ ] **Step 3: Implement.** Create `src/owners/owners.service.ts`:

```ts
import { ForbiddenException, Injectable } from '@nestjs/common';
import { OwnerService } from '../owner/owner.service.js';
import { PrismaService } from '../prisma/prisma.service.js';

export interface OwnerSummary {
  ownerId: string;
  username: string; // the linked user's username, or the owner's name when no user exists
  role: 'USER' | 'ADMIN' | null;
}

@Injectable()
export class OwnersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly owner: OwnerService,
  ) {}

  // Admin-only picker source for "Acting As". NOT owner-scoped (it lists every owner); its safety is
  // the role gate on the REAL role (currentRole), which acting-as never changes.
  async list(): Promise<OwnerSummary[]> {
    if (this.owner.currentRole() !== 'ADMIN') throw new ForbiddenException('Admin only');
    const owners = await this.prisma.owner.findMany({ include: { user: true } });
    return owners.map((o) => ({
      ownerId: o.id,
      username: o.user?.username ?? o.name,
      role: o.user?.role ?? null,
    }));
  }
}
```

- [ ] **Step 4: Run to verify it passes.** Run: `npm test -- owners.service.test` → Expected: PASS.

---

### Task 2: OwnersController + OwnersModule + registration

**Files:**
- Create: `src/owners/owners.controller.ts`
- Create: `src/owners/owners.module.ts`
- Modify: `src/app.module.ts`

- [ ] **Step 1:** Create `src/owners/owners.controller.ts`:

```ts
import { Controller, Get } from '@nestjs/common';
import { OwnersService } from './owners.service.js';

@Controller('owners')
export class OwnersController {
  constructor(private readonly owners: OwnersService) {}

  @Get() list() { return this.owners.list(); }
}
```

- [ ] **Step 2:** Create `src/owners/owners.module.ts` (mirror `CitiesModule`; PrismaModule/OwnerModule are global):

```ts
import { Module } from '@nestjs/common';
import { OwnersController } from './owners.controller.js';
import { OwnersService } from './owners.service.js';

@Module({
  controllers: [OwnersController],
  providers: [OwnersService],
})
export class OwnersModule {}
```

- [ ] **Step 3:** Register it in `src/app.module.ts`: add the import `import { OwnersModule } from './owners/owners.module.js';` and add `OwnersModule,` to the `imports` array (next to `CitiesModule`).

- [ ] **Step 4 (verify):** `npm run build` → PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/owners/ src/app.module.ts
git commit -m "feat(owners): admin-only GET /owners (acting-as picker source)"
```

---

### Task 3: `GET /auth/me` reports acting-as

**Files:**
- Modify: `src/auth/auth.controller.ts`
- Create: `src/auth/auth.controller.test.ts`

- [ ] **Step 1: Write the failing test.** Create `src/auth/auth.controller.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { AuthController } from './auth.controller.js';

describe('AuthController.me', () => {
  const ctrl = new AuthController({} as any);

  it('reports actingAs: null when not impersonating', () => {
    const req = { user: { username: 'carlos', role: 'USER' } } as any;
    expect(ctrl.me(req)).toEqual({ username: 'carlos', role: 'USER', actingAs: null });
  });

  it('reports the acting-as ownerId when impersonating', () => {
    const req = { user: { username: 'root', role: 'ADMIN', actingAsOwnerId: 'oTarget' } } as any;
    expect(ctrl.me(req)).toEqual({ username: 'root', role: 'ADMIN', actingAs: { ownerId: 'oTarget' } });
  });
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `npm test -- auth.controller.test` → Expected: FAIL (`me` does not return `actingAs`).

- [ ] **Step 3: Implement.** In `src/auth/auth.controller.ts`, update the `me` handler:

```ts
  @Get('me')
  me(@Req() req: any) {
    const p = req.user;
    if (!p) throw new UnauthorizedException();
    // Authoritative impersonation state the API actually resolved (id-only). The frontend banner is
    // driven by the BFF session me (which also carries a human label); these stay consistent.
    return {
      username: p.username,
      role: p.role,
      actingAs: p.actingAsOwnerId ? { ownerId: p.actingAsOwnerId } : null,
    };
  }
```

- [ ] **Step 4: Run to verify it passes.** Run: `npm test -- auth.controller.test` → Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/auth/auth.controller.ts src/auth/auth.controller.test.ts
git commit -m "feat(auth): GET /auth/me reports acting-as state"
```

---

### Task 4: Phase verification

- [ ] **Step 1 (verify):** `npm test` → PASS. `npm run build` → PASS.
