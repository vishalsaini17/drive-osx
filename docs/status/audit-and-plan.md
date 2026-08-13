# Project Audit and Implementation Plan

Audit date: 2026-08-13
Scope: the whole repository — `drive-osx-ui`, `drive-osx-api`, `drive-osx-mail`,
Compose stack, PostgreSQL schema, documentation.

Method: static review of every module, plus **live probing of the running
stack** (`docker compose` up, 7 containers healthy) with an end-to-end HTTP
script covering registration, login, tenancy isolation, files, trash, search,
messaging, notifications, audit and mail.

**Verification limits.** There is no browser automation in this environment.
Anything marked `VERIFIED (API)` was executed against the live API and the
response observed. Anything marked `VERIFIED (BUILD)` passed typecheck/build.
UI rendering and user interaction are reasoned from source and are marked
`UNVERIFIED (UI)` — they need a human or a browser harness to confirm.

---

## Issue summary

| Priority | Found | Fixed | Remaining |
| -------- | ----- | ----- | --------- |
| CRITICAL | 6     | 6     | 0         |
| HIGH     | 8     | 8     | 0         |
| MEDIUM   | 8     | 2     | 6         |
| LOW      | 4     | 0     | 4         |
| **Total**| **26**| **16**| **10**    |

One CRITICAL (`TASK-020`) was found **by running the fixes**, not by reading
the code — see below.

Remaining items are documented below with the reason each was deferred. None
is a regression; all are pre-existing gaps recorded so they are not lost.

**Later additions.** `TASK-025` and `TASK-026` were raised after the audit
date, during shell work on window dragging and dock behaviour. They are
recorded here so the numbering stays the single sequence the rest of the
documentation cites. This table is recounted from the task list below rather
than incremented by hand — it had drifted once already, understating the count
by three.

---

## TASK-001 — Messaging directory search can never find anyone

* **Priority**: `CRITICAL`  **Status**: `FIXED`  **Risk**: high (feature dead)
* **Module**: `drive-osx-api` → `modules/messaging`
* **Feature**: "search by username and send a chat request"

**Problem.** `searchUsers` joins `memberships` on `actor.organizationId`, so it
only ever returns co-members of the caller's own organization. Registration
provisions every new user a **private `personal` organization**
(`identity.service.ts` → `createOrganizationInTransaction(..., type: 'personal')`).
Two users who sign up independently are therefore never co-members, and the
directory search returns an empty list for every query.

**Evidence (live).** Database state: `6 users`, `6 organizations`, all of type
`personal`. E2E probe: user A searched for user B's exact username and received
`{"users":[]}` with HTTP 200.

**Root cause.** Direct messaging was modelled as an intra-organization feature,
but the product's registration flow is single-user-per-tenant. The two
assumptions are incompatible.

**Impact.** The entire chat-request → conversation → messaging feature is
unreachable through the product's own signup flow. Nothing downstream of
directory search can ever execute.

**Required changes.** Make people *discoverable* across organizations without
making the user table *enumerable*:

* fuzzy (substring) matching stays scoped to organizations the caller shares
  with the subject — unchanged behaviour for real multi-user tenants;
* **exact** `username` or `email` match resolves platform-wide, which is what
  "search by username to send a request" means and what a messenger needs.

**Files**: `modules/messaging/messaging.service.ts`
**Database**: none. **API**: no contract change. **Frontend**: none.
**Tests**: `messaging.service.test.ts` — exact-match reachability, substring
non-enumerability, self-exclusion.

---

## TASK-002 — Conversations invisible to the other participant

* **Priority**: `CRITICAL`  **Status**: `FIXED`  **Risk**: high
* **Module**: `drive-osx-api` → `modules/messaging`

**Problem.** `listConversations` filters `WHERE c.organization_id = $2` against
the *caller's* organization. A conversation stores the **requester's**
organization. Once TASK-001 allows a cross-organization request, the recipient
accepts, both contact rows are written, and then the conversation never appears
in the recipient's sidebar — messages exist but are invisible on one side.

**Root cause.** Same as TASK-001: organization used as the access boundary for
a resource whose real boundary is participation.

**Impact.** Silent, asymmetric data loss from the user's point of view: one
party sees a conversation, the other sees an empty inbox.

**Required changes.** Scope conversation listing by
`conversation_participants` membership — which the `JOIN` already enforces —
and drop the organization predicate. `organization_id` remains on the row as
originating context for audit and analytics. `listMessages`, `sendMessage`,
`markConversationRead` were already participant-scoped via `assertParticipant`
and needed no change.

