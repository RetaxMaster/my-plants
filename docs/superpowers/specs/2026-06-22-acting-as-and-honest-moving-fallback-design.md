# Admin "Acting As" Impersonation + Honest-Moving Empty-Primary Fallback — Design Spec

> Wave that fixes two pre-existing backend defects surfaced during the 2026-06-22 frontend-redesign QA (B7, B8). The redesign was presentation-only; these live in `repos/my-plants-api` (with matching frontend work in `repos/my-plants-web`). No `my-plants-species-schema` contract change.

## 1. Problem & goal

Two defects, diagnosed against the live system (data layer + HTTP), root causes confirmed:

- **B7 — `GET /cities` shows more than one primary city.** Not a bug in `make-primary` (verified: it demotes the owner's other cities in one transaction, and each owner has exactly one primary in the DB). The real cause: the ownership rule "ADMIN sees everything" makes `OwnerService.ownerFilter()` return `{}` (no owner constraint) for an admin, so an admin's reads return **every owner's** rows. With multiple owners, each contributes its own primary, so the admin's personal list shows several "Primary" badges and the personal "primary city" becomes ambiguous. `MovingService.simulate` already sidesteps this by using `currentOwnerId()` (own-scoped) rather than `ownerFilter()`.
- **B8 — `POST /moving/simulate` returns `[]` despite plants existing.** The owner's primary city has zero plants (all plants live in places of a *non-primary* city). "Honest moving" deliberately scopes simulate to plants whose place is in the current primary city, so the scoped set is empty → `[]`. This is a reachable production state: `make-primary` (and `create` with `isPrimary: true`) flip the primary flag **without relocating places**, so a primary city can legitimately contain none of your plants. B8 is **independent of B7** (simulate is own-scoped already).

**Goals:**

1. Replace the blanket "ADMIN sees all" with an explicit, opt-in **Acting As** (impersonation) capability: an admin defaults to seeing only their own resources and can choose to act on behalf of another owner, then stop.
2. Make `simulate` useful when the primary city is empty: fall back to all of the owner's plants, and let the frontend warn, per plant, that it is not in the current city.

**Non-goals:** No change to `make-primary` semantics (it correctly does not relocate places). No impersonation audit log (single real user today — YAGNI; revisit if multi-user becomes real). No `my-plants-species-schema` change. No new database tables or migrations.

## 2. Core concept — the "effective owner"

Today owner scoping has two modes inside `OwnerService`: a USER is constrained to `{ ownerId }`; an ADMIN is unconstrained (`{}`). B7 is that `{}`.

This wave introduces **one** new concept: the **effective owner** — "whose data am I operating on right now":

```
effectiveOwnerId = actingAsOwnerId ?? ownerId
```

- Not impersonating → effective owner is your own → you see your own resources. **This now includes admins** (the default "admin sees all" is removed).
- Acting as X → effective owner is X → you read **and write** X's resources.
- **Your role never changes while impersonating.** You remain ADMIN, so you can stop or switch targets. `currentRole()` always reflects the real token role.

The change is centralized in `OwnerService`: `currentOwnerId()` and `ownerFilter()` return the **effective** owner, and `ownerFilter()` never again returns `{}`. Every consumer (plants, places, cities, feedback, notifications, care-plan, moving) reads those two methods, so they all inherit the fix without per-service edits. The **only** privilege an admin retains is the ability to set `actingAsOwnerId`.

This is a deliberate behavior change to the ownership layer; the existing ownership tests that assert "an ADMIN reads any owner" are rewritten to "an ADMIN defaults to own; acting-as reaches the target."

## 3. How impersonation is carried (BFF session + role-gated header)

Decision: keep **identity** in the JWT (unchanged) and the **"who am I viewing"** state in the BFF's existing sealed server-side session; the proxy forwards it to the API as a header the API honors only for admins. (Chosen over re-minting a token with an `actAs` claim: avoids double-token lifecycle, TTL/revocation puzzles, and per-switch re-issue; reuses infrastructure that already exists; security is equivalent because the header is role-gated.)

Flow:

1. The admin opens the admin-only Owners view and clicks **Act as X**.
2. The frontend calls a BFF route that, after confirming the session user is ADMIN, resolves X's display label server-side and stores `actingAsOwnerId` + `actingAsLabel` in the sealed session.
3. The BFF proxy adds `X-Act-As-Owner: <ownerId>` to every forwarded API request while that state is present.
4. The API guard, after verifying the token and building the `Actor`, applies the header **only if `actor.role === 'ADMIN'`**, setting `actingAsOwnerId`. A USER's header is ignored (no escalation).
5. **Stop acting as** clears the session state; **logout** destroys the whole session, so a fresh login always starts as yourself.

## 4. API changes (`repos/my-plants-api`)

### 4.1 Actor + guard
- `src/auth/actor.ts`: add optional `actingAsOwnerId?: string` to `Actor`.
- `src/auth/jwt-auth.guard.ts`: read the `x-act-as-owner` request header; set `actor.actingAsOwnerId` **only when `actor.role === 'ADMIN'`** and the header is a non-empty string. The header value is trusted only as a scoping target — an admin pointing at a non-existent owner simply sees empty results (no security impact), so no per-request existence check is required.

### 4.2 OwnerService (`src/owner/owner.service.ts`)
- Add `currentEffectiveOwnerId()` (private or public helper): `actor.actingAsOwnerId ?? actor.ownerId`.
- `currentOwnerId()` → returns the effective owner (used by creates/writes and own-scoped reads).
- `ownerFilter()` → returns `{ ownerId: effectiveOwnerId }` **always** (the `{}` admin branch is removed).
- `currentRole()` → unchanged: the **real** token role (drives admin-only gating, unaffected by impersonation).
- Add `currentActingAsOwnerId(): string | null` for `/auth/me` to report impersonation state.

### 4.3 New `GET /owners` (admin-only, role-gated, NOT owner-scoped)
- New module (e.g. `src/owners/`) exposing `GET /owners`.
- Guarded by the **real role**: if `currentRole() !== 'ADMIN'` → `ForbiddenException` (403).
- Returns the full owner list for the picker: `[{ ownerId, username, role }]` via Owner→User (1:1; `User.ownerId` is unique). If an owner has no linked user, fall back to `Owner.name` for the label and `role: null`.
- This endpoint is intentionally **not** owner-scoped (it is the impersonation picker source); its safety comes from the role gate.

### 4.4 `GET /auth/me` (API endpoint — distinct from the BFF `me`)
- Extend the **API** response (`src/auth/auth.controller.ts`) to include `actingAs: { ownerId: string } | null` (derived from `currentActingAsOwnerId()`) as the *authoritative* impersonation state the API actually resolved — useful for verification/diagnostics and future API clients.
- Note the frontend does **not** read this directly: it renders the banner from the **BFF** `me` (`server/api/auth/me.get.ts`, §5.1), which is session-backed and carries the human-readable label. The two are consistent by construction (API `me` is id-only; BFF `me` is id + label, both reflecting the same session state).

### 4.5 B8 — `MovingService.simulate`
- Resolve the primary city as today. Compute the scoped plant set `where: { ownerId, place: { cityId: primary.id } }` when a primary exists.
- **New empty-primary fallback:** if a primary exists **and** the scoped set is empty, re-query all of the owner's plants (`where: { ownerId }`). (The existing no-primary fallback — already "all owner plants" — is unchanged.)
- Include the place's city: change the include to `place: { include: { city: true } }`.
- Each `PlantViability` gains:
  - `placeCityName: string` — `plant.place.city.name`.
  - `inPrimaryCity: boolean` — `primary ? plant.place.cityId === primary.id : true` (no-primary case → `true`, no warning).
- Behavior summary: primary with plants → only those, all `inPrimaryCity: true`; primary empty → all plants, the off-primary ones flagged `false`; no primary → all plants, all `true`.

### 4.6 care-plan recompute scoping (decision, documented)
- `POST /care-plan/recompute` today branches on `currentRole()`: ADMIN recomputes **all** owners, USER recomputes own. For consistency with the effective-owner model, recompute now scopes to the **effective owner** (admin recomputes their own / the target's garden). The all-owners recompute remains available through the startup/cron job (`applyAllDueMoves → recomputeAll`). Rationale: an HTTP "recompute everyone" is not a needed user action and conflicts with the new default-own model.

### 4.7 No schema/migration impact
No new tables, no Prisma migration, no env changes. Audit was explicitly dropped.

## 5. Frontend changes (`repos/my-plants-web`)

### 5.1 BFF routes + proxy
- `POST /api/acting-as` (`server/api/acting-as.post.ts`): require the session user to be ADMIN (else 403); take `{ ownerId }`; resolve the label **server-side** from `GET /owners` (do not trust a client-supplied label); store `actingAsOwnerId` + `actingAsLabel` in the session via `setUserSession` (merging existing `secure.token`).
- `DELETE /api/acting-as` (`server/api/acting-as.delete.ts`): clear the impersonation fields from the session.
- Catch-all proxy `server/api/[...].ts`: when the session has `actingAsOwnerId`, add `X-Act-As-Owner: <id>` to the forwarded headers.
- `server/api/auth/me.get.ts`: include the session's `actingAs: { ownerId, label } | null` in its response so the client renders the banner without an extra round-trip.

### 5.2 `composables/useApi.ts` + `types/api.ts`
- Add `listOwners()`, `actAs(ownerId)`, `stopActingAs()`. Add the `PlantViability` fields (`placeCityName`, `inPrimaryCity`) and the owner-list / `me.actingAs` types.

### 5.3 Admin-only Owners view (`pages/admin/owners.vue`)
- Lists owners (username + role) via `useApi().listOwners()`, rendered with existing `CardGrid`/`Card`/`Button`. Each row has an **Act as** button except the admin's own row (marked "You", no button).
- **Admin-only rendering invariant:** the route content is gated by the real session role — for a non-admin user the view (and its nav entry) is **not rendered at all** (not merely hidden via CSS). The backend `GET /owners` 403 is the hard gate; the frontend gate prevents a USER from ever seeing the surface.

### 5.4 Account menu + global banner
- `components/AccountMenu.vue`: an **admin-only** entry "Owners / Switch user" linking to `pages/admin/owners.vue`, plus "Stop acting as" when impersonating. **This entry only mounts for an ADMIN session** — a normal USER's account menu does not include it.
- `layouts/default.vue`: a persistent, hard-to-miss **global banner** when impersonating — `Acting as <label> — Stop acting as` — so the admin cannot mistake the target's data for their own. Stop calls `stopActingAs()` then refreshes session/data.

### 5.5 Moving warning
- `pages/moving.vue`: for each simulated plant with `inPrimaryCity === false`, show a warning: *"This plant is not in your current city — it is in `<placeCityName>`."* (User-facing strings stay in English in place per the deferred-i18n rule.)

## 6. Security invariants

- The `X-Act-As-Owner` header is honored **only** when the verified token's role is ADMIN; a USER's header is ignored — no privilege escalation, even hitting the API directly on `:8000`.
- The effective owner is the **single** scoping source for all reads and writes, so an admin acting-as only ever touches the target's resources; stamping on create uses the effective owner.
- Impersonation state lives in the sealed, httpOnly BFF session; the client cannot read or tamper it. The banner label is resolved server-side.
- Acting-as does not change the role, so admin-only endpoints (`GET /owners`, `POST /api/acting-as`) stay gated by the real role and the admin can always stop/switch.
- Admin-only frontend surfaces (Owners view, the account-menu entry) do not render for a USER session.

## 7. Testing & verification

- **API (unit, Vitest):**
  - Effective owner: USER scoped to own; ADMIN with no header scoped to own (**new** — replaces "admin sees all"); ADMIN with `x-act-as-owner` reads **and** writes the target; USER with the header is ignored (stays own-scoped).
  - `GET /owners`: 403 for a USER; full list for an ADMIN; label fallback when an owner has no user.
  - `simulate` fallback: primary with plants → only those (`inPrimaryCity` all true); primary empty → all plants with off-primary flagged false + correct `placeCityName`; no primary → all, all true.
  - Rewrite the existing ownership tests (cities/plants/places) to the effective-owner model.
- **Web:** `npm run typecheck && npm run build`.
- **E2E (qa-engineer, LOCAL ONLY):** admin act-as flow end to end (open Owners view, Act as another owner, see that owner's resources in `/plants` etc., banner visible, Stop returns to own resources); a normal USER never sees the Owners view/menu entry; Moving shows the off-primary warning when the primary has no plants.

## 8. Suggested implementation phases (for `writing-plans`)

1. **Effective-owner model** — `Actor` + guard header + `OwnerService` (drop `{}`); rewrite ownership tests.
2. **Owners endpoint + me** — `GET /owners` (role-gated) and `/auth/me` `actingAs`.
3. **B8 simulate fallback + flags** — empty-primary fallback, `placeCityName`/`inPrimaryCity`, tests.
4. **BFF wiring** — `POST`/`DELETE /api/acting-as`, proxy header, `me` passthrough, `useApi` methods + types.
5. **Frontend surfaces** — admin-only Owners view, account-menu entry, global banner, Moving warning.
6. **E2E + docs** — qa-engineer run; update `docs/architecture.md` (ownership/effective-owner + Acting As), `docs/care-engine.md` (simulate empty-primary fallback), the API collection, and the roadmap.
