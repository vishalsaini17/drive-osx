# Developer and AI Agent Guide

The operating manual for working in this repository. [CLAUDE.md](../../CLAUDE.md) says
what the platform should be; this says how to change it without breaking it.

---

## Before changing code

1. Read [System Overview](../overview.md). Ten minutes, and it prevents
   most of the mistakes below.
2. Find your area in [Application Inventory](../reference/applications.md).
   **Check its status before assuming it works** — several applications look
   complete and persist nothing.
3. Check [Integration Map](../reference/integration-map.md) §10 for what your change
   touches downstream.
4. Check [Audit and Plan](../status/audit-and-plan.md)
   for a task already describing it.
5. Read the relevant [decision record](../architecture/decisions/) before
   reversing anything. Each says what breaks if you do.

## The six traps in this codebase

These are not hypothetical. Each one has already caused a defect here.

### 1. Organization scoping is wrong for anything social

Every user registers into their **own** `personal` organization. Two users who
sign up independently share no organization, ever.

```sql
-- WRONG for a conversation, a message, a chat request or a contact
WHERE c.organization_id = $currentUserOrg

-- RIGHT — the real boundary is participation, involvement or ownership
JOIN conversation_participants cp ON cp.conversation_id = c.id AND cp.user_id = $userId
```

This exact mistake made messaging entirely unusable (TASK-001, TASK-002).
Files, mail, meetings and audit *are* genuinely tenant-scoped — the distinction
matters. See the table in [Architecture](../architecture.md)
§"Every user starts alone in their own tenant".

### 2. Duplicate column names silently overwrite each other

```sql
-- WRONG: USER_COLUMNS also selects u.id, so row.id is the USER's id
SELECT r.id, r.status, ${USER_COLUMNS} FROM chat_requests r JOIN users u ...

-- RIGHT
SELECT r.id AS request_id, r.status, ${USER_COLUMNS} FROM ...
```

The driver keeps the last column of a duplicated name. No error, no type
error — just the wrong id, and every accept 404s (TASK-020). **Alias explicitly
whenever a query joins two tables that both have `id`.**

### 3. A `catch` that only logs is a lie to the user

```ts
// WRONG — the UI now shows a restore that never happened
try { await FileService.restoreFile(id); }
catch (error) { console.warn('Failed to restore:', error); }

// RIGHT — put the state back and say what happened
catch (error) {
  set(previous);
  addNotification({ text: describeFileFailure(`"${file.name}" could not be restored`, error), type: 'error' });
}
```

CLAUDE.md §20, §35.15 and §48. Offline and denied need different wording,
because the user's next action differs.

### 4. Network placement is not authentication

`POST /mail/receive` was unauthenticated on the reasoning that it was
"internal". The API is published on a host port; a live probe delivered
phishing mail into a real mailbox with no credential at all (TASK-003).

**If an endpoint has no user session, give it a service credential.** There is
now a pattern to copy: `platform/authentication/mail-gateway.ts`.

### 5. Mock data outlives its welcome

Seeded arrays get shipped and users see invented people in their contact list.
When you build a UI ahead of its API, the placeholder must be an **empty state
that explains itself**, not fabricated rows. Deleted this audit:
`apps/contacts/mockContacts.ts`, the Messenger seed arrays, and a
`count × 4.2 KB` "reclaimable space" figure.

### 6. The shell store is not a place to put per-frame state

`systemStore` replaces the whole `windows` array on every change, and six
components subscribe to it. Writing to it from a pointer-move handler
re-renders the entire desktop per frame:

```ts
// WRONG — sixty store writes a second, and the desktop re-renders for each
const onPointerMove = (e) => onMove(app.id, x, y);

// RIGHT — move the element, commit once when the pointer is released
const onPointerMove = (e) => { live.current = { x, y }; schedulePaint(); };
const onPointerUp   = ()  => onMove(app.id, live.current.x, live.current.y);
```

This made window dragging stutter and then crash the desktop outright with
*Maximum update depth exceeded* — reported from `Dock.tsx`, which was innocent.
The same reasoning applies to any high-frequency input: scroll position, canvas
strokes, resize handles.

Two corollaries worth internalising:

* **A rebuilt array is a state change.** `setState(items.map(...))` re-renders
  even when every element is identical. Compare before setting.
* **Depend on what you read.** An effect that only needs window *ids* should
  key on a signature of them, not on `windows`.

Full treatment in [Windows and the dock](../features/shell-windows-and-dock.md).

---

## While changing code

### Follow the existing shape

Backend modules are `*.routes.ts` / `*.service.ts` / `*.repository.ts`. Routes
validate with Zod and delegate; services hold rules and authorization;
repositories hold SQL. **A module never reads another module's tables** — call
its service. That is what keeps later extraction a move rather than a rewrite.

Frontend applications use `platform.*`, never `fetch`. A new capability belongs
in `platform/index.ts` so every application gets it consistently.

### The frontend is a desktop, not a page