**Files**: `modules/messaging/messaging.service.ts`
**Tests**: covered by the cross-organization flow test.

---

## TASK-003 — Unauthenticated mail injection with arbitrary spoofed sender

* **Priority**: `CRITICAL`  **Status**: `FIXED`  **Risk**: high (security)
* **Module**: `drive-osx-api` → `modules/mail`

**Problem.** `POST /api/v1/mail/receive` sits **before** `mailRoutes.use(authenticate())`
and requires no credential of any kind. The source comment asserts it is
"reachable only from the internal network", but the API is published on
`0.0.0.0` (`API_PORT`/`API_DEV_PORT`), so the claim does not hold.

**Evidence (live).** With no token, no cookie and no session:

```
POST /api/v1/mail/receive
{"to":"<victim>@driveosx.com","from":"ceo@yourbank.example","subject":"…"}
→ 201 {"message":"Message delivered", …, "folder":"inbox", "isUnread":true}
```

The message landed in the victim's inbox with a fully attacker-chosen `from`.

**Root cause.** A trust boundary was assumed (network isolation) rather than
enforced (a credential). Nothing in the deployment establishes that isolation.

**Impact.** Any party who can reach the API can deliver phishing mail into any
mailbox on the platform, displayed by the client as a genuine received message.

**Required changes.** A shared secret between the SMTP gateway and the API:

* API: `MAIL_GATEWAY_TOKEN` in the validated env schema; a
  `requireMailGateway()` guard on `/mail/receive` comparing the
  `X-Mail-Gateway-Token` header in constant time.
* Gateway: send the header on every delivery.
* Both `.env` / `.env.example` pairs updated per CLAUDE.md §35; Compose passes
  one root value to both services so they cannot drift.
* Defence in depth: the API refuses to boot in production without the token,
  and logs a loud warning if it is unset in development.

**Files**: `platform/configuration/env.ts`, `platform/authentication/authenticate.ts`,
`modules/mail/mail.routes.ts`, `drive-osx-mail/src/config.ts`,
`drive-osx-mail/src/api-client.ts`, 4 env files, `docker-compose.yml`.
**Tests**: gateway-guard unit tests + live probe that an unauthenticated
delivery is now rejected.

---

## TASK-020 — Every chat request accept and decline returned 404

* **Priority**: `CRITICAL`  **Status**: `FIXED`  **Risk**: high
* **Module**: `drive-osx-api` → `modules/messaging`
* **Found**: by executing the fixed flow, not by reading the code

**Problem.** `listChatRequests` selected `r.id` alongside `USER_COLUMNS`, which
also selects `u.id`. A driver building row objects keeps the **last** column of
a duplicated name, so `row.id` held the counterpart's *user* id. The API
therefore handed clients a request id that did not exist in `chat_requests`,
and every `POST /requests/:id/respond` answered `404 Request not found`.

**Evidence (live).** The E2E run sent
`242bbf5c-70fa-4e40-965a-22370a20fd6b`; the database held request
`97f65de1-ed8d-4d4a-b961-6fc8041be3bb` whose `requester_id` was
`242bbf5c-…`. The id being sent was the requester's.

**Root cause.** Two joined tables both have an `id` column and neither was
aliased. Nothing catches this: it is valid SQL, and TypeScript cannot see
inside a query string, so typecheck, build and every unit test passed.

**Impact.** The chat request flow was dead at its final step. A request could
be sent and seen, and never accepted.

**Why it matters beyond this fix.** This is the strongest evidence in the audit
that queries need execution, not review. Three CRITICAL defects, all in SQL,
all invisible to 37 passing unit tests.

**Required changes.** Alias the request id (`r.id AS request_id`) and read it
under that name. A repository-wide scan for the same pattern found one other
candidate (`organizations.repository.ts`), which is safe — its second `id` is
inside a `jsonb_build_object`, not a top-level column.

**Files**: `modules/messaging/messaging.service.ts`
**Tests**: `tests/e2e/messaging-and-contacts.sh` — "B accepts" now asserts 200.

---

## TASK-021 — A message never appeared in an open conversation

* **Priority**: `CRITICAL`  **Status**: `FIXED`  **Risk**: high
* **Module**: `drive-osx-ui` → `apps/messages`

