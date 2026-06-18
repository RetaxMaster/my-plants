# Local Development — MyPlants

> v1 runs **only on localhost**. No Docker, no cloud. MariaDB runs directly on the host.
> Some commands below reference submodules that may not exist yet while the project is being
> built out; they become live as each repo is added under `repos/`.

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
string. Each service reads them from its own `.env` (only `.env.example` is tracked):

```bash
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=my_plants
DB_PASSWORD=<local password>
DB_NAME=my_plants
```

Create the database and user once in your local MariaDB, then apply the API's Prisma
migrations (command documented in `repos/my-plants-api` once it exists).

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