Three assumptions that hold on an ordinary web page are false here.

**Breakpoints measure the wrong thing.** Tailwind's `sm:`/`md:`/`lg:` prefixes
respond to the browser viewport, which in this platform is the entire desktop.
An application in a 400px window on a 1400px screen still matches `md:`, so it
renders a two-column layout into a pane too narrow to hold it and the columns
overlap. Applications must measure themselves with
`platform/layout/useContainerWidth.ts`. The Contacts detail pane was fixed this
way; thirteen applications still carry the latent bug (TASK-025).

**Tailwind only generates classes it can see as literal text.** A class
assembled at runtime never exists:

```tsx
// WRONG — generates nothing, silently
<div className={`hover:${shell.text} placeholder:${shell.textSubtle}`} />

// RIGHT — a spelled-out token, or an inline style for a runtime colour
<div className={shell.placeholder} style={{ backgroundColor: accent }} />
```

**There is no ESLint here**, so `react-hooks/rules-of-hooks` never runs. A hook
placed after an early `return null` changes the hook count between renders and
unmounts the whole tree. That is exactly how right-clicking the desktop produced
a white screen. Check hook placement by eye in any component with an early
return.

### Authorization is server-side

Frontend checks shape the UI; they are never the control. Every resource access
goes through `platform/authorization/access-control.ts`. Denied access returns
`404`, not `403`, so the API does not confirm a resource exists.

### Database changes

Applied migrations are **immutable** — the runner verifies checksums and will
refuse to start. Add a new numbered file. New tenant-scoped tables carry
`organization_id`; new personal tables carry `owner_id`. Never edit a file
under `migrations/` that has already run.

### Configuration changes

> Adding, renaming or removing a variable in a `.env` means the same edit to
> its `.env.example`, in the same commit.

`.env` is never committed, so `.env.example` is the only description of what a
service needs. Adding a key to a validated env schema means adding it to
`.env.example` too, even if nothing sets it yet. Verify with
`./scripts/check-env.sh`.

### Domain events

Adding an event to `DomainEventMap` is half the job. **Check whether it needs a
subscriber in `workers/handlers.ts`** — three chat events were published for a
whole release with nobody listening, so no notification was ever produced
(TASK-004). Handlers are at-least-once, so they must be idempotent.

### Errors

Say what happened, why, whether the work was saved, and what to do next.
`describeError` in Messenger and `describeFileFailure` in the system store are
the pattern. "Something went wrong" is not acceptable (CLAUDE.md §36).

### Every feature needs its states

Happy path, loading, empty, error, offline, and no-permission. An application
that renders only the populated case is not finished (CLAUDE.md §49).

---

## After changing code

```sh
./scripts/check-env.sh
cd drive-osx-api && npx tsc --noEmit && npm test
cd drive-osx-ui  && npx tsc --noEmit && npx vite build
./tests/e2e/platform-workflows.sh
./tests/e2e/messaging-and-contacts.sh
```

**A green typecheck means nothing about SQL.** If you touched a query, run the
E2E probes — that is the only thing here that will catch it.

Then update the documentation in the same change:

| If you changed | Update |
| -------------- | ------ |
| Architecture or a boundary | `docs/architecture.md` |
| An API contract | `docs/reference/integration-map.md`, the service client |
| The schema | `docs/overview.md` §4 migration table |
| Application status or capability | `docs/reference/applications.md` |
| Shell, window or dock behaviour | `docs/features/shell-windows-and-dock.md` |
| How one feature works end to end | a doc in `docs/features/` |
| A significant decision | a new `docs/architecture/decisions/ADR-*.md` |
| Fixed or found a defect | `docs/status/audit-and-plan.md` |
| Test coverage | `docs/guides/testing.md` |

The documentation map itself is in [docs/README.md](../README.md).

## Reporting honestly

This matters more than it sounds, because most of this repository's
documentation debt came from claiming completion.

* Say what you **verified** and how. "Typecheck passes" is not "it works".
* There is no browser automation here. **UI rendering and interaction cannot
  be verified** — say so rather than implying otherwise.
* If part of a task is blocked, finish everything else and state plainly what
  was left and why. Do not quietly reduce scope.
* Use `UNKNOWN` or `BLOCKED` where that is the truth, and say what would
  resolve it.

## Quick reference

| Task | Path |
| ---- | ---- |
| Add an API endpoint | `modules/<domain>/<domain>.routes.ts` + `.service.ts`, mount in `app.ts` |
| Add a UI capability | `platform/<area>/<Area>Service.ts`, expose in `platform/index.ts` |
| Add an application | `apps/<name>/index.tsx`, register in `platform/registry/AppRegistry.tsx` |
| Change the schema | New file in `infrastructure/database/migrations/` |
| Add a background job | `registerJobHandler` in `workers/handlers.ts` |
| React to a state change | `onEvent` in `workers/handlers.ts` |
| Add a per-app preference | `settings.appPreferences.<app>`, surface in `PreferencesDialog` |
