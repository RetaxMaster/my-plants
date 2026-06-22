# Frontend Redesign — Phase 3: Form, Feedback & Overlay Components Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the form, feedback, navigation, task, and overlay components — including the accessible `Modal` that the page-port phases depend on — plus the `useTaskMeta` composable.

**Architecture:** Reusable `<script setup lang="ts">` SFCs styled from tokens. Form inputs use `v-model`. `Modal` is the reusable overlay behind the edit modals (Phase 5/6).

**Tech Stack:** Vue 3 `<script setup>`, TypeScript, `defineModel`/`v-model`, Teleport, scoped CSS on tokens.

**Reference:** spec §"Component library"; visual source `.design-import/_ds/.../_ds_bundle.js`; `TASK_LABELS`/`TASK_ICONS` live in the bundle and current `utils/tasks.ts`. Commands from `repos/my-plants-web/`. Verify each task with `npm run typecheck && npm run build`.

---

### Task 1: useTaskMeta composable

**Files:** Create `composables/useTaskMeta.ts`

- [ ] Export `TASK_LABELS: Record<TaskCode,string>` and `TASK_ICONS: Record<TaskCode, string>` (icon aliases for `AppIcon`). Source the labels from the existing `utils/tasks.ts` (`TASK_LABELS` already exists there — reuse/re-export, do not fork) and the icons from the bundle's `TASK_ICONS`. If `utils/tasks.ts` already exports labels, import and re-expose; only add the icon map. Verify build.

### Task 2: Input

**Files:** Create `components/ui/Input.vue`

- [ ] Props `type` (default `text`), `icon` (alias, optional leading), `placeholder`, `disabled`, `error` (string); `modelValue` via `v-model`. Green focus ring (`--shadow-focus` + `--border-brand`), `--radius-md`, `--border-default`. Verify build.

### Task 3: SelectField

**Files:** Create `components/ui/SelectField.vue`

- [ ] Props `options: {label:string;value:string}[]`, `placeholder`; `modelValue` via `v-model`. Named `SelectField` to avoid auto-import clash with native `select`. Styled like Input. Verify build.

### Task 4: Switch

**Files:** Create `components/ui/Switch.vue`

- [ ] `modelValue` boolean via `v-model`. Knob slides 200ms; on = `--brand-primary`. Accessible (`role="switch"`, `aria-checked`, keyboard toggle). Verify build.

### Task 5: FormGroup

**Files:** Create `components/ui/FormGroup.vue`

- [ ] Props `label`, `hint`, `error`, `required` (bool). Default slot wraps the control; label above, hint/error below (error in `--care-poor`). Verify build.

### Task 6: Alert

**Files:** Create `components/ui/Alert.vue`

- [ ] Props `color` (`amber`|`red`|`green`), `title`, `description`, `icon` (alias, optional). Soft-tinted box using care tokens. Verify build.

### Task 7: NavTabs

**Files:** Create `components/ui/NavTabs.vue`

- [ ] Props `items: {key:string;label:string;icon:string}[]`, `active` (key), `variant` (`top`|`bottom`); emits `select`. `top` = horizontal ghost row; `bottom` = fixed mobile tab bar (icon over label). Active item uses `--nav-active-bg`/`--nav-active-text`; idle `--nav-idle`. Verify build.

### Task 8: TaskRow

**Files:** Create `components/ui/TaskRow.vue`

- [ ] Props `task` (TaskCode), `status` (`overdue`|`today`|`upcoming`), `dueLabel` (string), `withDoneDate` (bool, default false). **Emits MUST carry the task** so the parent knows which row acted (Today and detail call `sendFeedback(plantId, { task, ... })`): `done` payload `{ task: TaskCode; occurredOn?: string }`, `postpone` payload `{ task: TaskCode }`. Renders task label (`TASK_LABELS`) + icon (`TASK_ICONS` via `AppIcon`) + a status `Badge` (overdue→red, today→amber, upcoming→neutral) + Done/Postpone buttons; when `withDoneDate`, an optional `<input type="date">` whose value (empty → `undefined`) rides along on `done`. Concrete contract:

```ts
const props = withDefaults(defineProps<{
  task: TaskCode; status: 'overdue'|'today'|'upcoming'; dueLabel: string; withDoneDate?: boolean
}>(), { withDoneDate: false });
const emit = defineEmits<{ done: [{ task: TaskCode; occurredOn?: string }]; postpone: [{ task: TaskCode }] }>();
const doneDate = ref('');
const onDone = () => emit('done', { task: props.task, occurredOn: doneDate.value || undefined });
const onPostpone = () => emit('postpone', { task: props.task });
```
Verify build.

### Task 9: Modal

**Files:** Create `components/ui/Modal.vue`

- [ ] Props `modelValue` (open, v-model), `title`; slots default (body) + `footer`. Behavior (accessibility is the point — do not ship a bare div):
  - `Teleport to="body"`; backdrop + centered panel (`--surface-card`, `--radius-xl`, `--shadow-lg`).
  - `role="dialog"`, `aria-modal="true"`, labelled by the title id.
  - Close on Escape and backdrop click (emit `update:modelValue=false`).
  - Focus trap: focus the panel on open, keep Tab within it; restore focus to the previously-focused element on close.
  - Body scroll-lock while open.
- [ ] **Verify:** `npm run typecheck && npm run build` green.
- [ ] **Commit:** `git add components/ui composables/useTaskMeta.ts && git commit -m "feat(web): form, feedback, nav, task & modal components"` (new files — use `git add`, not `-am`).
