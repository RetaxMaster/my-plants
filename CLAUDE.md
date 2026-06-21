# CLAUDE.md — MyPlants Workspace

## Workspace overview

MyPlants is a system that tells the owner **what plant-care action to take and when** — watering, fertilizing, repotting, and general maintenance — adapting to each plant's species, its physical spot, and the local climate. It does not perform care; it advises. See `docs/product-vision.md`.

The workspace is a **Git multirepo orchestrator with submodules under `repos/`**. The root holds shared docs, these agent instructions, orchestration scripts (`run.sh`, `scripts/*`), and pins a known-good combination of submodule commits; it holds **no product code**. Submodules are public GitHub repositories under the `RetaxMaster` account:

- `repos/my-plants-species-schema` — the shared data contract (Zod schema + inferred types + validators); the single source of truth for the curated species-record shape, consumed by the other repos.
- `repos/my-plants-knowledge-engine` — a Claude-driven research workspace (its own `CLAUDE.md`) that turns a scientific name into a validated curated species record + a Markdown brief.
- `repos/my-plants-api` — NestJS backend: the deterministic care engine (scheduling, viability semaphore, feedback adaptation, moving) over local MariaDB via Prisma.
- `repos/my-plants-web` — Nuxt 3 + Vue 3 frontend (Nuxt UI).

**Runtime constraints (v1):** local only — no Docker, no cloud. MariaDB runs directly on the host. The care app is **100% deterministic** (no runtime AI, no AI keys in production); all AI lives in the knowledge engine. Single user now, structured so multi-user is an additive change later. Full technical design: `docs/architecture.md` and `docs/superpowers/specs/`.

## Sync rule (highest priority)

`CLAUDE.md` and `AGENTS.md` are kept **byte-for-byte identical**: same content, same detail, same sections — full stop. The only intended difference is this sentence's self-reference: whenever you change **either** file you MUST immediately apply the exact same change to the other so they never diverge. (In this file, `CLAUDE.md` names itself first; the copy in `AGENTS.md` names `AGENTS.md` first. Nothing else may differ except each file's H1 title.) Do not turn either file into a "summary" of the other.

## How to write rules in this file (what + where here, how in `docs/`)

This file is the **constitution**: the imperative rules an agent must always have in context. The detailed **procedure** for each rule lives in `docs/` and is read on demand. When you add or change a rule, follow this:

1. **The "what" must be self-triggering — include the *when* and the *invariant*, not just a label.** A rule must let an agent know it applies AND what must hold true *without* opening the doc. Only the step-by-step *how* goes to the doc.
2. **One source for the "how".** The procedure lives in exactly one doc — never duplicated here. Here: the rule + a pointer (`see docs/...`). There: the steps. Avoid drift.
3. **Not everything splits.** Atomic rules with no real procedure stay whole here — don't manufacture a doc for them.
4. **Point only to a doc that is correct.** Before linking, verify the target doc exists and is up to date; if it's a stub, fill it first. A rule that points at a stale/empty doc is worse than no rule.
5. **Mirror to `AGENTS.md`.** Per the Sync rule, every edit here is applied byte-for-byte there.

The same discipline governs auto-memory: `MEMORY.md` holds one-line hooks (what + where); each individual memory file holds the detail (how).

## Mandatory first step

Before analyzing or modifying any part of the project, read:

1. this root agent guide (`AGENTS.md` ≡ `CLAUDE.md` — identical mirrors);
2. the relevant per-area section below;
3. the live docs under `docs/` for the area you are touching (keep `docs/` as the single home for product vision, architecture, local-development setup, the roadmap, the API collection under `docs/api/`, and design specs/plans).

If workspace instructions and submodule/sub-area instructions conflict, prefer the stricter instruction.

## Spec & plan authoring workflow (Codex review-gated, mandatory)

After a brainstorming flow, when you finish writing a spec — and again when you finish writing the phase plans — **do not ask the user to review it.** Gate it through Codex via the `/using-codex-workflow` skill (which owns the Codex CLI mechanics):

1. **Iterative Codex review until clean.** Have Codex review the spec and loop its suggestions — keep the *same* Codex session (`resume`) across iterations for context efficiency — until Codex has **no more observations**.
2. **Codex is advisory only.** It only suggests; it never edits and never blocks. **You have the final word** and stay objective: if Codex wants something resolved now but you judge it belongs in the implementation phase, you defer it.
3. **Spec first, then plans.** Once *you* approve the spec, **commit it**; then write the implementation plans with `/writing-plans` — **one plan per phase** — and run the **same** iterative Codex review on the plans.
4. **Hand back to the user only at the end.** When everything is finalized, tell the user it is ready to implement and give them a **`/compact` compaction prompt** capturing the most relevant context for the implementation ahead.

