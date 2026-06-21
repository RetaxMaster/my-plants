# Auth Phase 1 — Data model + env split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `User`, `RevokedToken`, `UserRole` data model + migration, and split env validation so Prisma scripts don't require auth secrets. No behavior change yet.

**Architecture:** Two new Prisma models (`users` 1:1 with `owners`, `revoked_tokens` blocklist) via a hand-authored MariaDB migration applied with `prisma:migrate` (= migrate deploy). Env splits into `loadDbEnv()` (DB-only, for Prisma tooling) and full `loadEnv()` (DB + app + `JWT_*`).

**Tech Stack:** NestJS, Prisma (mysql/MariaDB), Zod, Vitest.

**Repo:** `repos/my-plants-api`. Branch: `feature/user-auth`.

---

### Task 1: Prisma schema — User, RevokedToken, UserRole

**Files:**
- Modify: `prisma/schema.prisma`

- [ ] **Step 1: Add the enum + models and the Owner back-relation**

In `prisma/schema.prisma` add:

```prisma
enum UserRole {
  USER
  ADMIN
}

model User {
  id           String   @id @default(cuid())
  username     String   @unique
  passwordHash String   @map("password_hash")
  role         UserRole @default(USER)
  ownerId      String   @unique @map("owner_id")
  owner        Owner    @relation(fields: [ownerId], references: [id])
  createdAt    DateTime @default(now()) @map("created_at")
  @@map("users")
}

model RevokedToken {
  jti       String   @id
  expiresAt DateTime @map("expires_at")
  @@index([expiresAt])
  @@map("revoked_tokens")
}
```

Add to the existing `Owner` model a back-relation field:

```prisma
  user User?
```

- [ ] **Step 2: Generate the Prisma client and confirm it compiles**

Run: `npm run prisma:generate`
Expected: regenerates `@prisma/client` with `User`, `RevokedToken`, `UserRole`. No errors.

- [ ] **Step 3: Commit**

```bash
git add prisma/schema.prisma
git commit -m "feat(auth): add User, RevokedToken, UserRole to Prisma schema"
```

---

### Task 2: Migration `0006_add_users_and_revoked_tokens`

**Files:**
- Create: `prisma/migrations/0006_add_users_and_revoked_tokens/migration.sql`

- [ ] **Step 1: Write the migration SQL (hand-authored, MariaDB conventions)**

```sql
CREATE TABLE `users` (
  `id`            VARCHAR(191) NOT NULL,
  `username`      VARCHAR(191) NOT NULL,
  `password_hash` VARCHAR(191) NOT NULL,
  `role`          ENUM('USER','ADMIN') NOT NULL DEFAULT 'USER',
  `owner_id`      VARCHAR(191) NOT NULL,
  `created_at`    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE INDEX `users_username_key`(`username`),
  UNIQUE INDEX `users_owner_id_key`(`owner_id`),
  PRIMARY KEY (`id`),
  CONSTRAINT `users_owner_id_fkey` FOREIGN KEY (`owner_id`) REFERENCES `owners`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `revoked_tokens` (
  `jti`        VARCHAR(191) NOT NULL,
  `expires_at` DATETIME(3)  NOT NULL,
  INDEX `revoked_tokens_expires_at_idx`(`expires_at`),
  PRIMARY KEY (`jti`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

- [ ] **Step 2: Apply the migration to the local DB**

Run: `npm run prisma:migrate`
Expected: `0006_add_users_and_revoked_tokens` applied; `prisma migrate status` shows it as applied. (Do NOT use `migrate dev` — the scoped DB user lacks the global CREATE needed for the shadow DB; this is the documented project convention.)

- [ ] **Step 3: Verify the tables exist (read-only check)**

Run: `set -a; source .env; set +a; mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SHOW TABLES LIKE 'users'; SHOW TABLES LIKE 'revoked_tokens';"`
Expected: both tables listed.

- [ ] **Step 4: Commit**

