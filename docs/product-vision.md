# Product Vision — MyPlants

## The problem

Keeping houseplants healthy means knowing **what to do and when** — and that is not a fixed
schedule. "Water every 7 days" is wrong because watering depends on the species, the pot,
the soil, the light, the temperature, the humidity, and the season. Generic plant apps feel
dumb precisely because they ignore this.

## What MyPlants does

MyPlants **advises**; it does not care for the plants itself. For each of the owner's plants
it says what action to take and when — watering, fertilizing, repotting, and general
maintenance — and it adapts that advice to:

- the **species** (its real needs and tolerances),
- the **spot** the plant physically lives in (a user-built environment profile), and
- the **local climate** (real weather for outdoor spots; a stabilized model for indoor).

Care is modeled as **parameters and formulas that recompute**, never as a hardcoded calendar.

## How it stays accurate and personal

- **Curated species knowledge.** A Claude-driven research workflow turns a scientific name
  into a validated, structured species record plus an informative Markdown brief. The
  knowledge is curated once and reused cheaply forever after.
- **A control loop with the owner.** The owner logs actions, postpones tasks, and reports
  symptoms; the system adapts each plant's plan from that feedback (a postpone repeated often
  means the interval was wrong).
- **An informative viability semaphore.** It compares a plant's spot + city climate against
  the species' tolerances and warns about poor fits — but it never blocks. Moves and gifts
  are real; the app accompanies, it doesn't scold.
- **A moving module.** Simulate a move to another city ("what would change?") or schedule it
  so the whole garden's care recomputes on the move date.

## Scope (v1) and deferred ideas

- **v1:** single user, 100% deterministic care app, local-only.
- **Deferred:** AI photo diagnosis inside the feedback loop, multi-user accounts, and the
  production deploy flow.

Full design rationale: `docs/superpowers/specs/2026-06-18-myplants-design.md`.
