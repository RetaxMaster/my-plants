# Auth Phase 4 — User registration script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide the only way users are created — an `npm` script on the API that creates a user (bcrypt-hashed password) and its 1:1 `Owner`, with a role and an optional `--adopt-default` to attach to the pre-existing `"default"` owner locally.

**Architecture:** A standalone `tsx` script (same convention as the Prisma scripts) that loads `.env`, parses CLI args, hashes the password, and creates `Owner` + `User` in one transaction. A `user:list` convenience script prints non-sensitive fields.

**Tech Stack:** `tsx`, Prisma, bcrypt.

**Repo:** `repos/my-plants-api`. Branch: `feature/user-auth`.

---

### Task 1: Extract a small, testable arg-parser + creation core

**Files:**
- Create: `src/auth/create-user.core.ts`
- Test: `src/auth/create-user.core.test.ts`

Keeping the logic in a pure-ish core makes it testable without spawning a process.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest';
import { parseArgs, createUser } from './create-user.core.js';

describe('parseArgs', () => {
  it('parses username/password/role/adopt-default', () => {
    const a = parseArgs(['--username', 'carlos', '--password', 'secret123', '--role', 'admin', '--adopt-default']);
    expect(a).toEqual({ username: 'carlos', password: 'secret123', role: 'ADMIN', adoptDefault: true });
  });
  it('defaults role to USER and adoptDefault false', () => {
    const a = parseArgs(['--username', 'u', '--password', 'pwpwpwpw']);
    expect(a.role).toBe('USER');
    expect(a.adoptDefault).toBe(false);
  });
  it('rejects a short password and missing username', () => {
    expect(() => parseArgs(['--username', 'u', '--password', 'short'])).toThrow();
    expect(() => parseArgs(['--password', 'longenoughpw'])).toThrow();
  });
});

describe('createUser', () => {
  it('hashes the password and creates owner+user (fresh)', async () => {
    const created: any = {};
    const prisma = {
      user: { findUnique: async () => null },
      $transaction: async (fn: any) => fn({
        owner: { create: async ({ data }: any) => { created.owner = data; return { id: 'o1', ...data }; } },
        user: { create: async ({ data }: any) => { created.user = data; return data; } },
      }),
    } as any;
    const r = await createUser(prisma, { username: 'carlos', password: 'secret123', role: 'ADMIN', adoptDefault: false });
    expect(r.username).toBe('carlos');
    expect(created.user.passwordHash).not.toBe('secret123'); // hashed
    expect(created.user.role).toBe('ADMIN');
  });

  it('rejects a duplicate username', async () => {
    const prisma = { user: { findUnique: async () => ({ id: 'x' }) } } as any;
    await expect(createUser(prisma, { username: 'carlos', password: 'secret123', role: 'USER', adoptDefault: false })).rejects.toThrow();
  });
});
```

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Implement the core**

```ts
import * as bcrypt from 'bcrypt';
import type { PrismaClient } from '@prisma/client';

export interface CreateUserArgs { username: string; password: string; role: 'USER' | 'ADMIN'; adoptDefault: boolean; }

export function parseArgs(argv: string[]): CreateUserArgs {
  const get = (flag: string) => { const i = argv.indexOf(flag); return i >= 0 ? argv[i + 1] : undefined; };
  const username = get('--username');
  const password = get('--password');
  const roleRaw = (get('--role') ?? 'user').toLowerCase();
  const adoptDefault = argv.includes('--adopt-default');
  if (!username) throw new Error('--username is required');
  if (!password || password.length < 8) throw new Error('--password is required (min 8 chars)');
  if (roleRaw !== 'user' && roleRaw !== 'admin') throw new Error('--role must be user or admin');
  return { username, password, role: roleRaw === 'admin' ? 'ADMIN' : 'USER', adoptDefault };
}

export async function createUser(prisma: Pick<PrismaClient, 'user' | 'owner' | '$transaction'> | any, args: CreateUserArgs) {
  const existing = await prisma.user.findUnique({ where: { username: args.username } });
  if (existing) throw new Error(`Username already exists: ${args.username}`);
  const passwordHash = await bcrypt.hash(args.password, 12);
  return prisma.$transaction(async (tx: any) => {
    let ownerId: string;
    if (args.adoptDefault) {
      const def = await tx.owner.findFirst({ where: { name: 'default' } });
      ownerId = def ? def.id : (await tx.owner.create({ data: { name: args.username } })).id;
    } else {
      ownerId = (await tx.owner.create({ data: { name: args.username } })).id;
    }
    await tx.user.create({ data: { username: args.username, passwordHash, role: args.role, ownerId } });
    return { username: args.username, role: args.role, ownerId };
  });
}
```

> Note the `--adopt-default` branch needs `owner.findFirst` inside the transaction; widen the `$transaction` fake in the test only if you add a test for that branch.

- [ ] **Step 4: Run to verify it passes**, then commit.

```bash
git add src/auth/create-user.core.ts src/auth/create-user.core.test.ts
git commit -m "feat(auth): create-user core (parseArgs + createUser)"
```

---

### Task 2: The `tsx` entrypoint scripts + npm wiring

**Files:**
- Create: `scripts/create-user.ts`, `scripts/list-users.ts`
- Modify: `package.json`

- [ ] **Step 1: Implement `scripts/create-user.ts`**

```ts
import '../src/config/load-env-file.js';
import { PrismaClient } from '@prisma/client';
import { parseArgs, createUser } from '../src/auth/create-user.core.js';

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const prisma = new PrismaClient();
  try {
    const r = await createUser(prisma, args);
    console.log(`Created user '${r.username}' (role ${r.role}) → owner ${r.ownerId}`);
  } finally { await prisma.$disconnect(); }
}
main().catch((e) => { console.error(e.message ?? e); process.exit(1); });
```

- [ ] **Step 2: Implement `scripts/list-users.ts`**

```ts
import '../src/config/load-env-file.js';
import { PrismaClient } from '@prisma/client';

async function main() {
  const prisma = new PrismaClient();
  try {
    const users = await prisma.user.findMany({ select: { username: true, role: true, createdAt: true }, orderBy: { createdAt: 'asc' } });
    for (const u of users) console.log(`${u.username}\t${u.role}\t${u.createdAt.toISOString()}`);
    if (users.length === 0) console.log('(no users yet)');
  } finally { await prisma.$disconnect(); }
}
main().catch((e) => { console.error(e.message ?? e); process.exit(1); });
```

- [ ] **Step 3: Wire npm scripts** in `package.json`:

```json
"user:create": "tsx scripts/create-user.ts",
"user:list": "tsx scripts/list-users.ts"
```

- [ ] **Step 4: Smoke-test against the local DB** (real path, not a workaround)

Run: `set -a; source .env; set +a && npm run user:create -- --username testuser --password testpass123 --role user`
Expected: prints "Created user 'testuser' ...". Then `npm run user:list` shows it. (This row is local test data; fine.)

- [ ] **Step 5: Run the suite + commit**

Run: `npm test`

```bash
git add scripts/create-user.ts scripts/list-users.ts package.json
git commit -m "feat(auth): user:create + user:list npm scripts"
```
