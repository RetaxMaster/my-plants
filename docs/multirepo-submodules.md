# Multirepo + Git Submodules Workflow

> **Template note.** Project-agnostic procedure for a Git multirepo orchestrator. Replace `<PROJECT_NAME>` and the example submodule paths/scripts with the project's real ones, then delete this note. The constitution (`CLAUDE.md` / `AGENTS.md`) holds the short *Multi-repo feature workflow* rule and points here for the full mechanics — keep that split: the rule + essential commands live there, the exhaustive procedure lives here. If the project is single-repo, this doc does not apply.

## Purpose

The workspace root coordinates the complete `<PROJECT_NAME>` system while each product repo keeps its own Git history. Product repos are added as **submodules** under a submodules directory (conventionally `apps/` or `repos/` — pick one and keep it consistent). The workspace pins a known-good combination of submodule commits through those submodule entries; it never holds product code itself.

## Daily start

```bash
git pull --ff-only
git submodule update --init --recursive
./scripts/status-all.sh
```

## Updating all repos to latest main

```bash
./scripts/pull-all.sh
```

## Starting a cross-repo feature

Branch **only** in the repos the feature actually touches, with the same branch name in each:

```bash
FEATURE=feature/my-feature

git -C apps/<submodule-a> checkout main && git -C apps/<submodule-a> pull --ff-only origin main
git -C apps/<submodule-a> checkout -b "$FEATURE"

# repeat for each submodule the feature touches
git -C apps/<submodule-b> checkout main && git -C apps/<submodule-b> pull --ff-only origin main
git -C apps/<submodule-b> checkout -b "$FEATURE"
```

The workspace root only needs its own branch if the change also touches root docs/scripts/config.

## Dependency-order rule (shared packages first)

If the feature changes a **shared package** consumed by other repos (a database package, a contracts/messaging package, a shared core), change and release that package *before* the consumers depend on the new contract:

1. change the shared package repo first;
2. run its tests and build/package it (e.g. `npm test` + `npm pack`, or the project's equivalent);
3. install the produced artifact into every affected consumer (or run the project's install script, e.g. `./scripts/pack-<package>-and-install.sh`), and commit the dependency-manifest changes in each;
4. only then implement against the new contract in the runtimes/consumers.

More generally: implement in dependency order — producers (DB, shared packages, backend contracts/endpoints) before the consumers (runtimes, frontends) that depend on them.

## Finishing a cross-repo change

1. Commit each affected submodule.
2. Push each affected branch.
3. Open one PR per submodule (or merge `--ff-only` to `main` and push, per the project's flow).
4. After every submodule PR is merged to its `main`, bump the workspace submodule pointers:

```bash
git -C apps/<submodule-a> checkout main && git -C apps/<submodule-a> pull --ff-only origin main
# repeat for each affected submodule
git add apps/
git commit -m "chore: update submodule pointers after <feature>"
git push origin main
```

**Never skip the pointer bump.** A checkout/deploy that runs `git submodule update` checks out the workspace-pinned commit, so an un-bumped pointer silently reverts the merged work back to the old commit at deploy time. This is the single highest-risk step of the whole workflow.

## Workspace root commits

The root workspace should commit **only**:

- submodule pointer updates;
- docs;
- scripts;
- workspace config;
- architecture decisions.

Never commit product code changes from the workspace root — those belong in each submodule.