This overrides any default brainstorming/spec step that would ask the user to review the spec: the review gate is Codex, not the user.

## Implementing plans (autonomous, Codex-gated — only on explicit request)

**Trigger:** only when the user explicitly asks you to implement plans. Then run the whole thing **start to finish without stopping** — the user is unavailable to tell you to continue, so never pause for a "shall I go on?". When a doubt arises, **decide it yourself** from the resources at hand and **document the decision and its rationale**. This autonomy covers implementing, the Codex review, leaving the project locally runnable, and any E2E tests on feature branches; it does **NOT** authorize `merge` to `main`, `push`, or deploy — those still need explicit user approval.

Implement the specified plans **sequentially** — finish one, then the next:

1. **Implementation phase** — directed by whichever skill the user invoked (`/subagent-driven-development` or `/executing-plans`); **default to `/subagent-driven-development` if none was invoked.** Work on feature branches per the Multi-repo feature workflow (branch + implement + verify; stop before the merge/push/pointer-bump steps).
2. **Final Code Review phase** — once implementation is done, this phase is **driven by Codex** via the `/using-codex-workflow` skill: let Codex find bugs and gaps and **fix them iteratively until Codex gives its green light.** You keep final technical judgment on genuine disagreements (decide + document).
3. **Leave it runnable (local only, never any remote):** apply any pending migrations/seeders the change introduces, update the local env vars it needs (`.env`), and do whatever else is required so the user can start everything with the project's start command (`./run.sh`) right away.
4. **E2E/QA phase (when applicable)** — with the stack runnable, write **and run to green** deterministic tests for every new feature testable on our own surface (frontend/API), then run the full suite to catch regressions. Diagnose every red as a real product bug or a brittle test; never mask it (decide + document).

**At the end, deliver a summary to the user:** what was done, what they should expect, step-by-step instructions to start testing, and every decision you made with its justification.

## Multi-repo feature workflow (MANDATORY)

Required for every feature touching one or more repos. Skipping steps causes broken submodule pointers, stale tarballs, or diverged branches.

1. **Sync first:** `./scripts/pull-all.sh` (workspace + all submodules to latest `main`).
2. **Branch** in each affected repo: `git -C repos/<repo> checkout -b feature/<name>`. Only the repos the feature modifies; the workspace root only needs a branch if docs/scripts change.
3. **Implement in dependency order:** the shared contract `my-plants-species-schema` first, then its consumers (`my-plants-knowledge-engine`, `my-plants-api`), then `my-plants-web`. Skip steps that don't apply.
4. **After any `my-plants-species-schema` change, pack + install it into its consumers and commit `package.json`/`package-lock.json` in each:** `./scripts/pack-species-schema-and-install.sh`. The schema is the shared package — consumers must depend on the freshly packed version before they use a new contract.
5. **Verify:** `./scripts/test-all.sh` (or per-repo).
6. **Merge & push each submodule:** `git checkout main && git merge --ff-only feature/<name> && git branch -d feature/<name> && git push origin main`.
7. **Bump workspace pointers (required):** from the workspace root, `git add repos/<repos pushed> && git commit -m "chore: update submodule pointers after <name>" && git push origin main`. The workspace must always point to the correct commit of each submodule — **never skip this**: a checkout/deploy that runs `git submodule update` checks out the workspace-pinned commit, so an un-bumped pointer silently reverts your work to the old commit.

Full submodule mechanics: `docs/multirepo-submodules.md`.

## Dead code & fork prevention (mandatory)

**Deletion rule:** a file may be deleted as dead ONLY when ALL three hold: (1) a static reachability walk from the repo's entrypoints marks it unreachable, (2) a `grep` for its basename across src+tests finds no reference outside itself (this is what catches dynamic/string dispatch — request-time controller resolution by name, readdir aggregators, computed imports), and (3) the full suite is green after the deletion.

**No new forks:** never copy a file between repos (or within one) to share logic. When two surfaces must share behavior, extract ONE implementation with the per-context differences injected, so drift becomes structurally impossible. The species-record shape is the canonical example: it lives once in `my-plants-species-schema` and is imported, never copied. Parallel per-context copies of one surface (adapters, pollers, handlers) are a high-yield bug class: any contract/behavior change in one MUST be propagated to every sibling in the same change.

## Testing

