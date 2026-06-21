# Local Development — MyPlants

> v1 runs **only on localhost**. No Docker, no cloud. MariaDB runs directly on the host.
>
> **The project is now implemented.** For the authoritative, verified run/stop commands, the
> current ports (API 8000, web 8001), the DB credentials, what's already seeded, and the
> deliberate deviations from the original plans, see **`docs/IMPLEMENTATION-STATUS.md`** — it is
> the source of truth for running the app today. The subrepos are local git repos under
> `repos/` (not yet GitHub submodules), so the submodule/push commands below are aspirational
> until the GitHub repos are created.

## Prerequisites

- Node.js LTS + npm.
- A local **MariaDB** server running on the host (installed natively, not via Docker).

## First-time setup

```bash
git clone --recurse-submodules <workspace-repo-url> my-plants
cd my-plants
./scripts/install-all.sh        # npm install in every submodule
```

If you cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

## Database & environment variables

The connection is assembled internally from **separate** variables — never a connection
string. The API reads them from its own `.env` (only `.env.example` is tracked); copy the
example once and the app loads it automatically at startup (via dotenv — no manual `source`):

```bash
cp repos/my-plants-api/.env.example repos/my-plants-api/.env
# .env holds: DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME, PORT, DEFAULT_CITY_TZ, WEB_ORIGIN
#             JWT_SECRET (≥32 chars)   JWT_EXPIRES_IN (e.g. 30d)
```

Fill in the auth variables before starting the API:

| Variable | Notes |
|---|---|
| `JWT_SECRET` | A random string of at least 32 characters. Never commit a real value — only `.env.example` carries a placeholder. |
| `JWT_EXPIRES_IN` | Token TTL. `30d` is the recommended default. |

The web also needs its own `.env`:

```bash
cp repos/my-plants-web/.env.example repos/my-plants-web/.env
# .env holds: NUXT_SESSION_PASSWORD (≥32 chars)   NUXT_API_BASE=http://localhost:8000
```

| Variable | Notes |
|---|---|
| `NUXT_SESSION_PASSWORD` | At least 32 characters. Used by `nuxt-auth-utils` to seal the `httpOnly` session cookie. |
| `NUXT_API_BASE` | The NestJS server URL from Nitro's perspective. Default `http://localhost:8000`. |

Prisma's CLI needs a composed `DATABASE_URL`; `npm run prisma:env` generates it into a
**separate** `prisma/.env` (so it never overwrites the app's `.env`). `prisma:generate` and
`prisma:migrate` run that step for you.

Create the database and user once in your local MariaDB, then apply the API's Prisma
migrations (including **migration 0006** which adds the `users` and `revoked_tokens` tables):

```bash
npm --prefix repos/my-plants-api run prisma:migrate
```

### Creating a user account

There is no self-service registration. Users are created via an operator script:

```bash
npm --prefix repos/my-plants-api run user:create -- \
  --username <username> \
  --password <password> \
  --role admin \
  [--adopt-default]
```

The `--adopt-default` flag links the new user to the pre-existing `"default"` owner row so
all existing local seed data (places, plants) is immediately visible under this account.
Without it, a fresh `Owner` row is created (empty garden).

To list all accounts (no password material):

```bash
npm --prefix repos/my-plants-api run user:list
```

### Route protection

All routes require login **except** the blog (`/blog`, `/blog/:id`). Unauthenticated
navigation is redirected to `/login`. The public API surface is `POST /auth/login`,
`GET /species`, and `GET /species/:slug/brief` — everything else needs a bearer token.

### Architecture note: the BFF

The browser never holds the JWT. It speaks only to the Nuxt server (Nitro), which seals the
token in an `httpOnly` session cookie and proxies every API call to NestJS, attaching the
bearer automatically. See the "Authentication / login wall" section of `docs/architecture.md`
for the full design.

## Running

```bash
./run.sh            # start API + web in parallel (prefixed output)
./run.sh --api      # API only
./run.sh --web      # web only
```

MariaDB must be running before `./run.sh`.

## Testing

```bash
./scripts/test-all.sh                                  # whole workspace
npm --prefix repos/my-plants-species-schema test       # a single repo
```

- `my-plants-species-schema` / `my-plants-knowledge-engine` / `my-plants-api`: `npm test`.
- `my-plants-web`: `npm run build` (build + typecheck).

## Curating a species (knowledge engine)

Open a Claude session inside `repos/my-plants-knowledge-engine` (it has its own `CLAUDE.md`)
and follow its onboarding workflow: give a scientific name, it researches, validates against
the schema, and writes `species/<slug>/record.json` + `brief.md`.

## Workspace scripts

| Script | Purpose |
|---|---|
| `./scripts/pull-all.sh` | Sync workspace + all submodules to latest `main` |
| `./scripts/install-all.sh` | `npm install` in every submodule |
| `./scripts/status-all.sh` | Git status across workspace + submodules |
| `./scripts/test-all.sh` | Run every submodule's test/verify command |
| `./scripts/pack-species-schema-and-install.sh` | Pack the shared schema and install it into its consumers |
