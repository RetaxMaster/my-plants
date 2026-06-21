# Auth Phase 2 — Auth module (login / logout / me) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the authentication building blocks — bcrypt hashing, JWT sign/verify with a revocation blocklist, and the `auth` endpoints — WITHOUT turning on global enforcement yet (that is Phase 3).

**Architecture:** `AuthService` signs JWTs (`{ sub, ownerId, role, jti }`, `exp` from `JWT_EXPIRES_IN`), verifies them (signature + expiry + blocklist), and revokes on logout by inserting the `jti` into `revoked_tokens`. `@nestjs/jwt`'s `JwtModule` is wired to the existing custom `ENV` provider (this repo has NO `@nestjs/config`). A `@Public()` decorator marks open routes for Phase 3's guard.

**Tech Stack:** NestJS, `@nestjs/jwt`, `bcrypt`, Prisma, Vitest + supertest.

**Repo:** `repos/my-plants-api`. Branch: `feature/user-auth`.

---

### Task 1: Install dependencies

**Files:** `package.json`

- [ ] **Step 1: Install**

Run: `npm install @nestjs/jwt bcrypt && npm install -D @types/bcrypt`
Expected: added to `package.json`.

- [ ] **Step 2: Commit**

```bash
git add package.json package-lock.json
git commit -m "chore(auth): add @nestjs/jwt, bcrypt deps"
```

---

### Task 2: `@Public()` decorator

**Files:**
- Create: `src/auth/public.decorator.ts`

- [ ] **Step 1: Implement**

```ts
import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
```

- [ ] **Step 2: Commit**

```bash
git add src/auth/public.decorator.ts
git commit -m "feat(auth): @Public() route marker"
```

---

### Task 3: `AuthService` — hashing, sign, verify, revoke

**Files:**
- Create: `src/auth/auth.service.ts`
- Test: `src/auth/auth.service.test.ts`

- [ ] **Step 1: Write the failing test**

