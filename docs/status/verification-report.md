# Final Project Verification Report

**Date** 2026-08-14
**Scope** Whole repository — `drive-osx-ui`, `drive-osx-api`, `drive-osx-mail`,
Compose stack, PostgreSQL schema, documentation.
**Method** Static review of every module and application, plus **live probing
of a running stack** (7 containers healthy) with HTTP workflow scripts.

---

## Verification honesty

This section governs how to read every claim below.

| Claim | What it means |
| ----- | ------------- |
| `VERIFIED (LIVE)` | Executed against the running stack; the response was observed. |
| `VERIFIED (TEST)` | Covered by a passing automated test. |
| `VERIFIED (BUILD)` | Typecheck and production build pass. |
| `REVIEWED` | Source read; the path was not executed. |
| `UNKNOWN` | Not verifiable here. Always says what would resolve it. |

**There is no browser automation in this environment.** No user interface was
rendered, clicked or observed. Every frontend change is verified at the layers
that *were* checked — TypeScript, the production build, and the API calls the
code makes — and nowhere in this report is a UI claimed to work on any stronger
basis. The offline layer and WebRTC media are marked `UNKNOWN` for this reason.

---

## Project summary

| Reviewed | Count |
| -------- | ----- |
| Services | 4 (UI, API, worker, SMTP gateway) + 3 datastores |
| Backend modules | 11 |
| Frontend applications | 18 |
| API endpoints | ~95 across 11 route files |
| Database migrations | 5 (one added) |
| Integrations traced | 9 categories, ~50 individual paths |
| Source files | 148 UI + 62 API + 7 mail |

---

## Issue summary

| Priority | Found | Fixed | Remaining |
| -------- | ----- | ----- | --------- |
| CRITICAL | 4 | **4** | 0 |
| HIGH | 5 | **5** | 0 |
| MEDIUM | 7 | 3 | 4 |
| LOW | 4 | 0 | 4 |
| **Total** | **20** | **12** | **8** |

All eight remaining items are pre-existing gaps, individually documented with
the reason for deferral in `docs/status/audit-and-plan.md`. None is
a regression, and none is critical or high.

### Critical issues fixed

**TASK-001 — Directory search could never find anyone.** Search joined
`memberships` on the caller's organization, but registration gives every user a
private `personal` organization. Live database: 6 users, 6 organizations, one
member each. Every search returned `{"users":[]}`. The whole chat feature was
unreachable through the product's own signup flow.

**TASK-002 — Conversations were invisible to the person who accepted.**
`listConversations` filtered on the caller's organization while the row carried
the *requester's*. Asymmetric by construction: one party saw a conversation, the
other saw an empty inbox. The same bug existed in `listChatRequests`, hiding
incoming requests from their recipients.

**TASK-003 — Unauthenticated mail injection with a forged sender.**
`POST /api/v1/mail/receive` required no credential, on the strength of a source
comment claiming network isolation the deployment does not provide. Demonstrated
live: a message from `ceo@yourbank.example` was delivered into a real user's
inbox, `201`, no token. A ready-made phishing channel.

**TASK-020 — Every accept and decline returned 404.** `listChatRequests`
selected `r.id` alongside `USER_COLUMNS`, which also selects `u.id`; the driver
keeps the last duplicate, so clients received the counterpart's *user* id as the
request id. **Found by running the fixed flow, not by reading it.**

### High issues fixed

* **TASK-004** — `chat.request_sent`, `chat.request_accepted` and
  `chat.message_sent` were published but had no subscriber, so no chat
  notification was ever produced.
* **TASK-005** — Contacts ran entirely on five invented people with stock
  photographs; the tables existed but had no endpoints. New `contacts` module,
  new client, app rewritten, mock file deleted.
* **TASK-006** — Trash was dual-sourced (`localStorage` vs the API) and every
  backend failure was swallowed into `console.warn`, so the UI reported success
  for writes the server rejected.
* **TASK-007** — The Messenger theme override was not reachable from
  Preferences, the documented path.
* **TASK-019** — Documentation did not describe the shipped system.

---

## Application status

Full detail in `docs/reference/applications.md`. Condensed:

