# Auth Phase 6 — Web login page + route guard + logout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The user-facing login wall: a `/login` page, a global route middleware that redirects unauthenticated navigation (except the blog), a logout action, and graceful handling of a mid-session `401`.

**Architecture:** `nuxt-auth-utils` exposes `useUserSession()` (`loggedIn`, `user`). A global middleware gates navigation; public routes are `/login`, `/blog`, `/blog/[id]`. The app chrome shows a logout button when logged in.

**Tech Stack:** Nuxt 3 / Vue 3 + Nuxt UI.

**Repo:** `repos/my-plants-web`. Branch: `feature/user-auth`.

---

### Task 1: Login page

**Files:**
- Create: `pages/login.vue`

- [ ] **Step 1: Implement**

```vue
<script setup lang="ts">
const username = ref('');
const password = ref('');
const error = ref('');
const route = useRoute();
const { fetch: refreshSession } = useUserSession();

async function submit() {
  error.value = '';
  try {
    await $fetch('/api/auth/login', { method: 'POST', body: { username: username.value, password: password.value } });
    await refreshSession();
    const redirect = (route.query.redirect as string) || '/';
    await navigateTo(redirect);
  } catch {
    error.value = 'Invalid username or password.';
  }
}
</script>

<template>
  <div class="max-w-sm mx-auto mt-16">
    <h2 class="text-lg font-semibold mb-4">Sign in</h2>
    <UForm :state="{ username, password }" class="grid gap-3" @submit="submit">
      <UFormGroup label="Username"><UInput v-model="username" autocomplete="username" /></UFormGroup>
      <UFormGroup label="Password"><UInput v-model="password" type="password" autocomplete="current-password" /></UFormGroup>
      <p v-if="error" class="text-sm text-red-500">{{ error }}</p>
      <UButton type="submit" :disabled="!username || !password">Sign in</UButton>
    </UForm>
  </div>
</template>
```

- [ ] **Step 2: Mark `/login` so the global middleware never bounces it** (handled in Task 2's public list). Commit.

```bash
git add pages/login.vue
git commit -m "feat(auth): login page"
```

---

### Task 2: Global route middleware (login wall, blog public)

**Files:**
- Create: `middleware/auth.global.ts`

- [ ] **Step 1: Implement**

```ts
const PUBLIC = [/^\/login$/, /^\/blog$/, /^\/blog\/.+$/];

export default defineNuxtRouteMiddleware((to) => {
  if (PUBLIC.some((re) => re.test(to.path))) return;
  const { loggedIn } = useUserSession();
  if (!loggedIn.value) {
    return navigateTo(`/login?redirect=${encodeURIComponent(to.fullPath)}`);
  }
});
```

- [ ] **Step 2: Build + typecheck**

Run: `npm run typecheck && npm run build`
Expected: green.

- [ ] **Step 3: Commit**

```bash
git add middleware/auth.global.ts
git commit -m "feat(auth): global route guard (login wall; blog public)"
```

---

### Task 3: Logout action in the app chrome

**Files:**
- Modify: `components/AppNav.vue`

- [ ] **Step 1: Add a logout button** shown only when logged in:

```vue
<script setup lang="ts">
const { loggedIn, user, clear } = useUserSession();
async function logout() {
  await $fetch('/api/auth/logout', { method: 'POST' });
  await clear();
  await navigateTo('/login');
}
</script>
```

In the template, render (placement consistent with existing nav styling):

```vue
<template>
  <!-- existing nav ... -->
  <span v-if="loggedIn" class="ml-auto flex items-center gap-2 text-sm">
    <span class="text-gray-500">{{ user?.username }}</span>
    <UButton size="xs" variant="ghost" @click="logout">Log out</UButton>
  </span>
</template>
```

> Match the actual existing AppNav markup; do not restructure unrelated nav.

- [ ] **Step 2: Commit**

```bash
git add components/AppNav.vue
git commit -m "feat(auth): logout action in app nav"
```

---

### Task 4: Handle a mid-session 401 (token revoked/expired)

**Files:**
- Modify: `composables/useApi.ts`

- [ ] **Step 1:** Wrap the `api()` helper so a `401` from the proxy clears the session and redirects to `/login` (client-side only). Keep it minimal:

```ts
const api = async <T>(path: string, opts?: Parameters<typeof $fetch>[1]) => {
  try { return await fetcher<T>(`/api${path}`, opts as any); }
  catch (e: any) {
    if (import.meta.client && (e?.statusCode === 401 || e?.response?.status === 401)) {
      const { clear } = useUserSession();
      await clear();
      await navigateTo('/login');
    }
    throw e;
  }
};
```

> Note: `useUserSession()` is a composable — if calling it inside this catch causes a scope warning, capture `const session = useUserSession()` in `useApi`'s setup scope and use `session.clear()` here. Public blog calls never hit this path (no 401 without a session).

- [ ] **Step 2: Typecheck + build + suite**

Run: `npm run typecheck && npm run build && npm test`
Expected: green.

- [ ] **Step 3: Commit**

```bash
git add composables/useApi.ts
git commit -m "feat(auth): redirect to /login on mid-session 401"
```
