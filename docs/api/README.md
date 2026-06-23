# MyPlants API Collection

The HTTP surface of `repos/my-plants-api` (NestJS). This is the living, human-readable API
collection; the quick map of the same surface lives in `docs/architecture.md` ("HTTP API surface").

## Conventions

- **Base:** local only — `http://localhost:8000`. The web app never calls this directly; the Nuxt
  BFF proxy (`/api/*`) forwards browser requests and attaches the bearer from the sealed session.
- **Auth column:**
  - `public` — no token required.
  - `bearer` — requires `Authorization: Bearer <token>` (JWT from `POST /auth/login`).
  - `bearer (admin)` — bearer required **and** the real token role must be `ADMIN` (else `403`).
- **Owner scope:** owner-scoped endpoints operate on the **effective owner**
  (`actingAsOwnerId ?? ownerId`). By default that is your own owner — admins included. An admin can
  reach another owner only via the role-gated impersonation header below.
- **Dates** are `YYYY-MM-DD` strings; the per-plant "today" boundary is computed from that plant's
  place-city timezone.

## Impersonation header — `X-Act-As-Owner`

A request header that sets the effective owner for that single request.

- **`X-Act-As-Owner: <ownerId>`** — honored **only** when the verified token's role is `ADMIN`
  (a USER's header is ignored — no privilege escalation, even hitting `:8000` directly).
- If the named owner does not exist → **`403 Forbidden`** (validated in the guard, before any write,
  so a bogus target never surfaces as a later FK/`500`).
- It is normally **set by the BFF** from the admin's sealed session (after `POST /api/acting-as`),
  not by clients directly. The BFF only ever stores owner ids drawn from `GET /owners`.

---

## Auth

### `POST /auth/login`
- **Auth:** public
- **Request:** `{ "username": string, "password": string }`
- **Response:** `{ "token": string, "user": { "username": string, "role": "USER" | "ADMIN" } }`

### `POST /auth/logout`
- **Auth:** bearer
- **Request:** _(empty)_
- **Response:** `204` / `{ "ok": true }`. Revokes the caller's current token (its `jti` is added to the blocklist).

### `GET /auth/me`
- **Auth:** bearer
- **Request:** _(none)_
- **Response:** `{ "username": string, "role": "USER" | "ADMIN", "actingAs": { "ownerId": string } | null }`
- **Notes:** `actingAs` is the **authoritative** impersonation state the API resolved from the
  `X-Act-As-Owner` header (`null` when not impersonating). The web banner is rendered from the BFF
  `me` (which also carries the human-readable label); the two are consistent by construction.

---

## Owners (admin)

### `GET /owners`
- **Auth:** bearer (admin) — a USER receives **`403 Forbidden`**.
- **Request:** _(none)_
- **Response:** `[{ "ownerId": string, "username": string | null, "role": "USER" | "ADMIN" | null }]`
- **Notes:** This is the "Acting As" picker source. `username`/`role` come from the linked `User`
  (1:1 with `Owner`); for an owner with **no** linked user, `role` is `null` and the label falls
  back to the owner's name. Intentionally **not** owner-scoped (it *is* the picker) — its safety is
  the role gate. Selects only safe user fields (never `passwordHash`).

---

## Species

### `GET /species`
- **Auth:** public
- **Response:** `{ "slug": string, "scientificName": string, "commonName": string }[]` — lightweight catalog.

### `GET /species/:slug/brief`
- **Auth:** public
- **Response:** `{ "slug", "scientificName", "commonNames": string[], "briefEs": string, "briefEn": string }`. `404` on unknown slug.

### `GET /species/:slug`
- **Auth:** bearer
- **Response:** the full curated species record (care data). Protected to minimize the public surface.

---

## Plants

### `GET /plants/:id/care`
- **Auth:** bearer · owner-scoped
- **Response:** `{ "plantId", "tasks": [{ "task", "nextDueOn", "daysUntilDue", "status": "overdue" | "today" | "upcoming" }], "viability": { "level": "good" | "caution" | "poor", "reasons": string[] } }`. Lazily recomputes the due cache if empty.

### `PATCH /plants/:id`
- **Auth:** bearer · owner-scoped
- **Request:** `{ "nickname"?: string, "placeId"?: string }` — empty nickname clears it; the target place must belong to the effective owner. A place change recomputes the plant.

### `GET /plants/:id/viability-preview?placeId=`
- **Auth:** bearer · owner-scoped
- **Response:** the projected viability of the plant as if it lived in the given place. Writes nothing.

---

## Places

### `PATCH /places/:id`
- **Auth:** bearer · owner-scoped
- **Request:** `{ "name"?: string, "climateControlled"?: boolean }` — a `climateControlled` change recomputes every plant in the place; a name-only change does not.

---

## Cities

### `GET /cities/search?q=`
- **Auth:** bearer (not owner-scoped — public geocoding reference data, but still login-gated)
- **Response:** `CitySearchResult[]` (Open-Meteo geocoding proxy). Degrades to `[]` on error.

---

## Moving

### `POST /moving/simulate`
- **Auth:** bearer · owner-scoped
- **Request:** `{ "latitude": number, "longitude": number }`
- **Response:** `PlantViability[]`, each result including:
  - `placeCityName: string` — the plant's current city name.
  - `inPrimaryCity: boolean` — whether the plant is in the current primary city.
- **Behavior — empty-primary fallback:** normally only the plants whose place is in the current
  primary city are returned (all `inPrimaryCity: true`). **If the primary city holds none of the
  owner's plants, `simulate` falls back to ALL of the owner's plants**, flagging the off-primary
  ones `inPrimaryCity: false` so the UI can warn per plant
  (*"This plant is not in your current city — it is in &lt;city&gt;."*). Writes nothing.

### `POST /moving/schedule`
- **Auth:** bearer · owner-scoped
- **Request:** `{ "name": string, "latitude": number, "longitude": number, "timezone": string, "moveOn": "YYYY-MM-DD" }`. Find-or-creates the destination City, then schedules the move.

---

## Care plan

### `POST /care-plan/recompute`
- **Auth:** bearer · owner-scoped
- **Request:** _(none)_
- **Response:** recompute summary.
- **Notes:** Scopes to the **effective owner** — your own garden by default, the target's while
  acting-as. The all-owners recompute is **not** reachable over HTTP; it runs only in the
  startup/cron path (`applyAllDueMoves → recomputeAll`).
