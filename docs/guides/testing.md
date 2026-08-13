# Test Plan

## Where coverage stands

| Layer | Suite | Count | State |
| ----- | ----- | ----- | ----- |
| Backend unit | `drive-osx-api` vitest | 61 | Passing |
| Backend E2E (HTTP) | `tests/e2e/*.sh` | 103 assertions | Passing |
| SMTP gateway unit | `drive-osx-mail` vitest | address parsing | Passing |
| Frontend unit | — | 0 | **Absent** (TASK-014) |
| Frontend E2E | — | 0 | **Absent** |
| Backend integration (live DB) | — | 0 | **Absent** (TASK-016) |

## The lesson this plan is built on

The two defects that made messaging completely unusable, and the third that
broke every accept/decline, were **all invisible** to typecheck, production
build and 37 passing unit tests. Each lived in SQL:

* a `JOIN` on the wrong scope (`TASK-001`),
* a `WHERE` on the wrong column (`TASK-002`),
* a duplicated output column name silently overwriting an id (`TASK-020`).

TypeScript cannot see inside a SQL string. **A change to a query is not tested
until a real database has answered it.** That is why the E2E probes exist and
why they run against a live stack rather than a mock.

---

## 1. Unit tests

**Where they belong:** pure logic that can be extracted from I/O — permission
algebra, validation, formatting, decay rules, parsers.

Running: `cd drive-osx-api && npm test`

Current subjects:

| File | Covers |
| ---- | ------ |
| `platform/authorization/roles.test.ts` | Role hierarchy, strongest-grant-wins |
| `platform/authentication/mail-gateway.test.ts` | Gateway token policy, constant-time compare, dev vs production |
| `modules/contacts/contacts.service.test.ts` | Presence decay, clock skew, missing rows |
| `modules/files/files.service.test.ts` | Path rules, MIME classification, quota |
| `modules/organizations/organizations.service.test.ts` | Slug reservation, membership rules |
| `modules/mail/mail.service.test.ts` | Address parsing, folder routing |

**Design rule that makes this work:** when a rule matters, extract it as a pure
function and export it. `effectivePresence` is exported precisely so the "is
this user online" decision can be tested without a database or a clock.

## 2. HTTP end-to-end probes

**Where they belong:** anything crossing a process boundary — SQL, auth,
tenancy, multi-user flows, service-to-service calls.

```sh
docker compose up -d
./tests/e2e/platform-workflows.sh
./tests/e2e/messaging-and-contacts.sh
./tests/e2e/realtime-messaging.sh
```

All three exit non-zero on any failure, so they can gate a pipeline.

`platform-workflows.sh` — 29 assertions: registration and validation, login,
token handling, organizations, file lifecycle, **cross-tenant isolation**
(404 not 403), trash round-trip, search, notifications, audit, mail.

`messaging-and-contacts.sh` — 49 assertions: three users in three separate
personal organizations, exact-handle discovery across tenants, substring search
*not* enumerating other tenants, request → accept → two-way messaging,
third-party refusal, contact auto-creation on both sides, contact CRUD and
isolation, idempotent save, presence transitions, chat notifications.

`realtime-messaging.sh` — 16 assertions driving a **real WebSocket** opened
through the UI's own origin, so it covers the dev-server proxy as well as the
gateway: handshake, delivery with nothing polling, exactly-once, the payload
fields the client routes on, offline retrieval, and that a sender is never
notified of their own message.

Credential endpoints are rate limited (20 per 5 minutes). Running the suites
repeatedly in quick succession exhausts that bucket, and the sign-in failures
that follow are the limiter working — not a regression.

**When adding a test here:** a `chk` line is label, expected, actual. Prefer
adding to these over writing a new script.

## 3. Regression policy

Every defect fixed in the audit has a test pinning it:

| Task | Defect | Pinned by |
| ---- | ------ | --------- |
| TASK-001 | Directory search found nobody | `messaging-and-contacts.sh` — exact match across orgs, substring not enumerating |
| TASK-002 | Recipient never saw the conversation | Same — "B sees 1 conversation (was 0 before fix)" |
| TASK-003 | Unauthenticated mail injection | `mail-gateway.test.ts` (12 cases) + live 401/201/401 probe |
| TASK-004 | Chat events had no subscribers | `messaging-and-contacts.sh` — three notification assertions |
| TASK-005 | Contacts were fabricated | `messaging-and-contacts.sh` — a fresh user has **zero** contacts |
| TASK-012 | No meetings collection endpoint | `messaging-and-contacts.sh` |
| TASK-020 | Request id clobbered by user id | `messaging-and-contacts.sh` — accept returns 200 |
| TASK-021 | Open thread never refetched | `realtime-messaging.sh` — push arrives with nothing polling |
| TASK-022 | Nothing consumed the realtime gateway | `realtime-messaging.sh` — handshake + delivery |
| TASK-023 | Vite did not proxy `/ws` | `realtime-messaging.sh` — socket opened via the UI origin |

**The rule:** a bug in a flow crossing a process boundary gets an E2E
assertion, not only a unit test. The unit tests would have passed throughout
all three CRITICAL defects.

### Shell defects have no home yet