**Problem.** `loadMessages` ran only when `activeConversationId` *changed*, and
the 15-second poll refreshed the conversation **list** only. A recipient sitting
in the thread therefore never saw an incoming message: the sidebar preview
updated while the thread itself stayed frozen. The only way to see it was to
click to another conversation and back, or reopen the app.

**Root cause.** The polling loop refreshed the wrong resource. Nothing kept the
open thread current, and there was no realtime path to compensate.

**Impact.** Messaging looked broken to the recipient even though the message had
been stored correctly and was visible to the API.

**Required changes.** A refetch of the open conversation — realtime-driven,
with a 10s visible-tab poll as fallback — using a `silent` mode so a background
refresh does not flash a spinner or fight the scroll position.

**Files**: `apps/messages/index.tsx`.
**Tests**: `tests/e2e/realtime-messaging.sh`.

---

## TASK-022 — Nothing in the browser consumed the realtime gateway

* **Priority**: `CRITICAL`  **Status**: `FIXED`  **Risk**: high
* **Module**: `drive-osx-ui` → new `platform/realtime`

**Problem.** The API has shipped a per-user notification gateway since it was
built: `/ws` authenticates a socket, `deliverToUser` pushes to it, and
`createNotification` publishes every notification to Redis for fan-out. **No
client ever connected.** The only `new WebSocket` in 148 UI files was inside
Meet, for meeting signalling. Every notification the server pushed was
discarded.

**Impact.** No realtime anything. Messenger polled; the notification centre only
ever showed locally generated entries; a message could not reach a user whose
Messenger window was closed, because closing a window unmounts the component
(`AppWindow` returns `null` when `!isOpen`) and stops its polling.

**Required changes.** A shell-level `RealtimeClient` — connected for the whole
session rather than by any application, since the point is to hear about a
message when Messenger is *not* running — with backoff reconnection, a
heartbeat, and id-based deduplication.

**Files**: `platform/realtime/RealtimeClient.ts`,
`shell/notifications/useRealtimeNotifications.ts`, `App.tsx`.

---

## TASK-023 — The development server never proxied `/ws`

* **Priority**: `HIGH`  **Status**: `FIXED`
* **Module**: `drive-osx-ui` → `vite.config.ts`

**Problem.** The client opens its socket against the page origin. The UI image's
nginx config has a correct `location /ws` block with the upgrade headers, but
`vite.config.ts` proxied only `/api/v1`. In development every WebSocket
connection therefore failed — **including Meet's signalling**, which is why
realtime had never worked locally while appearing correct in production.

**Root cause.** Two separate places configure the same route, and only one was
kept in step.

**Required changes.** `server.proxy['/ws']` with `ws: true`, which is what makes
the dev server perform the HTTP upgrade.

**Tests**: `tests/e2e/realtime-messaging.sh` deliberately opens its socket
through the **UI origin**, so this cannot regress unnoticed.

---

## TASK-024 — No native system notifications existed

* **Priority**: `HIGH`  **Status**: `FIXED`
* **Module**: `drive-osx-ui` → new `platform/notifications`

**Problem.** The browser Notification API was never used — zero occurrences of
`new Notification`, `requestPermission` or `showNotification` in the repository.
"Notifications" meant an in-app panel, which by definition cannot reach a user
who is not looking at the app.

**Required changes.** A `SystemNotifier` wrapper that degrades quietly when
unsupported, unpermitted or in an insecure context; permission requested from a
user gesture in the Notifications panel (never on load, which can get an origin
permanently blocked); the notification carries the sender's name and a message
preview, is tagged per conversation so a burst replaces rather than stacks, and
routes to the conversation on click.

**Files**: `platform/notifications/SystemNotifier.ts`,
`shell/notifications/useRealtimeNotifications.ts`,
`shell/notifications/SystemNotificationPopup.tsx`,
`shell/state/systemStore.tsx` (deep-link target), `workers/handlers.ts`
(preview text in the payload).

---

## TASK-004 — Chat domain events have no subscribers

* **Priority**: `HIGH`  **Status**: `FIXED`
* **Module**: `drive-osx-api` → `workers/handlers.ts`

**Problem.** `chat.request_sent`, `chat.request_accepted` and
`chat.message_sent` are declared in `DomainEventMap` and published
transactionally, but `registerDomainEventHandlers()` subscribes to none of
them. Every other domain area (`file.shared`, `mail.received`,
`user.registered`, `organization.member_added`) creates a notification.

