# Application Inventory

Every application, module and service in the repository, with an **evidenced**
status. Compiled 2026-08-13 from source review plus live probing of a running
stack; the Code Editor entry was rewritten 2026-08-15 after that app was
rebuilt, and is the one entry additionally verified by live browser
automation (see the note above the frontend table).

## How to read the status

| Status | Means |
| ------ | ----- |
| `WORKING` | Exercised end to end against the live stack, or covered by passing tests. |
| `PARTIALLY_WORKING` | Core path works; a named part does not, or is local-only. |
| `BROKEN` | Does not do what it claims. |
| `NOT_IMPLEMENTED` | Referenced somewhere but absent. |
| `UNKNOWN` | Not verifiable in this environment — always says what is needed. |

**Verification honesty.** Most frontend entries below were **not** exercised in
a browser — they're verified at the layer that *was* checked (typecheck,
production build, and the API calls the code makes), and say so. **Code
Editor is the one exception:** it was driven live in a real browser via
Playwright (clicks, typing, screenshots) and is marked accordingly. Don't
infer the same basis for any other entry just because this one has it.

---

# Part 1 — Backend modules (`drive-osx-api`)

## identity

* **Purpose** Accounts, sessions, password recovery, mailbox credential checks.
* **Location** `src/modules/identity/`
* **Provides** `/register` `/login` `/auth/refresh` `/auth/logout` `/auth/change-password` `/profile` `/forgot-password` `/reset-password` `/mail/auth`
* **Database** `users`, `sessions`, `password_resets`, `organizations`, `memberships`
* **Auth** Public for credential endpoints; bearer elsewhere; `/mail/auth` requires the gateway token
* **Depends on** `organizations` (registration provisions a personal tenant), `events`
* **Implemented** Registration with personal-org provisioning, login, refresh rotation, logout, password change/reset, profile read/update
* **Status** `WORKING` — verified live: registration 201, duplicate 409, invalid 400, login 200, wrong password 401, profile with/without/bad token 200/401/401
* **Known issues** `passwordHash` is a misleading field name in the client (TASK-017, cosmetic)
* **Risk** Low

## organizations

* **Purpose** Tenants, memberships, teams, storage quota.
* **Location** `src/modules/organizations/`
* **Provides** `/organizations` (+ `/workspaces` legacy alias) with members, teams, switch, sharing policy, storage
* **Database** `organizations`, `memberships`, `teams`, `team_members`
* **Status** `WORKING` — verified live (list, storage summary); 7 unit tests
* **Note** Every registration creates a `personal` organization. Live DB: 6 users → 6 organizations, one member each. This shapes messaging and contacts (see `docs/architecture.md`).
* **Risk** Low

## files

* **Purpose** Drive metadata, contents, versions, trash, search.
* **Location** `src/modules/files/`
* **Provides** 20 routes across CRUD, upload, download, versions, star/pin, trash, restore, permanent delete
* **Database** `files`, `file_versions` + object storage
* **Depends on** `sharing` (effective role), `storage`, `events`
* **Status** `WORKING` — verified live: create folder/file, list children, breadcrumbs, content download, trash → list → restore; **cross-tenant reads and deletes correctly return 404**; 13 unit tests
* **Risk** Low

## sharing

* **Purpose** User, team, organization and link grants.
* **Location** `src/modules/sharing/`
* **Provides** `/shares/links/:token` (public), `/shares/shared-with-me`, per-file share management
* **Status** `PARTIALLY_WORKING` — code reviewed and mounted; unauthenticated link resolution and grant/revoke **not** exercised end to end
* **Known issues** No module tests; not covered by the E2E suites
* **Risk** Medium — authorization-critical and unverified. Add coverage next.

## mail

* **Purpose** Mailboxes and delivery.
* **Location** `src/modules/mail/`
* **Provides** `/mail/receive` (gateway), send, folders, star/pin/important, delete
* **Status** `WORKING` — verified live: inbox 200; a real SMTP message travelled gateway → API → mailbox after the security change; 6 unit tests
* **Fixed this audit** `/mail/receive` accepted unauthenticated deliveries with a forged sender (TASK-003)
* **Risk** Low

## meetings

