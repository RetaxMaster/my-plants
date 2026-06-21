# Care Engine — how the care plan is computed

This document explains how MyPlants decides **which place applies to a plant**, **what care
action to take and when**, and **how it adapts** to the owner's behaviour. The whole engine is
**100 % deterministic** — pure functions over stored data, no runtime AI. All AI lives in the
knowledge engine, never here.

There are two independent systems: the **scheduling calendar** (what to do and when) and the
**viability semaphore** (whether the place suits the species at all). Don't conflate them.

## 1. Domain hierarchy & place association

```
Owner  →  City  →  Place  →  Plant
```

- **City** — a point on the map: latitude, longitude, timezone, and an `isPrimary` flag. Its
  coordinates drive **real outdoor weather** (Open-Meteo) and its latitude drives the
  **hemisphere → season**. The primary city's timezone defines the owner's "today".
- **Place** — a *physical spot* inside a city, described by hand. Not a coordinate: a
  **microclimate**. Fields: `indoor` (bool), `lightType` (LOW | MEDIUM | BRIGHT_INDIRECT |
  DIRECT), `climateControlled` (bool), `humidityCharacter` (DRY | NORMAL | HUMID), and optional
  `indoorTempMinC` / `indoorTempMaxC`.
- **Plant** — assigned to **exactly one place at creation** (`placeId` is required). **That
  assignment IS how the engine knows which place applies.** There is no device geolocation and no
  auto-detection: the plant lives in the place you set until you move it.

### Effective microclimate (place → what the plant actually feels)

The place converts "the weather outside" into the conditions the plant experiences:

- **Outdoor place** → uses the city's **real weather** (temp + humidity). If weather is
  unavailable, neutral baselines are used and the temperature modulator is forced neutral.
- **Indoor place** → modelled climate. Temperature: the midpoint of `indoorTempMin/MaxC` if both
  are given; else a comfort baseline of **21 °C**; else (not climate-controlled, weather known) it
  **tracks outdoor swings, damped** — `21 + 0.4 · (outdoorTemp − 21)`. Humidity comes from the
  character label: HUMID = 65 %, NORMAL = 50 %, DRY = 35 %.

So the same species in two different places of the same city gets **different plans** — the place
is the differentiator. Weather is cached for 3 h; a fetch failure falls back to stale cache, then
to neutral (the scheduler never throws on weather).

## 2. Scheduling calendar — what to do and when

Five tasks: **WATER, FERTILIZE, REPOT, ROTATE, CLEAN_LEAVES**. For each, the engine computes a
single **next-due date**:

```
next due = anchor + interval
```

- **Anchor** — the date of the **last DONE event** for that (plant, task); if it has never been
  done, the plant's **acquired-on** date. Marking a task done re-anchors it (see §4).
- **Interval** — depends on the task:

**WATER** (the weather/place/season-aware one). Base interval from the species record, multiplied
by independent modulators, then clamped:

- learned per-plant **adjustment** multiplier (see §4),
- **temperature modulator** — *outdoor + real weather only*: hotter than the species' ideal max →
  drink sooner (`<1`), colder than ideal min → slower (`>1`); `clamp(1 + deviation · w · 0.1,
  0.5, 1.6)` where `w` = temperature sensitivity weight,
- **light modulator** — brighter place than ideal → sooner, dimmer → slower; `clamp(1 +
  (idealLightRank − placeLightRank) · w, 0.7, 1.4)`,
- **season modulator** — `1.5` when the species `reduceInDormancy` and the current season is the
  dormancy season (winter), else `1`.
- Sensitivity weights: low = 0.04, medium = 0.08, high = 0.14. Light ranks: low = 0, medium = 1,
  bright-indirect = 2, direct = 3.
- Final clamp to a band from **drought tolerance** (`span`: low = 0.5, medium = 1.0, high = 1.5):
  `min = base · (1 − span · 0.5)`, `max = base · (1 + span)`, never below 1 day. Result rounded to
  whole days. This keeps the interval from ever drifting to an absurd extreme.

**FERTILIZE** — in-season cadence; out of an active season it stretches: factor `1` in season,
`×4` in true dormancy (`reduceInDormancy`), `×2` otherwise.

**REPOT / ROTATE / CLEAN_LEAVES** — pure cadence (`cadenceDays · adjustment`, rounded), no weather
or season. REPOT cadence = `typicalIntervalMonths · 30`. ROTATE and CLEAN_LEAVES are optional: if
the species record has `null` for them, the task is skipped entirely.