**Impact.** A user receives no notification for an incoming chat request or a
new message. Requests are discoverable only by opening Messenger and looking,
so the request flow stalls in practice.

**Required changes.** Subscribe the three chat events and create notifications
for the counterpart, reusing `createNotification`. Handlers must be idempotent
(the queue is at-least-once) and must not notify the actor about their own
action.

**Files**: `workers/handlers.ts`.

---

## TASK-005 — Contacts application runs entirely on fabricated people

* **Priority**: `HIGH`  **Status**: `FIXED`
* **Module**: `drive-osx-ui` → `apps/contacts`; new `modules/contacts` in API

**Problem.** `apps/contacts/mockContacts.ts` ships five invented contacts with
Unsplash headshots, seeded into `localStorage` on first run. The `contacts` and
`user_presence` tables exist (migration 0004) and rows are written when a chat
request is accepted, but **no CRUD or presence endpoint exists**, so the app
cannot read them.

**Impact.** Directly contradicts the standing requirement to remove mock data.
Contacts are per-browser, lost on cache clear, invisible across devices, and
show no real connection status.

**Required changes.** New `modules/contacts` (routes/service) exposing contact
CRUD, presence read and a presence heartbeat; a `ContactsService` client; the
Contacts app rewritten against it with loading/empty/error states.

**Files**: API `modules/contacts/*`, `app.ts`; UI
`platform/contacts/ContactsService.ts`, `apps/contacts/index.tsx`,
delete `apps/contacts/mockContacts.ts`.

---

## TASK-006 — Trash is dual-sourced and hides backend failures

* **Priority**: `HIGH`  **Status**: `FIXED`
* **Module**: `drive-osx-ui` → `shell/state/systemStore.tsx`, `apps/trash-bin`

**Problem.** The Trash app reads `deletedFiles` from the Zustand store, hydrated
from `localStorage['webos-trash']`. The API maintains its own trash
(`GET /files/trash`). The two are never reconciled. Worse, the store's
`handleRestoreFile` / `handleDeleteFile` / `handleEmptyTrash` call the API and
swallow every failure into `console.warn`, so the UI reports success for an
operation the server rejected.

**Impact.** Restoring a file can appear to work and silently not persist; trash
contents differ per browser. Violates CLAUDE.md §20 (offline/failure states are
first-class), §35.15 (do not silently swallow errors) and §48 (do not hide
network failures from users).

**Required changes.** Load trash from the API as the source of truth, keep the
local list as an offline cache, and surface failures as an explicit error state
with a retry rather than a console line.

**Files**: `shell/state/systemStore.tsx`, `apps/trash-bin/index.tsx`.

---

## TASK-007 — Messenger theme not reachable from Preferences

* **Priority**: `HIGH`  **Status**: `FIXED`
* **Module**: `drive-osx-ui` → `shell/preferences/PreferencesDialog.tsx`

**Problem.** The Messenger theme override is stored at
`settings.appPreferences.messenger.theme` and is settable from Messenger's own
header and View menu, but the Preferences dialog — the documented path
"Preferences → Messenger → Theme" — has no Messenger section.

**Required changes.** Add an Applications section to Preferences exposing the
Messenger theme (System / Light / Dark), reading and writing the same key so
the two entry points cannot disagree.

**Files**: `shell/preferences/PreferencesDialog.tsx`.

---

## TASK-008 — No test coverage for six backend modules

* **Priority**: `HIGH`  **Status**: `FIXED (partially)`
* **Module**: `drive-osx-api`

**Problem.** Tests existed for `files`, `organizations`, `mail` and `roles`
only (37 cases). `messaging`, `meetings`, `sharing`, `notifications`, `search`
and `contacts` had none — including the two modules carrying the CRITICAL
defects above, which is why those defects survived to production shape.

**Required changes.** Add regression tests pinning TASK-001…003 and covering
the new contacts module. Integration coverage requiring a live database remains
a gap (see TASK-016).

**Files**: `modules/messaging/messaging.service.test.ts`,
`modules/contacts/contacts.service.test.ts`,
`platform/authentication/mail-gateway.test.ts`.

---

## TASK-009 — Calendar events are never persisted

* **Priority**: `MEDIUM`  **Status**: `OPEN (documented)`
* **Module**: `drive-osx-ui` → `apps/calendar`