| Application | Status | Verified how |
| ----------- | ------ | ------------ |
| File Explorer | `WORKING` | Live: CRUD, breadcrumbs, download, trash round-trip, **cross-tenant 404** |
| Messenger | `WORKING` | Live: 49 assertions across three tenants |
| Contacts | `WORKING` | Live: auto-creation, CRUD, isolation, presence |
| Trash | `WORKING` | Live: server-owned listing, real sizes |
| Mail Studio | `PARTIALLY_WORKING` | Messages live; folders/rules still local (TASK-010) |
| OSX Meet | `PARTIALLY_WORKING` | Records live; media needs two browsers |
| Text Editor | `WORKING` | Live: documents persist |
| Calendar | `PARTIALLY_WORKING` | **Nothing persists** (TASK-009) |
| Spreadsheet, Presentation, Paint | `PARTIALLY_WORKING` | Editors work; documents not stored in Drive |
| PDF Viewer | `PARTIALLY_WORKING` | Bundled samples, not Drive files (TASK-011) |
| Settings | `PARTIALLY_WORKING` | Local only, does not follow the account |
| Calculator, Clock, Terminal, Browser | `WORKING` | Local by nature |
| Offline layer | `UNKNOWN` | Needs a browser with network throttling |

---

## Integration status

| Integration | Status | Tests performed |
| ----------- | ------ | --------------- |
| Browser → API | `VERIFIED (LIVE)` | 87 HTTP assertions across two suites |
| API → PostgreSQL | `VERIFIED (LIVE)` | All CRUD paths; 5 migrations applied and checksum-verified |
| API → object storage | `VERIFIED (LIVE)` | Upload and download round-trip |
| API → Redis | `VERIFIED (LIVE)` | Readiness probe; rate-limit headers observed |
| API → worker (outbox) | `VERIFIED (LIVE)` | Chat notifications arrived ~2s after the action |
| SMTP gateway → API | `VERIFIED (LIVE)` | Real SMTP message delivered end to end **after** the auth change — no regression |
| Messenger → Contacts | `VERIFIED (LIVE)` | Acceptance creates both contact rows in one transaction |
| Shell → presence | `VERIFIED (LIVE)` | online → offline transitions observed by the peer |
| Browser ↔ WebSocket | `UNKNOWN` | Needs two concurrent browsers |

---

## Test results

| Check | Result |
| ----- | ------ |
| Env drift (`check-env.sh`) | ✅ all four pairs in sync |
| API typecheck | ✅ exit 0 |
| UI typecheck | ✅ exit 0 |
| Mail typecheck | ✅ exit 0 |
| UI production build | ✅ built in 6.25s |
| API unit tests | ✅ **61 passed** (was 37) |
| Mail unit tests | ✅ 7 passed |
| E2E: platform workflows | ✅ **38 passed, 0 failed** |
| E2E: messaging and contacts | ✅ **49 passed, 0 failed** |
| Container health | ✅ 7/7 healthy |
| Migrations | ✅ 5 applied, checksums verified |

**Tests added:** 24 unit cases (mail gateway policy 12, presence decay 12) and
87 HTTP assertions committed as a permanent suite under `tests/e2e/`.

### Security review

| Check | Result |
| ----- | ------ |
| Unauthenticated mail injection | ✅ now `401` (was `201` with a forged sender) |
| Unauthenticated `/mail/auth` | ✅ now `401` — credential oracle removed from the public surface |
| Wrong gateway token | ✅ `401`, constant-time comparison |
| Unauthenticated messaging / contacts / files | ✅ `401` |
| Cross-tenant file read and delete | ✅ `404`, existence not disclosed |
| Cross-user contact read and delete | ✅ `404` both directions |
| Non-participant conversation access | ✅ `403` on read and write |
| Directory enumeration | ✅ substring search does not cross tenants |
| SQL injection | ✅ every query parameterised; the one dynamic `UPDATE` builds from a column whitelist |
| XSS sinks | ✅ zero `dangerouslySetInnerHTML` in 148 UI files |
| Secrets in source | ✅ none; `.env.example` carries placeholders only |
| Rate limiting | ✅ per-bucket (credentials, refresh, mail, general) |
| Password storage | ✅ bcrypt; refresh and reset tokens stored as SHA-256 only |