Use a Prisma test client (the repo's existing test DB pattern) or a typed fake. Prefer a small fake of the two Prisma delegates used (`user`, `revokedToken`) plus a real `JwtService` with a test secret.

```ts
import { describe, expect, it, beforeEach } from 'vitest';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service.js';

function makePrismaFake() {
  const revoked = new Map<string, { jti: string; expiresAt: Date }>();
  return {
    revoked,
    user: { findUnique: async ({ where }: any) => (globalThis as any).__user?.username === where.username ? (globalThis as any).__user : null },
    revokedToken: {
      findUnique: async ({ where }: any) => revoked.get(where.jti) ?? null,
      create: async ({ data }: any) => { revoked.set(data.jti, data); return data; },
      deleteMany: async () => ({ count: 0 }),
    },
  };
}

const jwt = new JwtService({ secret: 'x'.repeat(32), signOptions: { expiresIn: '30d' } });

describe('AuthService', () => {
  let svc: AuthService;
  let prisma: ReturnType<typeof makePrismaFake>;
  beforeEach(async () => {
    prisma = makePrismaFake();
    svc = new AuthService(prisma as any, jwt);
    (globalThis as any).__user = {
      id: 'u1', username: 'carlos', role: 'ADMIN', ownerId: 'o1',
      passwordHash: await bcrypt.hash('secret', 10),
    };
  });

  it('login returns a token + user for correct credentials', async () => {
    const r = await svc.login('carlos', 'secret');
    expect(r.user).toEqual({ username: 'carlos', role: 'ADMIN' });
    const payload = await svc.verify(r.token);
    expect(payload.sub).toBe('u1');
    expect(payload.ownerId).toBe('o1');
    expect(payload.role).toBe('ADMIN');
    expect(payload.jti).toBeTruthy();
  });

  it('login rejects a wrong password', async () => {
    await expect(svc.login('carlos', 'nope')).rejects.toThrow();
  });

  it('login rejects an unknown user', async () => {
    await expect(svc.login('ghost', 'secret')).rejects.toThrow();
  });

  it('verify rejects a revoked token', async () => {
    const r = await svc.login('carlos', 'secret');
    const payload = await svc.verify(r.token);
    await svc.logout(payload.jti, payload.exp);
    await expect(svc.verify(r.token)).rejects.toThrow();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run src/auth/auth.service.test.ts`
Expected: FAIL (AuthService not implemented).

- [ ] **Step 3: Implement `AuthService`**

```ts
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service.js';

export interface JwtPayload { sub: string; username: string; ownerId: string; role: 'USER' | 'ADMIN'; jti: string; iat: number; exp: number; }

@Injectable()
export class AuthService {
  constructor(private readonly prisma: PrismaService, private readonly jwt: JwtService) {}

  async login(username: string, password: string): Promise<{ token: string; user: { username: string; role: 'USER' | 'ADMIN' } }> {
    const user = await this.prisma.user.findUnique({ where: { username } });
    const ok = user && (await bcrypt.compare(password, user.passwordHash));
    if (!user || !ok) throw new UnauthorizedException('Invalid credentials'); // generic — no user enumeration
    await this.purgeExpired();
    const token = await this.jwt.signAsync({ sub: user.id, username: user.username, ownerId: user.ownerId, role: user.role, jti: randomUUID() });
    return { token, user: { username: user.username, role: user.role } };
  }

  async verify(token: string): Promise<JwtPayload> {
    let payload: JwtPayload;
    try { payload = await this.jwt.verifyAsync<JwtPayload>(token); }
    catch { throw new UnauthorizedException('Invalid token'); }
    const revoked = await this.prisma.revokedToken.findUnique({ where: { jti: payload.jti } });
    if (revoked) throw new UnauthorizedException('Token revoked');
    return payload;
  }

  async logout(jti: string, exp: number): Promise<void> {
    // exp is seconds-since-epoch from the JWT; bind a native Date (MariaDB date rule).
    try { await this.prisma.revokedToken.create({ data: { jti, expiresAt: new Date(exp * 1000) } }); }
    catch { /* already revoked — idempotent */ }
  }

  async purgeExpired(): Promise<void> {
    await this.prisma.revokedToken.deleteMany({ where: { expiresAt: { lt: new Date() } } });
  }
}
```

> Note: if the test's Prisma fake shape diverges from `PrismaService`, adjust the fake — never weaken the service types.

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx vitest run src/auth/auth.service.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/auth/auth.service.ts src/auth/auth.service.test.ts
git commit -m "feat(auth): AuthService — bcrypt login, JWT sign/verify, revoke"
```

---

### Task 4: `AuthController` + `AuthModule` (JwtModule wired to ENV)

**Files:**
- Create: `src/auth/auth.controller.ts`, `src/auth/auth.module.ts`
- Modify: `src/app.module.ts`

- [ ] **Step 1: Implement the controller**

```ts
import { Body, Controller, Get, Post, Req, UnauthorizedException } from '@nestjs/common';
import { AuthService } from './auth.service.js';
import { Public } from './public.decorator.js';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post('login')
  login(@Body() body: { username: string; password: string }) {
    return this.auth.login(body.username, body.password);
  }

  @Post('logout')
  async logout(@Req() req: any) {
    const p = req.user; // set by the guard in Phase 3
    if (!p) throw new UnauthorizedException();
    await this.auth.logout(p.jti, p.exp);
    return { ok: true };
  }

  @Get('me')
  me(@Req() req: any) {
    const p = req.user;
    if (!p) throw new UnauthorizedException();
    return { username: p.username, role: p.role }; // username now travels in the JWT/actor
  }
}
```

> `req.user` is populated by Phase 3's guard. Until then, `logout`/`me` are exercised via Phase 3 e2e. A login DTO with class-validator may be added; keep it minimal here.

- [ ] **Step 2: Implement the module (JwtModule via the custom ENV provider)**

```ts
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ENV } from '../config/config.module.js';
import type { Env } from '../config/env.js';
import { AuthService } from './auth.service.js';
import { AuthController } from './auth.controller.js';

@Module({
  imports: [
    JwtModule.registerAsync({
      inject: [ENV],
      useFactory: (env: Env) => ({ secret: env.JWT_SECRET, signOptions: { expiresIn: env.JWT_EXPIRES_IN } }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService],
  exports: [AuthService],
})
export class AuthModule {}
```

- [ ] **Step 3: Register `AuthModule` in `AppModule`**

Add `AuthModule` to the `imports` array in `src/app.module.ts`.

- [ ] **Step 4: Build + run the suite**

Run: `npm run build && npm test`
Expected: compiles; existing tests still green (no global guard yet, so endpoints behave as before plus the new `auth/*` routes exist).

- [ ] **Step 5: Commit**

```bash
git add src/auth/auth.controller.ts src/auth/auth.module.ts src/app.module.ts
git commit -m "feat(auth): AuthController + AuthModule (JwtModule via ENV)"
```