Three shell-layer defects were fixed after the audit. Each has assertions
written against it, but they live in a scratchpad rather than the repository,
because `drive-osx-ui` still has no test runner (TASK-014).

| Defect | What it broke | Checked by |
| ------ | ------------- | ---------- |
| A hook placed after an early `return null` in `GlobalContextMenu` | Right-clicking the desktop unmounted the entire application — white screen | A sweep of all 22 components using theme hooks; nothing automated |
| `onMove` called from `pointermove`, re-rendering the desktop per frame | Window dragging stuttered, then threw *Maximum update depth exceeded* | 44 assertions on the gesture state machine |
| The dock could not see a window's position mid-drag | A window dragged over the dock did not hide it until release | 51 assertions on the visibility truth table |

The first has no automated check at all and would be caught for free by
`eslint-plugin-react-hooks` — **there is no ESLint configuration in this
repository**, which is why the rule never ran. `npm run lint` in `drive-osx-ui`
is `tsc --noEmit`: a typecheck, not a lint. Adding one is TASK-026 and the
cheapest available win in this table.

---

## 4. Gaps, with concrete proposals

### TASK-014 — no frontend tests

**Proposal.** Vitest + React Testing Library + jsdom in `drive-osx-ui`.

Worth testing, in order of value:

1. **Pure logic already extracted** — the cheapest real coverage available
   today: `platform/theme/appTheme.ts` (four-choice resolution, the legacy
   preference migration, and that Retro Terminal survives the default),
   `apps/contacts/adapter.ts` (name splitting, presence wording, stable avatar
   colour), `apps/spreadsheet/utils/formula.ts` and `utils/grid.ts`,
   `apps/paint-studio/utils/diagram.ts`.

   `appTheme.ts` is the first candidate: it is a truth table over three inputs
   with no I/O, so it is fully testable the moment a runner exists. Its 33-case
   table was checked by hand during the change; without a runner in the repo
   that check is not repeatable, which is the whole point of this task.

   Second is **catalogue integrity** for `themes.ts` and `wallpapers.ts` — that
   every theme names a wallpaper that exists, ids are unique, every chrome set
   is complete, and no theme reduces to the wrong family. That is 140 cheap
   assertions guarding a class of bug that typecheck cannot see: a theme may
   reference a wallpaper id that was renamed, and the only symptom is a blank
   desktop when someone selects it.

   Third is **`shell/taskbar/dockZone.ts`** — pure geometry plus a small store,
   both directly importable. The dock visibility truth table in
   [Windows and the dock](../features/shell-windows-and-dock.md) §3 is already
   written as 51 assertions; they would move into the repository unchanged.

   The window gesture state machine in `AppWindow.tsx` is the one piece that
   *cannot* move as-is: it is entangled with the component. Extracting the
   clamp-and-commit arithmetic into a pure module would make 44 existing
   assertions repeatable, and is worth doing when the runner lands.
2. **Service clients** against a mocked `http` — that a 401 triggers refresh,
   that offline is classified as offline.
3. **State transitions** in `systemStore` — especially that a failed API call
   rolls the store back, which is the TASK-006 defect.
4. **Component states** — that Contacts and Messenger render loading, empty,
   error and populated states from the same component.

Explicitly *not* proposed: snapshot tests of large components. They would pass
while the app was broken, which is the failure mode being corrected.

### TASK-016 — no integration tests against a live database

**Proposal.** A second vitest project that runs each test file against a
disposable schema:

```
beforeAll:  CREATE SCHEMA test_<random>; run migrations; set search_path
afterAll:   DROP SCHEMA test_<random> CASCADE
```

This would catch exactly the class of defect that got through: SQL scoping,
column collisions, constraint behaviour, transaction boundaries. Until it
exists, the E2E scripts are the only cover for that class — **and they leave
their fixtures behind in the shared development database**, which is the main
reason to build this.

### Realtime and offline

Both are `UNKNOWN` in `docs/reference/applications.md` and cannot be resolved without
a browser:

* **Realtime** needs two concurrent clients — Playwright with two contexts.
* **Offline** needs network throttling plus service-worker control: go offline,
  act, come back, assert the queue drained and no work was lost.

Offline behaviour is a stated architectural requirement (CLAUDE.md §18–20), so
this is the most valuable browser-level suite to build first.

### Media and camera teardown

Meet's camera-release-on-close has regressed before. It needs a browser with a
fake media device (`--use-fake-device-for-media-stream`) asserting every track
is stopped after the window closes.

---

## 5. Before you commit

```sh
./scripts/check-env.sh                     # env drift, both directions
cd drive-osx-api && npx tsc --noEmit && npm test
cd drive-osx-ui  && npx tsc --noEmit && npx vite build
./tests/e2e/platform-workflows.sh          # needs the stack running
./tests/e2e/messaging-and-contacts.sh
./tests/e2e/realtime-messaging.sh
```

If you touched messaging, contacts, presence or authorization scoping, the E2E
scripts are not optional. If you touched the realtime gateway or a **proxy
configuration** (`vite.config.ts`, the UI image's nginx config), run
`realtime-messaging.sh` specifically — it is the only check that opens a socket
the way a browser does.