### Performance review

Reviewed, no blocking issues. Noted and documented rather than pre-emptively
optimised: three bundle chunks exceed 500 kB (TASK-015); Messenger polls at 15s
and Contacts at 30s pending the realtime gateway; `listConversations` runs a
correlated unread-count subquery that will need attention at scale but is
correct now.

---

## What remains unresolved

Each is documented with its shape and the reason for deferral.

| Task | Item | Priority | Why deferred |
| ---- | ---- | -------- | ------------ |
| TASK-009 | Calendar does not persist anything | MEDIUM | A missing feature, not a defect: needs a new domain module, schema, invitations and reminders. Phase 5 work; building it inside an audit would be a large uncontrolled change. |
| TASK-010 | Mail folders, rules and contacts are local | MEDIUM | Needs `mail_folders`/`mail_rules` tables and rule evaluation during delivery — a new feature surface. |
| TASK-011 | PDF Viewer does not open Drive files | MEDIUM | Feature integration; the app works standalone and fabricates nothing about the user. |
| TASK-014 | No frontend tests at all | MEDIUM | A project of its own. A concrete proposal, ordered by value, is in `docs/guides/testing.md`. |
| TASK-015 | Oversized bundle chunks | LOW | Non-blocking; remedies documented. |
| TASK-016 | No integration tests against a live database | LOW | Proposal (disposable schema per run) in `docs/guides/testing.md`. |
| TASK-017 | `passwordHash` is a misleading field name | LOW | Behaviour is correct; renaming touches the auth screens. Documented **with a warning not to "fix" it by hashing client-side.** |
| TASK-018 | Tokens in `localStorage` | LOW | Accepted risk with no XSS sink present; upgrade path and revisit trigger in ADR-002. |

Also unresolved and honestly marked `UNKNOWN` rather than assumed working:
**offline behaviour** (a stated architectural requirement, CLAUDE.md §18–20) and
**WebRTC media**, including Meet's camera teardown. Both need a browser.

## Blockers requiring human action

None blocked this work. Two operational items need attention before deploying:

1. **Set `MAIL_GATEWAY_TOKEN` in production.** The API now refuses to boot
   without it, by design. Generate with `openssl rand -hex 32` and set the same
   value in `drive-osx-api/.env` and `drive-osx-mail/.env`. A development token
   was generated for the local stack; it is not a production secret.
2. **The E2E scripts leave fixtures in the shared development database.** Fine
   locally; TASK-016 is the fix before they run in CI.

---

## Documentation delivered

Existing documents were **updated** rather than duplicated: `docs/architecture.md`
gained the tenancy model, the mail trust boundary, accepted risks and a
per-application data-source table; `README.md` gained a documentation index and
corrected SMTP instructions. `CLAUDE.md` already serves as the requirements
document, so no competing `PROJECT_REQUIREMENTS.md` was created; likewise no
root `docs/architecture.md`, which would have contradicted `docs/architecture.md`.

New: `docs/overview.md`, `docs/reference/applications.md`, `docs/reference/integration-map.md`,
`docs/guides/testing.md`, `docs/guides/developer-guide.md`,
`docs/status/audit-and-plan.md`, three decision records,
`docs/features/messaging-and-contacts.md`, and `tests/e2e/README.md`.

---

## Overall project health

**Good, and materially better than at the start of the audit.**

The foundations are genuinely strong: clean module boundaries, centralised
server-side authorization, a transactional outbox, immutable checksum-verified
migrations, real multi-tenant isolation that holds under probing, and a platform
API that keeps applications off infrastructure details.

The weakness the audit exposed was not architecture but **verification**. Three
critical defects — all in SQL, all in the same feature — survived a typecheck, a
production build and 37 passing unit tests, because nothing executed a query
against a real database. The messaging feature was fully written, fully typed,
shipped, and completely unusable.

That gap is now partly closed: 87 HTTP assertions run against the live stack and
are committed. Frontend and offline behaviour remain unverified here, and the
report says so rather than implying otherwise.

**Recommended next, in order:** the frontend test setup (TASK-014), then the
live-database integration project (TASK-016), then Calendar persistence
(TASK-009) — the largest remaining gap between what an application appears to do
and what it actually does.