**Problem.** `calendarEvents` lives in the Zustand store and is hydrated from
`localStorage` only. There is no `calendar` module in the API and no
`calendar_events` table. Events are per-browser and cannot be shared, invited
to, or synced.

**Why deferred.** This is a **missing feature**, not a defect: it needs a new
domain module (schema, recurrence storage, invitations, reminders, permissions,
tenancy) and is Phase 5 work in CLAUDE.md §32. Implementing it inside this
audit would be a large uncontrolled change, which Rule 7 forbids. Recorded here
with its full shape so it can be scheduled.

**Required changes (when scheduled)**: `calendar_events` +
`calendar_event_attendees` tables, `modules/calendar`, `CalendarService`
client, app rewrite, reminder worker.

---

## TASK-010 — Mail Studio side data is mock

* **Priority**: `MEDIUM`  **Status**: `OPEN (documented)`
* **Module**: `drive-osx-ui` → `apps/mail-studio`

**Problem.** Messages come from the API correctly (with real loading/empty/error
states), but `customFolders`, `contacts` and `rules` are initialised from
`data/mockEmails.ts` and never persisted. `INITIAL_EMAILS` is imported but is no
longer used for the message list.

**Why deferred.** Custom folders and filter rules need `mail_folders` and
`mail_rules` tables plus a rules-evaluation step in delivery — a new feature
surface rather than a repair. The contacts list here should consume the new
contacts module (TASK-005) once the app is next touched.

---

## TASK-011 — PDF Viewer ships sample documents

* **Priority**: `MEDIUM`  **Status**: `OPEN (documented)`
* **Module**: `drive-osx-ui` → `apps/pdf-viewer/data/samplePdfs.ts`

**Problem.** The viewer lists built-in sample PDFs rather than the user's own
files. It does not use `platform.files`, so a PDF in Drive cannot be opened
through its own viewer.

**Why deferred.** Requires wiring the viewer into the file-open path and the
`EditorRegistry`; it is a feature integration, and the app is otherwise
functional standalone. No data is fabricated *about the user* — the samples are
clearly demo documents.

---

## TASK-012 — `GET /api/v1/meetings` does not exist

* **Priority**: `MEDIUM`  **Status**: `FIXED`
* **Module**: `drive-osx-api` → `modules/meetings`

**Problem.** The module exposes `/meetings/today` but no collection listing, so
`GET /meetings` returns 404. The current UI only calls `/today`, so nothing is
broken today, but the resource is incomplete and the 404 is indistinguishable
from a routing fault during debugging.

**Required changes.** Add a listing endpoint with a bounded window and explicit
pagination.

---

## TASK-013 — Trash size is a fabricated constant

* **Priority**: `MEDIUM`  **Status**: `FIXED`
* **Module**: `drive-osx-ui` → `apps/trash-bin`

**Problem.** `calculateTotalSizeKB()` returns `deletedFiles.length * 4.2` —
"4.2KB average mock size". The reclaimable-space figure shown to the user is
invented. Fixed together with TASK-006 by summing real file sizes.

---

## TASK-014 — Frontend has no automated tests at all

* **Priority**: `MEDIUM`  **Status**: `OPEN (documented)`
* **Module**: `drive-osx-ui`

**Problem.** No test runner is configured (`npm run lint` is `tsc --noEmit`).
148 source files, ~40k lines, zero tests. Prior sessions wrote throwaway
verification scripts that were never committed as a suite.

**Why deferred.** Introducing Vitest + Testing Library and a meaningful suite is
a project of its own; doing it badly (a handful of snapshot tests) would give
false assurance. Recorded with a concrete proposal in `docs/guides/testing.md`.

---

## TASK-015 — Bundle ships oversized chunks

* **Priority**: `LOW`  **Status**: `OPEN (documented)`

Three chunks exceed 500 kB minified (576 kB, 526 kB, 417 kB) plus `jspdf`
(391 kB) and `html2canvas` (202 kB). Route-level code splitting exists, but the
heavy editors pull large libraries eagerly. Non-blocking; noted with remedies in
`docs/architecture.md`.

---

## TASK-016 — No integration tests against a live database

* **Priority**: `LOW`  **Status**: `OPEN (documented)`

All backend tests are pure unit tests over extracted logic. SQL — where both
CRITICAL defects lived — is exercised only by the ad-hoc E2E shell script,
which is not in CI. Proposal in `docs/guides/testing.md`: a Compose-backed `vitest`
project with a disposable schema.