```bash
git add prisma/migrations/0006_add_users_and_revoked_tokens/migration.sql
git commit -m "feat(auth): migration 0006 — users + revoked_tokens tables"
```

---

### Task 3: Split env — `loadDbEnv()` (DB-only) and full `loadEnv()` with JWT vars

**Files:**
- Modify: `src/config/env.ts`
- Test: `src/config/env.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest';
import { loadEnv, loadDbEnv } from './env.js';

const DB = { DB_HOST: 'h', DB_PORT: '3306', DB_USER: 'u', DB_PASSWORD: 'p', DB_NAME: 'n' };

describe('loadDbEnv', () => {
  it('parses DB vars without requiring JWT secrets', () => {
    const env = loadDbEnv({ ...DB } as NodeJS.ProcessEnv);
    expect(env.DB_NAME).toBe('n');
  });
});

describe('loadEnv', () => {
  it('requires JWT_SECRET (min 32 chars)', () => {
    expect(() => loadEnv({ ...DB } as NodeJS.ProcessEnv)).toThrow();
    const ok = loadEnv({ ...DB, JWT_SECRET: 'x'.repeat(32) } as NodeJS.ProcessEnv);
    expect(ok.JWT_EXPIRES_IN).toBe('30d'); // default
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run src/config/env.test.ts`
Expected: FAIL (`loadDbEnv` not exported; `loadEnv` doesn't know `JWT_SECRET`).

- [ ] **Step 3: Implement the split**

In `src/config/env.ts`:

```ts
import { z } from 'zod';

const dbSchema = z.object({
  DB_HOST: z.string().min(1),
  DB_PORT: z.coerce.number().int().positive(),
  DB_USER: z.string().min(1),
  DB_PASSWORD: z.string(),
  DB_NAME: z.string().min(1),
});

export const envSchema = dbSchema.extend({
  PORT: z.coerce.number().int().positive().default(3000),
  DEFAULT_CITY_TZ: z.string().min(1).default('America/Mexico_City'),
  JWT_SECRET: z.string().min(32),
  JWT_EXPIRES_IN: z.string().min(1).default('30d'),
});

export type DbEnv = z.infer<typeof dbSchema>;
export type Env = z.infer<typeof envSchema>;

export function loadDbEnv(source: NodeJS.ProcessEnv = process.env): DbEnv {
  return dbSchema.parse(source);
}

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  return envSchema.parse(source);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx vitest run src/config/env.test.ts`
Expected: PASS.

- [ ] **Step 5: Point the Prisma env script at `loadDbEnv()`**

In `scripts/write-prisma-env.ts`, replace the `loadEnv()` call with `loadDbEnv()` (and the import). `buildDatabaseUrl` only reads `DB_*`, so it accepts a `DbEnv`. This keeps `prisma:generate`/`prisma:migrate` from requiring `JWT_SECRET`.

- [ ] **Step 6: Verify Prisma scripts still work without JWT secrets**

Run: `env -u JWT_SECRET npm run prisma:generate`
Expected: succeeds (no JWT_SECRET required for tooling).

- [ ] **Step 7: Commit**

```bash
git add src/config/env.ts src/config/env.test.ts scripts/write-prisma-env.ts
git commit -m "feat(auth): split loadDbEnv/loadEnv; add JWT_SECRET, JWT_EXPIRES_IN"
```

---

### Task 4: `.env.example` placeholders

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: Add auth placeholders**

Append:

```
# Auth (app runtime only; never commit real values)
JWT_SECRET=change-me-to-a-long-random-string-at-least-32-chars
JWT_EXPIRES_IN=30d
```

- [ ] **Step 2: Add the same secrets to local `.env`** so the app can boot (real random value for `JWT_SECRET`). `.env` is gitignored — do NOT commit it.

- [ ] **Step 3: Run the full suite (regression)**

Run: `npm test`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add .env.example
git commit -m "chore(auth): document JWT env vars in .env.example"
```
