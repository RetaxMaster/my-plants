# MyPlants — Design Spec

**Date:** 2026-06-18
**Status:** Approved design (pre-implementation)

## Problem

I want a system that helps me keep my plants healthy by telling me **what to do and
when** — when to water, fertilize, repot, and do general maintenance. The system does
not care for the plants itself; it advises me. Care must be *accurate per species* and
must *adapt to the real environment* (temperature, the specific spot a plant lives in,
season, climate).

The core insight that drives the whole design: **plant care is not a fixed schedule, it
is a model.** "Water every 7 days" is wrong because watering depends on species, pot,
soil, light, temperature, humidity, and season. So care is expressed as parameters and
formulas that recompute, never as hardcoded calendars.

## System shape: a workspace with two subsystems

MyPlants is **two systems of different nature** that meet only through a data contract
(the curated species schema). This mirrors the existing `retaxmaster-workspace` pattern.

1. **Knowledge engine** — its product is *data*: the curated truth about each species.
2. **Care app** — its product is *a daily experience*: what to do and when.
3. **Shared contract** — the **curated species database**, whose schema we own (we do
   not adapt to third-party conventions).

This will likely become a git workspace with subrepos (one per subsystem) sharing the
curated data. **Each subsystem gets its own spec → plan → implementation cycle.** Build
order: the knowledge engine first (it produces the data the app depends on), then the
care app.

---

## Subsystem 1 — Knowledge engine

A `resume-optimizer`-style workspace: a `CLAUDE.md` runbook teaches *any* fresh Claude
the **species-onboarding workflow**, separating deterministic from non-deterministic
tools.

- **Non-deterministic tools (Claude):** a research subagent that gathers from
  trusted APIs we configure + public websites via Claude's web-reading tools,
  **critically evaluates source veracity** (cross-checks sources, flags uncertainty),
  and synthesizes.
- **Deterministic tools (scripts):** fetch/scrape trusted sources, **validate against
  the schema**, and write the record into the curated database.

**Reproducible flow:** give a scientific name → trigger "research this species" → the
workflow produces **two artifacts**:

1. A **structured species record** — the curated DB row the app consumes.
2. A **Markdown brief** — an informative blogpost (origins, curiosities, care narrative),
   purely for the human's curiosity.

A **schema-validation gate** runs before saving so every species comes out consistent.
The onboarding prompt must be carefully structured so the workflow is reproducible across
every onboarding.

### Curated species schema (we design it)

**Care parameters** (consumed by the app):

- **Watering:** base interval + how it responds to temperature/light/season + soil-dryness
  preference + drought tolerance.
- **Light:** minimum / ideal / maximum (direct, bright indirect, medium, low).
- **Temperature:** survival minimum / ideal range / maximum.
- **Humidity:** minimum / ideal.
- **Fertilizing:** active season(s), in-season frequency, dormancy period.
- **Repotting:** typical interval + signs that trigger it.
- **Maintenance:** pruning (seasonal guidance), `rotationDays` and `leafCleaningDays`
  (numeric, schedulable cadences), common pests.
- **Native climate / hardiness:** feeds the viability semaphore.

**Metadata:** scientific name, common names, confidence level + cited sources, reference
to the Markdown brief.

---

## Subsystem 2 — Care app

### Scope decisions (v1)

- **Single user now, modular for multi-user later.** v1 serves only the owner, but the
  design keeps a clean "owner" boundary from day one so multi-user can be added without a
  rewrite.
- **100% deterministic in v1.** All AI lives in the knowledge engine. The app does only
  cheap, predictable computation — no API keys or AI costs in production. **Future
  version:** AI photo diagnosis inside the state-feedback loop (deferred, see Roadmap).

### Domain concepts

- **Place** — a profile of environmental traits *the user builds* (nothing predefined):
  indoor/outdoor, light type, climate-controlled yes/no, humidity character, and an
  optional typical temperature range. Outdoor traits auto-fill from weather; indoor is
  hybrid (see below).
