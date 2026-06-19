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
```

Prisma's CLI needs a composed `DATABASE_URL`; `npm run prisma:env` generates it into a
**separate** `prisma/.env` (so it never overwrites the app's `.env`). `prisma:generate` and
`prisma:migrate` run that step for you.

Create the database and user once in your local MariaDB, then apply the API's Prisma
migrations: `npm --prefix repos/my-plants-api run prisma:migrate`.

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
