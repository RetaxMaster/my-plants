# Edit Modules + Per-Plant Day Cutoff + Honest Moving — Design Spec

**Date:** 2026-06-21
**Status:** Draft (pending Codex review gate)
**Repos touched:** `my-plants-api`, `my-plants-web`. **No** `my-plants-species-schema` change. **No DB migration** (every field already exists).

## 1. Overview & goals

Add the missing editing surfaces and make location semantics honest per place:

1. **Edit a plant** — change its `nickname` and/or its `place` (move it to another space). Moving a plant to a place in a different city implicitly relocates its climate, so a **viability preview** is shown before confirming.
2. **Edit a place** — change its `name` and/or its `climateControlled` flag.
3. **Per-plant day cutoff** — the "what counts as today" boundary stops using the owner's primary city and instead derives from **each plant's place-city timezone**.
4. **Honest Moving** — the Moving module stops assuming every plant is with you. It scopes simulate/apply to the plants whose place is in your **current (primary) city**.

### Non-goals (YAGNI)

- No removal of the `isPrimary` concept (Moving still relies on it; see §5). Only the day-cutoff stops using it.
- No editing of other plant fields (species, `acquiredOn`) or other place fields (city, `indoor`, `lightType`, humidity/temp). Those rarely change; out of scope.
- No redesign of Moving's UX (no "pick which plants move" UI). That is a future, separate design.
- No new "move plant to a brand-new city" flow — a plant moves only to one of the owner's existing places.

## 2. Data model

No schema change and no migration. All fields already exist:

- `Plant.nickname` (`String?`), `Plant.placeId` (`String`, FK → `Place`).
- `Place.name` (`String`), `Place.climateControlled` (`Boolean @default(false)`).
- `City.timezone` (`String`), `City.isPrimary` (`Boolean`).

The location chain is unchanged: `Plant → Place → City`. A plant has no city of its own; its city is its place's city.

## 3. API — Plant editing

### 3.1 `PATCH /plants/:id`

Body (`UpdatePlantDto`, both optional; an **empty body is a no-op** that returns the resource unchanged — no custom "at least one" validator):

```ts
class UpdatePlantDto {
  @IsOptional() @IsString() nickname?: string;     // "" or whitespace → stored as null (cleared)
  @IsOptional() @IsString() @MinLength(1) placeId?: string;
}
```

Behavior:

- **Resolve & ownership:** load the plant by `{ id, ...owner.ownerFilter() }` (USER → own only; ADMIN → any). `NotFoundException` if it does not resolve.
- **`placeId` change:** validate the target place belongs to the **plant's owner** (`{ id: placeId, ownerId: plant.ownerId }`) — not the actor's owner, so an ADMIN editing another owner's plant moves it within that owner's spaces. `BadRequestException` on mismatch/unknown.
- **`nickname`:** trim; empty/whitespace → `null`. Cosmetic.
- **Persist** the provided fields. Return the same shape as `GET /plants/:id` (species names flattened via `withNames`).
- **Recompute trigger:** if `placeId` actually changed → `carePlan.recomputePlant(id)` (place change alters light/indoor/climate-controlled and possibly the city's weather). A `nickname`-only change does **not** recompute.
- If neither field is provided, return the plant unchanged (no-op, no recompute).

### 3.2 `GET /plants/:id/viability-preview?placeId=<id>` (read-only)

Returns the plant's projected **viability** as if it lived in the given place, without writing anything. Powers the pre-confirm preview in the web modal.

- **Resolve & ownership:** plant by `{ id, ...owner.ownerFilter() }`; target place by `{ id: placeId, ownerId: plant.ownerId }`. `placeId` is required (`400` if missing); `BadRequestException` if the place is unknown / not the plant's owner's.
- **Compute:** `buildViability(speciesRecord, { indoor, climateControlled, humidityCharacter, indoorTempMinC, indoorTempMaxC, lightType } from target place, weather)` where `weather = weather.forCity(targetPlace.city.id, lat, lng)`. Returns the same `ViabilityResult` shape that `GET /plants/:id/care` already exposes under `viability`, so the front reuses its semaphore renderer.
- Side-effect free (no DueCache writes, no recompute).

## 4. API — Place editing

### 4.1 `PATCH /places/:id`

Body (`UpdatePlaceDto`, both optional; an **empty body is a no-op** returning the place unchanged):

```ts
class UpdatePlaceDto {
  @IsOptional() @IsString() @MinLength(1) name?: string;
  @IsOptional() @IsBoolean() climateControlled?: boolean;
}
```

Behavior:

- **Resolve & ownership:** load by `{ id, ...owner.ownerFilter() }` (USER own / ADMIN any). `NotFoundException` otherwise.
- **Persist** provided fields. Return the updated place row.
- **Recompute trigger:** if the effective `climateControlled` value **changes** (provided AND different from the stored value) → recompute **every plant in this place** via a new `carePlan.recomputePlace(placeId)` (loops `plant.findMany({ where: { placeId } })` → `recomputePlant`). A `name`-only change does **not** recompute.
- **Module wiring:** `PlacesService` gains a `CarePlanService` dependency; `PlacesModule` imports whatever module provides it (the same one `PlantsModule` uses).

## 5. API — Per-plant day cutoff (drop primary from the boundary)

The timezone is used only to compute the local calendar day for due-date comparisons (dates are DATE granularity). Two call sites switch from the owner's primary city to each plant's place-city:

- **`PlantsService.getCare(id)`** — fetch the plant with `place: { include: { city: true } }` and use `plant.place.city.timezone` for `startOfTodayUtc(...)` instead of the owner's primary city. (Climate/season already derive from the place's city; only the boundary lagged.)
- **`CarePlanService.todaysTasks(ownerId)`** — fetch the owner's DueCache rows joined to `plant → place → city` (timezone), then filter **per row**: keep a row when `nextDueOn < startOfTomorrowUtc(row.plant.place.city.timezone, now)`. Replaces the single-cutoff SQL `lt: end`. Per-row filtering in JS is fine at this scale (one owner, a handful of plants).
- **Comment fix:** `src/common/time/local-date.ts` header comment ("All day boundaries use the owner's primary-city timezone") updated to reflect per-plant place-city timezones.
- `isPrimary` stays in the schema and is still used by Moving (§5 above is unaffected by §6 below). No migration.