* **Purpose** Meetings, participants, in-meeting chat, locking.
* **Location** `src/modules/meetings/`
* **Provides** list, today, get, start, join, leave, end, chat, participant state, lock
* **Status** `PARTIALLY_WORKING` — listing verified live (200, and filtered); join/start/end/chat **not** exercised
* **Known issues** No module tests; WebRTC signalling not verifiable without two browsers
* **Risk** Medium

## messaging

* **Purpose** Chat requests, direct conversations, messages.
* **Location** `src/modules/messaging/`
* **Provides** user search, request send/list/respond/cancel, conversation list, message list/send, mark read, delete
* **Database** `chat_requests`, `conversations`, `conversation_participants`, `direct_conversation_keys`, `messages`
* **Status** `WORKING` — verified live across **three independently registered users in three separate organizations**: 49 assertions covering search, requests, acceptance, two-way messaging, third-party refusal
* **Fixed this audit** TASK-001 (search found nobody), TASK-002 (recipient never saw the conversation), TASK-020 (`r.id` clobbered by `u.id`, so every accept/decline 404'd)
* **Risk** Low — was Critical

## contacts

* **Purpose** Personal address book and presence. **New in this audit.**
* **Location** `src/modules/contacts/`
* **Provides** contact CRUD, search, favourites, save-a-user, presence heartbeat/offline/lookup
* **Database** `contacts`, `user_presence`
* **Status** `WORKING` — verified live: auto-creation on chat acceptance for both sides, CRUD, cross-user isolation (404 both ways), idempotent save, presence online → offline transitions; 12 unit tests on presence decay
* **Risk** Low

## notifications

* **Purpose** Durable and realtime notifications.
* **Location** `src/modules/notifications/`
* **Status** `WORKING` — verified live, including notifications produced by chat events
* **Note** `user_id`-scoped, which is stricter than tenant scoping
* **Risk** Low

## search

* **Purpose** Cross-domain search over files and mail.
* **Location** `src/modules/search/`
* **Status** `PARTIALLY_WORKING` — returns 200 live; ranking and coverage not assessed
* **Known issues** No tests; PostgreSQL full-text only (by design, CLAUDE.md §13)
* **Risk** Low

## audit

* **Purpose** Append-only audit trail.
* **Status** `WORKING` — verified live (200); entries written in the same transaction as the change
* **Risk** Low

## workers

* **Purpose** Domain-event handlers and queued jobs.
* **Location** `src/workers/`
* **Status** `WORKING` — verified live: chat notifications arrived within ~2s of the triggering action
* **Fixed this audit** Three declared chat events had no subscriber (TASK-004)
* **Known limitation** `file.thumbnail` copies the original rather than downscaling — no image library is a dependency. Documented, not hidden.
* **Risk** Low

---

# Part 2 — Frontend applications (`drive-osx-ui`)

All entries below share: React 19 + TypeScript + Tailwind v4, Zustand for shell
state. Unless otherwise noted, `UNVERIFIED (UI rendering)` — typecheck and
production build pass, but no browser exercised the interface. Code Editor is
the noted exception.

## File Explorer

* **Location** `src/apps/file-explorer/` (2,295 lines)
* **Uses** `platform.files` → `/files`, `/shares`
* **Implemented** Browse, upload, download, rename, move, trash, restore, share, properties, preview, open-with, multi-select, context menus
* **Status** `WORKING` (data path verified via API; UI unverified)
* **Risk** Low

## Messenger

* **Location** `src/apps/messages/`
* **Uses** `MessagingService` → `/messaging`; `ContactsService` → `/contacts`
* **Implemented** Real conversations, directory search, 280-character chat requests, accept/decline/withdraw, presence dots, per-app theme, empty/loading/error states, save-to-contacts
* **Status** `WORKING` (backend verified live; UI unverified)
* **Fixed this audit** Seeded conversations removed; the save-to-contacts button now writes instead of only claiming to
* **Risk** Low

## Contacts

* **Location** `src/apps/contacts/`
* **Uses** `ContactsService` → `/contacts`
* **Implemented** Real contacts with presence, create/edit/delete, favourites, search, labels, groups, vCard/CSV import-export, business card, QR
* **Status** `WORKING` (backend verified live; UI unverified)
* **Fixed this audit** `mockContacts.ts` (5 invented people with stock photos) deleted; writes now persist and failures are surfaced; migration `0005` added storage for fields the form already collected but discarded
* **Risk** Low

## Trash

* **Location** `src/apps/trash-bin/`
* **Status** `WORKING` (server is now the source of truth; UI unverified)
* **Fixed this audit** Read from the API instead of `localStorage` alone; failed restores roll back and tell the user; reclaimable space uses real byte counts instead of `count × 4.2 KB`
* **Risk** Low

## Mail Studio

* **Location** `src/apps/mail-studio/` (1,691 lines)
* **Status** `PARTIALLY_WORKING`
* **Working** Messages from `/mail` with proper loading, empty and error states; compose and send
* **Not working** Custom folders, contacts list and filter rules are local placeholders from `data/mockEmails.ts` and are never persisted (TASK-010)
* **Risk** Medium — the app looks fully featured but three sidebars are inert

## OSX Meet

* **Location** `src/apps/osx-meet/` (3,066 lines)
* **Status** `PARTIALLY_WORKING` — meeting records are real; peer-to-peer media needs two browsers to verify
* **Known issues** No automated coverage of camera teardown, which has regressed before
* **Risk** Medium

## Code Editor

* **Location** `src/apps/code-editor/` (3,206 lines) — replaced the old Text Editor app entirely, not a rename
* **Uses** `platform.files` → `/files` (open, save, create/rename/delete/move, and a BFS workspace walk for Search); Monaco Editor, bundled locally with no CDN fetch (offline-first per `CLAUDE.md` §18); Prettier (`prettier/standalone` + real parser plugins) and ESLint (`eslint-linter-browserify`), both running client-side with no server round-trip
* **Implemented** Open Folder with a real lazy-loaded tree; full Explorer create/rename/delete/move with drag-and-drop (same drag protocol as File Explorer, so files drag between the two); global workspace Search with case/whole-word/regex and Find & Replace, skipping files with unsaved local edits; an Activity Bar (Explorer, Search) plus a Settings entry point that opens a full VS Code-style Settings page — searchable, categorized (Commonly Used / Text Editor / Workbench / Extensions), every control bound to a real persisted preference; toggleable breadcrumbs; a status bar whose cursor position and problem counts come from Monaco's own marker service, not placeholders; real Prettier formatting (Format Document, Shift+Alt+F, and an optional Format On Save) for JS, TS, JSON, CSS, LESS, SCSS, HTML, Markdown, YAML and GraphQL; real ESLint linting of JavaScript/JSX as you type, using a curated core rule set
* **Explicitly not implemented** A plugin marketplace or extension host. The Extensions page lists Prettier and ESLint as genuinely installed, and GitLens, Python, and Docker as "Recommended" — each with an honest, specific explanation of the backend it would need (Git integration, a language server, a container runtime) that doesn't exist on this platform. There is no Install button that does nothing.
* **Status** `WORKING` — the one frontend entry in this document verified by **live browser automation** (Playwright), across this and an earlier pass: folder open, folder/nested-folder rename (Explorer and Code Editor stay in sync), drag-and-drop, workspace search and replace, the breadcrumb toggle, and — most recently — typing malformed JavaScript, saving as `.js`, watching real ESLint warnings appear, and Shift+Alt+F producing genuine Prettier-formatted output, each step screenshotted
* **Known issue** TypeScript files aren't linted — ESLint's default parser (espree) can't read TypeScript syntax, so this is scoped to JS/JSX rather than silently producing wrong results on `.ts`/`.tsx`
* **Risk** Low

## Calendar

* **Location** `src/apps/calendar/` (600 lines + 8 components)
* **Status** `PARTIALLY_WORKING` — full month/week/day/year/agenda UI, recurrence, reminders
* **Not working** **Nothing is persisted.** No `calendar` module, no `calendar_events` table. Events are per-browser and lost (TASK-009)
* **Risk** High for user expectation — it looks like a real calendar and silently loses data

## Spreadsheet / Presentation / Paint Studio

* **Status** `PARTIALLY_WORKING` — rich, working editors (formulas, charts, diagrams, layers) whose documents are **not stored in Drive**
* **Risk** Medium — same expectation gap as Calendar

## PDF Viewer

* **Status** `PARTIALLY_WORKING` — renders correctly, but lists bundled sample documents rather than the user's files (TASK-011)
* **Risk** Low

## Settings

* **Status** `PARTIALLY_WORKING` — preferences persist to `localStorage`, not to the user profile, so they do not follow the account to another device
* **Risk** Low

## Calculator, Clock, Terminal, Browser, Launcher

* **Status** `WORKING` — local-only by nature; no server state is appropriate
* **Risk** Low

---

# Part 3 — Shell and platform layer

| Component | Location | Status |
| --------- | -------- | ------ |
| Window manager | `shell/window-manager/` | `WORKING` — shared chrome, one status bar, portal-rendered menus. Drag and resize keep their state in refs and commit to the store **once on release**; a 120-event drag produces exactly one store write. 44 assertions cover the gesture arithmetic, clamping at every edge and dock size, and the commit count. **The motion itself is unverified** — no browser automation. See [Windows and the dock](../features/shell-windows-and-dock.md). |
| Dock | `shell/taskbar/Dock.tsx`, `dockZone.ts` | `WORKING` — hides whenever a window covers its strip (maximized, dropped over it, or dragged into it mid-gesture), reveals while the cursor is at the bottom edge. 51 assertions cover the full visibility truth table and the live-gesture store. **Not visually reviewed.** |
| Application menus | `platform/menus/` | `WORKING` — dynamic per app, submenus escape clipping via portals |
| Preferences | `shell/preferences/` | `WORKING` — Appearance, Windows, **Applications** (theme for every installed app), System |
| Theme resolution | `platform/theme/appTheme.ts` | `PARTIALLY_WORKING` — the pure resolution table (four choices × global × OS, plus the legacy-preference migration) was checked over 33 cases and typechecks and builds clean. **The rendering itself is unverified**: no browser automation exists here. |
| Theme catalogue | `platform/theme/themes.ts` | `PARTIALLY_WORKING` — 14 themes in 3 families, default **Nova**. 180 assertions confirm ids are unique, every theme names a wallpaper that exists, every chrome set is complete, and no theme falls through to light. **Colours were not viewed**; the class strings are unrendered. |
| Wallpaper catalogue | `platform/theme/wallpapers.ts` | `PARTIALLY_WORKING` — 21 wallpapers (6 light, 15 dark) plus a custom URL. Verified renderable and grouped. The two Nova wallpapers were **rasterised and visually reviewed** during the change — the only UI in this repo checked that way; everything else remains unverified by eye. |
| Shell surfaces | `platform/theme/useShellTheme.ts` | `PARTIALLY_WORKING` — dock, top bar, popups, menus, context menu, notification centre and application menu all read one token set. 274 assertions confirm every theme yields a complete surface set and that the glass recipe holds: gradient fill at 44–62%, blur plus saturation, soft border, inset highlight, restrained shadow, cards more solid than the panel, and no scrim above 60%. Generated CSS confirmed present in the production bundle. **Not visually reviewed.** |
| System store | `shell/state/systemStore.tsx` | `WORKING` — file/trash failures now roll back and notify |
| Platform API | `platform/index.ts` | `WORKING` — files, windows, notifications, clipboard, search, auth, orgs, mail, meetings, **contacts**, **presence**, network, sync |
| Offline layer | `platform/offline/` | `UNKNOWN` — IndexedDB, service worker and sync engine exist; **no offline scenario was exercised**. Needs a browser with network throttling. |
| Auth screens | `shell/auth/` | `WORKING` (API paths verified; UI unverified) |

---

# Part 4 — Other services

## drive-osx-mail

* **Purpose** SMTP ingress. Holds no state; authenticates and relays to the API.
* **Status** `WORKING` — verified live: a real SMTP message was accepted and delivered after the gateway-token change
* **Fixed this audit** Now presents `X-Mail-Gateway-Token` on every API call
* **Risk** Low

## Infrastructure

| Component | Status | Evidence |
| --------- | ------ | -------- |
| PostgreSQL 17 | `WORKING` | Readiness probe passes; 5 migrations applied and checksum-verified |
| Redis | `WORKING` | Readiness probe passes; rate limiting and cache observed |
| MinIO | `WORKING` | Container healthy; file upload and download round-tripped |
| Docker Compose | `WORKING` | 7 containers healthy; dev/production split via `COMPOSE_FILE` |