---

## TASK-017 — `passwordHash` field name is misleading

* **Priority**: `LOW`  **Status**: `OPEN (documented)`

`ApiService.register/login` take a field called `passwordHash` but send the
plaintext password, which the server bcrypts. The behaviour is correct and
standard; only the name is wrong, and it invites a future contributor to
"fix" it by hashing client-side, which would make the hash password-equivalent.
Renaming touches the auth screens; recorded rather than done mid-audit.

---

## TASK-018 — Access tokens live in `localStorage`

* **Priority**: `LOW`  **Status**: `OPEN (documented, accepted)`

JWT and refresh token are stored in `localStorage`, readable by any script on
the origin. No XSS sink was found in the audit (`dangerouslySetInnerHTML`: zero
occurrences; no `eval`/`innerHTML` on user data), and the pattern is standard
for SPAs. The stronger alternative — refresh token in an `HttpOnly` cookie —
requires CSRF protection and a cookie-aware CORS setup. Documented as an
accepted risk with the upgrade path in `docs/architecture/decisions/ADR-002`.

---

## TASK-019 — Documentation did not describe the shipped system

* **Priority**: `HIGH`  **Status**: `FIXED`

`README.md` and `docs/architecture.md` predate the messaging module, the
contacts/presence tables, the window-menu system and the app-preferences
model, and describe neither the personal-organization tenancy model nor the
mail gateway trust boundary. Addressed by the documentation set listed in
`docs/overview.md`.

---

## TASK-025 — Applications lay out against the viewport, not their window

* **Priority**: `MEDIUM`  **Status**: `OPEN (documented, one application fixed)`

Tailwind's `sm:`/`md:`/`lg:` prefixes respond to the browser viewport. In a
windowed desktop that is the wrong measurement: an application in a 400px
window on a 1400px screen still matches `md:`, renders a two-column layout, and
the columns overlap. This was reported against Contacts, where the email value
ran into the phone column and the action buttons were clipped.

`platform/layout/useContainerWidth.ts` was added to resolve it — a
`ResizeObserver` on the application's own root — and the Contacts detail pane
was converted, with 9 assertions over widths 320–2000px. The fix also exposed a
second-order bug: deriving the detail pane's width arithmetically from the
window width was wrong, because at 940px the sidebar reappears and takes 240px,
so *widening* the window squeezed the detail pane. Each pane measures itself.

**Still affected**, by count of viewport-prefixed classes:

| Application | Occurrences |
| ----------- | ----------- |
| `apps/osx-meet` | 88 |
| `apps/calendar` | 53 |
| `apps/mail-studio` | 13 |
| `apps/settings` | 10 |
| `apps/calculator` | 8 |
| `apps/text-editor`, `apps/clock` | 7 each |
| `apps/launcher` | 6 |
| `apps/pdf-viewer`, `apps/contacts` (its form modal only) | 4 each |
| `apps/terminal` | 2 |
| `apps/spreadsheet`, `apps/browser` | 1 each |

Thirteen applications, ~154 occurrences. Not every one is a visible defect —
a prefix on an element that never gets narrow is harmless — so this needs
triage per application rather than a blanket replacement. Messenger and Mail
Studio additionally carry their own inline `ResizeObserver` implementations
that predate the shared hook and should adopt it.

---

## TASK-026 — No ESLint, so the React hooks rules never run

* **Priority**: `MEDIUM`  **Status**: `OPEN`

There is no ESLint configuration anywhere in the repository. `npm run lint` in
`drive-osx-ui` is `tsc --noEmit` — a typecheck, not a lint.

This has already cost a production defect. A hook inserted after an early
`return null` in `GlobalContextMenu` changed the hook count between renders, so
right-clicking the desktop threw *Rendered more hooks than during the previous
render* and unmounted the entire application — a white screen with no way back
except a reload. `eslint-plugin-react-hooks` reports exactly that as an error.

**Proposal.** `eslint` + `@typescript-eslint` + `eslint-plugin-react-hooks` in
`drive-osx-ui`, with `rules-of-hooks` at `error` and `exhaustive-deps` at
`warn` — the latter because several effects deliberately key on a derived
signature rather than an object identity, each already carrying an inline
disable and a comment explaining why (see
`docs/features/shell-windows-and-dock.md` §4). Rename the existing script to
`typecheck` so `lint` means linting.

The cheapest item in this document by ratio of cost to defect class prevented.