- **City** — anchors the weather source and feeds outdoor places.
- **Plant (instance)** — a specific plant = species (from the curated DB) + place + pot +
  acquisition date + care history.
- **Care plan** — per plant and per task (watering / fertilizing / repotting /
  maintenance), a **dynamically computed** schedule: *base (from species) × modulators
  (temperature, season, light)*. Never a stored fixed interval.

### Why "places" are user-built, not predefined

There is **no reliable formula** to compute the temperature or light inside a home from a
city's weather. Indoor microclimate depends on heating/AC, insulation, floor, window
orientation, obstructions, and artificial light — none of which any weather API knows. So
each environmental variable is sourced from **whoever knows it best**:

- **Indoor/outdoor:** declared by the user (the switch that decides whether street weather
  applies).
- **Light** (direct / bright indirect / medium / low; natural or artificial): declared by
  the user.
- **Temperature & humidity of an OUTDOOR place:** auto-filled from the weather API, changes
  with the seasons on its own.
- **Temperature & humidity of an INDOOR place (hybrid):** the user characterizes the place
  (climate-controlled? naturally humid like a bathroom?) and optionally gives a typical
  *range*. If not provided, the app models indoor as a *stabilized/damped* version of the
  city's weather.

### Engines

- **Scheduling engine:** computes next-due dates from species parameters + place/weather,
  and **recomputes automatically** as season or weather change.
- **Viability semaphore:** compares place + city climate against the species' tolerances →
  an **informative** compatibility level. It **never blocks** adding or moving a plant
  (moves, gifts, and exceptions are real; the app advises, it does not scold).
- **Feedback loop** (closes the control loop):
  - *Action feedback:* logging "watered today" teaches the app the real cadence; consistent
    early/late watering nudges the plant's per-plant interval adjustment (never the species
    baseline).
  - *Postponement:* any task can be postponed. A one-off postpone just shifts the date;
    **repeated postpones** signal a mis-calibrated interval and adapt the plan.
  - *State feedback:* a periodic check-in ("how does it look?") with symptom options
    (yellow leaves, drooping, dry soil, leggy growth…); each maps to an adjustment
    (yellow + wet soil = overwatering → lengthen interval).
- **Moving module:** reuses the viability engine + climate model in two modes:
  - *"What-if" simulator:* pick a target city → recompute each plant's compatibility and
    care deltas, committing nothing. Useful to decide before moving.
  - *Scheduled move:* set a date → on that day the app switches city and all climate
    variables and recomputes the whole garden's care at once.

### Deferred to the care-app spec

- **How reminders reach the user:** v1 is **in-app** (per the architecture spec); email and
  push channels are deferred behind a notification-channel interface.

---

## Roadmap (explicitly deferred)

- **AI photo diagnosis** in the app's state-feedback loop (upload a photo → model
  diagnoses). v1 stays deterministic.
- **Multi-user.** v1 is single-user but structured so this is an additive change.

## Non-goals (v1)

- The app does not physically care for plants; it only advises.
- No automated actuator/sensor/control integrations — the app never reads a moisture
  probe or triggers a pump; it advises a human.
- No runtime AI in the care app.
- No multi-user accounts in v1.
- The technology stack is defined in the companion architecture spec
  (`2026-06-18-myplants-architecture.md`); this design spec stays stack-agnostic on purpose.

## Notes on the feedback loop and the brief (clarifications)

- **Feedback adapts per-plant state, never species truth.** The curated species record is
  immutable read-only data. Adaptation from logged actions, postponements, and symptoms
  produces a *per-plant* adjustment (kept with an audit trail), layered on top of the
  species baseline — it never edits the species record.
- **The Markdown brief is not served by the app in v1.** It is stored alongside the curated
  record for human reading; surfacing it in the UI is a later, optional addition.