- **`my-plants-species-schema` / `my-plants-knowledge-engine` / `my-plants-api`:** `npm test`.
- **`my-plants-web`:** `npm run build` (build + typecheck).
- **Whole workspace:** `./scripts/test-all.sh`.
- **Tests must be env-hermetic:** a test that asserts an env-default code path MUST delete/restore the ambient var around the assertion, or it passes locally and breaks elsewhere.
- **MariaDB date/time rule (critical for the date-heavy scheduling engine):** never compare date/time columns against `toISOString()`/ISO strings — MariaDB may parse them in the session timezone and shift due-date thresholds by the UTC offset. Bind native datetime objects (let the ORM stringify them in the connection timezone) or use the DB's own `NOW()`. Fix the connection timezone explicitly.

## E2E / Live QA — acting as a real user (mandatory delegation)

When the goal is to verify that something *actually works* by acting as a real user (a page rendering, a frontend action driving the API, an endpoint behaving), **never do it yourself — delegate to the `qa-engineer` subagent.** Every invocation MUST brief it with: (1) what to test, (2) how to test it (behavior, syntax, accepted variations), and (3) the expected result; it judges semantically, so an incomplete brief yields a useless verdict. **LOCAL ONLY.** The subagent only finds and reports what's broken — diagnosing and fixing it is a separate pass.

## Deploy

**v1 is local-only; no production deploy flow is defined yet (intentionally).** There is no `docs/deploy.md`, and you must NOT improvise one. If the user asks to ship/deploy/go to production, **stop and remind them to define the deploy flow first** (commands, gating, what touches the DB/migrations, which services restart, target environment) in `docs/deploy.md`, then point this section to it. Deploying to production is always **gated and explicit** — it requires the user's approval in the same message (see the Shared-environment / production golden rule below), and the implement-plans autonomy never covers it.

## Shared-environment / production golden rule

MyPlants runs only on localhost today. If/when a remote or shared environment exists: **any connection you initiate on your own is READ-ONLY DIAGNOSIS.** Forbidden without an explicit instruction in that same message: editing files, deploying, restarting services, running migrations/seeders, DB writes, config edits — anything that changes shared state. Ask once **per batch** of work (not per command), stating *why* you connect, *what* you will do, and whether the batch is read-only or mutating; a read-only approval never authorizes a mutation.

## No workarounds for blockers — pull the blocker into scope and fix it

When something blocks your testing/verification flow, do NOT write a hack, shortcut, or workaround to skip past it (no hand-forcing DB state, stubbing the real code path, disabling the failing step, faking inputs, or rerunning until green). Instead: stop, diagnose the root cause, pull it INTO scope, fix it at the root (decide + document), and re-run the original test through the real, unmodified flow. A workaround proves nothing about real behavior — if the blocker would also happen in production, the "passing" test is a false green. The only acceptable reasons to defer are: the blocker is purely a local/test-harness artifact that genuinely cannot occur in production, or the user explicitly says to defer.

## Commit conventions

Conventional Commits with imperative subjects (`feat: …`, `fix: …`, `chore: …`, `docs: …`). PRs include: behavioral change description, migration/env impact, and the verification commands run. Repo docs, code, identifiers, and commits are in English.

## Documentation (`docs/`) — index & workflow

All documentation lives in `docs/`. When a rule above says "see `docs/…`", the procedure lives there. Index:

| Topic | Doc |
|---|---|
| Product vision | `docs/product-vision.md` |
| Architecture (components/stack/DB/workspace, repo-topology decision) | `docs/architecture.md` |
| Care engine (place association, scheduling, viability, feedback/adaptation) | `docs/care-engine.md` |
| Local development (install, env, DB, run, tests) | `docs/local-development.md` |
| Roadmap | `docs/mvp-roadmap.md` |
| Multi-repo / submodule mechanics | `docs/multirepo-submodules.md` |
| Deploy | *(not defined yet — local-only v1)* |
| API collection | `docs/api/` *(pending — create once the API exists)* |
| Design specs & plans | `docs/superpowers/specs/`, `docs/superpowers/plans/` |

**After every completed feature, update docs:** the API collection and `docs/architecture.md` when the API surface/contracts change; the roadmap when scope advances; `docs/local-development.md` when setup/run/test steps change.

## Security

Never commit `.env` or real secrets/credentials. Only `.env.example` is tracked. The database connection is assembled from **separate** env vars (`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`) — never a hand-authored connection string. Do not log secrets or expose them in errors. Never hardcode credentials.

## Agent behavior

- Prefer small, targeted changes. Do not perform unrelated refactors.
- Preserve each area's existing module system and language conventions; don't introduce a new one without a documented decision.
- Always update docs when behavior, API routes, env contracts, or cross-repo workflows change.
- Respect the project's separation of concerns: keep domain/processing logic where the architecture places it, and let each surface do only its job.
- Communicate with the user in Spanish; keep everything else (subagents, repo docs, code, commits) in English.