## 6. API — Honest Moving (scope to current-city plants)

Today `MovingService.simulate` and `applyDueMovesForOwner` treat **all** of an owner's plants as if they were at the primary city. They are scoped to the plants actually at the current (primary) city:

- **`simulate(lat, lng)`** — resolve the owner's primary city; restrict the plant set to `where: { ownerId, place: { cityId: primary.id } }`. Plants in other cities are not "with you," so they are excluded. Both indoor and outdoor plants in the current city are included (you want to assess your whole relocation). **No-primary fallback:** if the owner has no primary city, behave as today (all owner plants) — documented, backward-compatible.
- **`applyDueMovesForOwner(ownerId, now)`** — for **each** due move, resolve the **current** primary city id **inside that move's transaction** (immediately before flipping), and repoint to the target only the outdoor places that were in **that** old-primary city (`updateMany({ where: { ownerId, indoor: false, cityId: oldPrimaryId } })`). Resolving per-move (not once before the loop) keeps a chain of multiple due moves correct: each move moves the places that were at the primary as of that move. The primary-flag flip and idempotency are unchanged. **No-primary fallback:** if there is no current primary at that point, behave as today (repoint all outdoor places).
- **Indoor/outdoor asymmetry (conscious, pre-existing):** `simulate` shows ALL current-city plants (indoor + outdoor), but `apply` repoints only **outdoor** places' `cityId` — exactly as today. Changing how indoor places relocate is a separate Moving concern and is intentionally **out of scope** here; this wave only closes the cross-city gap. The asymmetry (simulate broader than apply) is therefore deliberate and documented, not a bug to fix now.
- For a single-city garden (the real-world common case) the behavior is identical to today.

## 7. Web — editing UI (modal/drawer, Nuxt UI `UModal`)

- **Plant edit (`/plants/[id]`):** an "Edit" button opens a modal with a nickname input and a place selector. The selector shows only the **plant's owner's** places — filter `listPlaces()` to `place.ownerId === plant.ownerId` (both `ownerId` fields are already present in the API responses; expose them on the web `Plant`/`Place` types). This keeps an ADMIN from picking another owner's place (which the API would reject). When the selected place differs from the current one, call the viability preview and render the projected semaphore (reuse the existing viability display). "Save" → `PATCH /plants/:id` → on success **refresh both page datasets** (`plant` and `care` — the page has two `useAsyncData`) so title/place AND care reflect the edit; "Cancel" closes without changes.
- **Place edit (`/places`):** each place row gets an "Edit" affordance opening a modal with a name input and a climate-controlled toggle. "Save" → `PATCH /places/:id` → refresh the list.
- **`composables/useApi.ts` additions** (all through the `/api` BFF proxy):
  - `updatePlant(id, body: { nickname?: string; placeId?: string })`
  - `previewPlantViability(id, placeId)` → `PlantViability`/`ViabilityResult`
  - `updatePlace(id, body: { name?: string; climateControlled?: boolean })`
- Types added to `types/api.ts` as needed (request bodies). Responses reuse existing `Plant` / `Place` / viability types, with `ownerId: string` added to `Plant` and `Place` (already returned by the API) so the front can filter the place selector to the plant's owner.

## 8. Testing

- **API (Vitest):**
  - Plant `PATCH`: nickname-only → no recompute; place change → recompute called + new placeId persisted; ownership (USER cannot patch another owner's plant; ADMIN can; target place must belong to the plant's owner); empty nickname clears to null.
  - Viability preview: returns a `ViabilityResult` for the target place; rejects a place from another owner; no DueCache writes.
  - Place `PATCH`: climateControlled change → recomputes all plants in the place; name-only → no recompute; ownership.
  - Per-plant cutoff: `todaysTasks` with two plants in cities of different UTC offsets returns the correct per-plant "due today" set (a plant due "tomorrow" in its own tz is excluded even if another plant's tz would include it).
  - Moving filter: `simulate` excludes plants whose place is in a non-primary city; no-primary fallback returns all; `applyDueMovesForOwner` repoints only old-primary outdoor places.
- **Web:** `npm run typecheck` + `npm run build` (the web gate).
- **E2E:** delegated to the `qa-engineer` (local only) — edit a plant's nickname + place (with preview), edit a place's name + climate-controlled, confirm care/today reflects changes.

## 9. Phasing (one implementation plan per phase)

1. **API — plant editing + viability preview** (`PATCH /plants/:id`, `GET /plants/:id/viability-preview`, `recomputePlant` on place change, tests).
2. **API — place editing** (`PATCH /places/:id`, `recomputePlace`, module wiring, tests).
3. **API — per-plant day cutoff** (`getCare` + `todaysTasks` + comment, tests).
4. **API — honest Moving** (scope `simulate` + `applyDueMovesForOwner` to current-city plants, tests).
5. **Web — editing UI** (plant + place modals, `useApi` additions, types; typecheck + build).
6. **Docs + runnable + E2E** (architecture/roadmap docs; apply nothing migration-wise; qa-engineer E2E + full regression).