### "Today" list & recompute triggers

The **due cache** stores **one** next-due per (plant, task) — a unique pair, so a plant never has
more than one pending watering. The **Today** query returns due-cache rows whose `nextDueOn` is
before the **start of tomorrow** in the owner's primary-city timezone — i.e. everything **due
today or overdue**, oldest first.

The plan is recomputed:
- **daily at 05:00** (cron, whole garden),
- **after every feedback event** (that plant), and
- **after a scheduled move is applied** (whole garden).

## 3. Viability semaphore — does the place suit the species?

Separate from scheduling. It compares the place's effective conditions against the species'
**survival** bounds and minimums and returns **good / caution / poor** with human reasons:

- seasonal low `<` survival min → **poor**; within 3 °C above it → **caution**,
- seasonal high `>` survival max → **poor**,
- place light rank below species minimum: gap ≥ 2 → **poor**, gap of 1 → **caution**,
- effective humidity below species minimum → **caution**.

Today this is surfaced in the **moving what-if simulation** (viability of every plant against a
target city's weather). It writes nothing.

## 4. Feedback loop — Done / Postpone / Symptom

Every owner action is stored as a **care event** and triggers a recompute of that plant. The
learning lives in two places: **re-anchoring** (immediate, one-shot) and the **learned
multiplier** (gradual, persistent).

- **DONE** — records the event with `occurredOn` (the date it was actually done; can be
  backdated). That date becomes the **new anchor**, so the next due is recomputed forward from
  reality. Also clears any manual override.
- **POSTPONED** — records the event, writes a **task override** pinning the exact next-due date
  you chose (a one-shot that beats the formula until the next DONE), **and** nudges the learned
  multiplier up: each postpone in the recent 60-day window adds `+0.05`. Repeated postpones teach
  the system "this plant needs this task less often than the book says."
- **SYMPTOM** — a v1 symptom→watering map nudges the WATER multiplier: `yellow-leaves-wet-soil`
  +0.15, `mushy-stem` +0.2 (over-watering → water less), `wilting-dry-soil` −0.15,
  `crispy-edges-dry-soil` −0.1 (under-watering → water more). Unknown symptoms are stored but
  change nothing.

The **learned multiplier** (`PlantTaskAdjustment`, one per plant+task) starts at `1.0`, is
bounded to **[0.5, 2.0]**, and is the personalization layer over the species defaults.

### Catch-up / overdue behaviour (no accumulation)

The engine is **state-based**, not an event stream that emits one task per missed day. Because the
due cache holds a single next-due per (plant, task), **forgetting the app for a week produces one
overdue watering, not seven**. The daily recompute keeps recomputing the *same* overdue date (the
anchor hasn't moved), so it stays a single item that simply shows as overdue in Today. You water
once, mark it DONE, and it re-anchors forward. Nothing piles up.

### Reporting "I watered it" & watering early/late

You tell the app via a **DONE feedback event** with `occurredOn` set to the date you actually did
it (today, or backdated to yesterday). Because that date becomes the anchor:

- **watered a day early** and marked done with that date → the next due shifts **earlier** by that
  amount; the plant's rhythm follows reality,
- **a day late** → the next due shifts **later**.

So the schedule always re-syncs from the **real action**, not from the planned date.

## 5. Known limitation — no punctuality learning yet

The adaptation function already accepts an `earlyLateRatio` input (observed interval ÷ scheduled
interval) whose intent is: if you *consistently* act earlier than scheduled, permanently **shorten**
the base interval; later → lengthen it (`cadenceNudge = (ratio − 1) · 0.3`). **Today this input is
hard-wired to `1`, so it contributes nothing.** The practical consequence: marking a watering early
or late **re-anchors** the next due (a one-time shift) but does **not** yet make the engine learn
"this owner always waters 2 days early" and bake that into the base rhythm. Active learning
currently comes only from **postpones** and **symptoms**. Feeding a real `earlyLateRatio` from the
DONE history is a natural future improvement.

## 6. Moving (brief)

Scheduling a move stores a `ScheduledMove`. When its date arrives, the target city becomes
primary, **outdoor places repoint** to it (indoor places don't — a room is still a room), and the
whole garden recomputes. The apply step is idempotent via an `applied` flag.
