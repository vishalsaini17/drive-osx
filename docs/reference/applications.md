# Application Inventory

Every application, module and service in the repository, with an **evidenced**
status. Compiled 2026-08-13 from source review plus live probing of a running
stack; the Code Editor entry was rewritten 2026-08-15 after that app was
rebuilt, and is the one entry additionally verified by live browser
automation (see the note above the frontend table). The Messenger, File
Explorer, Code Editor and shell-Preferences entries were amended 2026-08-24
from source review (not live probing) to reflect group chat, attachments,
message actions, file-manager, and per-app-settings work landed since the
original audit — those additions carry the same "UI unverified" caveat as
the rest of Part 2 unless stated otherwise. The PDF Viewer entry was rewritten
2026-09-09 after that app was rebuilt from a sample-data mock into a real
pdf.js-backed viewer (TASK-011), and is the second entry additionally verified
by live browser automation — see its own note below. The Paint Studio entry
was rewritten 2026-09-10 after a tool-by-tool audit and fix pass (fill,
raster/vector shape separation, resize handles, cursors, a duplication bug,
flowchart drag, and real `FileService`-backed saving) and is the third entry
additionally verified by live browser automation.

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
* **Routing** `/folder` opens the root; `/folder/:folderId` opens that folder directly (`folderId` is the backend's real folder id, e.g. `/folder/abc123` — never a name). Reload or a direct link lands back in the same folder; browser Back/Forward walks through folders visited, each a separate history entry (`src/App.tsx`'s `DesktopLayout` sync effect + `AppRegistry.getPathForApp`/`getAppIdForPath`/`getFolderIdFromPath`, backed by `fileManagerCurrentFolderId` in `systemStore`). An id that doesn't resolve to an accessible folder shows an inline "Folder not found" state instead of silently falling back to root.
* **Sharing** The Share dialog (`components/ShareModal.tsx`) is fully backed by the `/shares` API — "People with access" is loaded live, adding someone autocompletes against the sharer's contacts (`FileService.searchEligibleUsers`, debounced ~300ms), removing calls `revokeShare`, and the public-link tab creates/rotates a real token (opened at `/s/:token`, `shell/auth/ShareLinkPage.tsx`). A shared file/folder shows a small people-icon badge in the grid and list views (`item.isShared`), and "Shared with me" in the sidebar is a real `FileService.listSharedWithMe()` view rather than fixture data. Toolbar/context-menu actions are additionally hidden per `item.effectiveRole` as a UX hint — the `/files` and `/shares` APIs enforce the real rule server-side regardless.
* **Implemented** Browse, upload, download (single file via a signed URL; multiple items or any folder via a server-streamed zip, `POST /files/download-zip`; a selection over 1GiB splits deterministically into several ≤1GiB zip parts, downloaded one after another), rename, move, duplicate (`POST /files/:fileId/duplicate` — a real server-side copy via `objectStorage.copy`, recursive for folders, capped at 2,000 descendants), trash, restore, share, properties, preview, open-with, multi-select, context menus
* **Implemented, added 2026-08-22** File-type-aware icons and "Open With" filtering, both reading one shared `getFileKind()` map (`utils/fileType.ts`) so the two can no longer drift independently; "Shared with me" defaults to grouping by owner on entry (still user-changeable for that visit).
* **Fixed 2026-09-09** `handleItemDoubleClick` already resolved `.pdf` → `pdf-viewer` via `EditorRegistry`, but `handleOpenWithApp` had no branch for that app id, so double-clicking a PDF was a silent no-op — see PDF Viewer, below (TASK-011). Also added a `pdf-viewer` entry (`kinds: ['pdf']`) to `OpenWithModal.tsx`'s own separate app list, which previously had none — a PDF's "Open With…" menu offered no relevant app at all. `paint`, `spreadsheet`, `presentation` and `browser` have the same `handleOpenWithApp` gap and were **not** touched by this fix — only `pdf-viewer` was in scope.
* **Status** `WORKING` (data path verified via API; UI unverified)
* **Risk** Low

## Messenger

* **Location** `src/apps/messages/`
* **Uses** `MessagingService` → `/messaging`; `ContactsService` → `/contacts`
* **Implemented** Real conversations, directory search, 280-character chat requests, accept/decline/withdraw, presence dots, per-app theme, empty/loading/error states, save-to-contacts
* **Implemented, added 2026-08-24** Group conversations (create from existing contacts only, rename/describe/avatar/add-member as admin, leave, report, favourite); attachments — documents, images, video (25MB), plus a live camera-capture path and a "from Drive" picker; voice notes; an emoji picker (its "Stickers" tab sends large emoji as messages — there is no real sticker/GIF backend); a contact-details panel and a group-details panel, both backed by a shared Media/Docs/Links section; per-message actions — react, reply, copy (client-side only), forward to one or more conversations, pin/unpin, delete for me or for everyone; block/unblock and clear/delete chat, all from the details panel. "Call" buttons create and start a real Meeting via the separate Meetings app and post the code into the chat — Messenger itself has no calling stack. See [Messaging and contacts](../features/messaging-and-contacts.md) for the full API/permission/limitation list.
* **In progress, uncommitted** Editing a sent text message (`PATCH /messaging/messages/:id`) — do not treat as shipped.
* **Status** `WORKING` (backend verified live; UI unverified). The 2026-08-24 additions are **not** covered by either messaging E2E suite yet.
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

* **Display name** "Editor" since 2026-08-22 (display-only rename; the app id is still `editor`, so this doesn't affect routing or preferences keys)
* **Location** `src/apps/code-editor/` (3,206 lines) — replaced the old Text Editor app entirely, not a rename
* **Uses** `platform.files` → `/files` (open, save, create/rename/delete/move, and a BFS workspace walk for Search); Monaco Editor, bundled locally with no CDN fetch (offline-first per `CLAUDE.md` §18); Prettier (`prettier/standalone` + real parser plugins) and ESLint (`eslint-linter-browserify`), both running client-side with no server round-trip
* **Implemented** Open Folder with a real lazy-loaded tree; full Explorer create/rename/delete/move with drag-and-drop (same drag protocol as File Explorer, so files drag between the two); global workspace Search with case/whole-word/regex and Find & Replace, skipping files with unsaved local edits; an Activity Bar (Explorer, Search) plus a Settings entry point that opens a full VS Code-style Settings page — searchable, categorized (Commonly Used / Text Editor / Workbench / Extensions), every control bound to a real persisted preference; toggleable breadcrumbs; a status bar whose cursor position and problem counts come from Monaco's own marker service, not placeholders; real Prettier formatting (Format Document, Shift+Alt+F, and an optional Format On Save) for JS, TS, JSON, CSS, LESS, SCSS, HTML, Markdown, YAML and GraphQL; real ESLint linting of JavaScript/JSX as you type, using a curated core rule set
* **Explicitly not implemented** A plugin marketplace or extension host. The Extensions page lists Prettier and ESLint as genuinely installed, and GitLens, Python, and Docker as "Recommended" — each with an honest, specific explanation of the backend it would need (Git integration, a language server, a container runtime) that doesn't exist on this platform. There is no Install button that does nothing.
* **Implemented, added 2026-08-22** Multi-window support: "Open With…" from File Explorer always opens a new editor window (`forceNewWindow`), a plain double-click reuses/focuses the one primary window, and the dock collapses multiple windows of the app into a single icon. A window opened with no preopened file/folder now shows an empty/welcome state instead of manufacturing a throwaway tab. Minimap visibility is a real toggle (`minimapEnabled` preference, default on). Workspace Search is now only rendered when a folder is actually open — it used to silently fall back to searching the entire Drive from root when nothing was open; now an explicit "You have not yet opened a folder" state is shown instead.
* **Not covered by the shared per-app Preferences modal** (`AppSettingsModal` — see the Preferences row in Part 3 below) — Editor keeps its own hand-built Settings page instead, reachable from its Activity Bar.
* **Status** `WORKING` — the one frontend entry in this document verified by **live browser automation** (Playwright), across this and an earlier pass: folder open, folder/nested-folder rename (Explorer and Code Editor stay in sync), drag-and-drop, workspace search and replace, the breadcrumb toggle, and — most recently — typing malformed JavaScript, saving as `.js`, watching real ESLint warnings appear, and Shift+Alt+F producing genuine Prettier-formatted output, each step screenshotted
* **Known issue** TypeScript files aren't linted — ESLint's default parser (espree) can't read TypeScript syntax, so this is scoped to JS/JSX rather than silently producing wrong results on `.ts`/`.tsx`
* **Risk** Low

## Calendar

* **Location** `src/apps/calendar/` (600 lines + 8 components)
* **Status** `PARTIALLY_WORKING` — full month/week/day/year/agenda UI, recurrence, reminders
* **Not working** **Nothing is persisted.** No `calendar` module, no `calendar_events` table. Events are per-browser and lost (TASK-009)
* **Risk** High for user expectation — it looks like a real calendar and silently loses data

## Spreadsheet / Presentation

* **Status** `PARTIALLY_WORKING` — rich, working editors (formulas, charts) whose documents are **not stored in Drive**
* **Risk** Medium — same expectation gap as Calendar

## Paint Studio

* **Location** `src/apps/paint-studio/` (raster drawing engine in `index.tsx`; vector flowchart layer in `components/DiagramLayer.tsx` + `utils/diagram.ts`)
* **Audited and fixed 2026-09-10.** A full pass over every tool after user reports that several were broken or confusing:
  * **Fill tool filled the background instead of the shape it was aimed at.** Root cause: the Shapes tool was implemented as a thin wrapper around the vector Flowchart system, so a "shape" was an SVG node, not pixels on the canvas — flood-fill (which only ever operates on the raster bitmap) had nothing of the shape to find. Fixed by making Shapes genuinely raster: `drawRasterShape()` strokes the shape's outline directly onto the canvas via `Path2D`, with no fill, so the user's own Fill tool now colours the actual enclosed pixels correctly. Shapes and Flowchart are now two fully separate systems — Shapes no longer touches `DiagramLayer`/`diagram.ts` at all, and Flowchart nodes (placed from the Flowchart panel) are unaffected raster-wise.
  * **Resize-after-draw.** Finishing a shape now leaves it in an adjustable state — drag handles for width/height/corner-radius (reusing the existing vector-node `RESIZE_HANDLES`/`applyResize` machinery against the raster shape's rect) before it's committed to the bitmap; clicking elsewhere or switching tools commits it.
  * **Shape palette expanded** from 6 to 15 options (rectangle, rounded-rect, ellipse, diamond, triangle, right-triangle, pentagon, hexagon, octagon, star, heart, speech-bubble, cross, line, arrow) — deliberately excludes the four shapes (parallelogram, capsule, cylinder, document) reserved for the separate Flowchart panel, so the two tools' palettes don't imply overlap that doesn't exist.
  * **Per-tool cursors.** Each tool now shows a custom cursor built from that tool's own sidebar icon (exact lucide-react path data, e.g. the pen-tool cursor is a pen, the eraser is an eraser) instead of a generic crosshair; the Shapes-tool cursor is generated dynamically from `nodePath()` so it traces the actual outline of whichever shape is currently selected.
  * **Shape-duplication bug.** Clicking away from a shape mid-adjustment (to dismiss the resize handles) fell through into the active tool's own pointer-down handler on the same click, drawing a fresh copy of the shape on top of the one just committed. Fixed with an early return once the pending adjustment is committed.
  * **Flowchart nodes were unselectable/undraggable** for every non-rectangular shape (Decision/diamond, Preparation/hexagon, Data/parallelogram, Note/speech-bubble). Root cause: precise hit-testing uses the browser's `SVGGeometryElement.isPointInFill()` against a reusable `<path>` element that was never attached to the DOM — this browser silently returns `false` for a detached element regardless of valid geometry, so clicks (even dead-center) never registered, and a drag can't start without a successful hit-test. Fixed by attaching that element (zero-size, invisible, non-interactive) to `document.body` once on first use. Verified against all 8 `FLOWCHART_PRESETS`.
  * **Save to Drive now really persists.** Previously "Save to Drive" only pushed a fake entry into local React state (`setFiles`), never reaching the server. It now calls `FileService.createFile`/`updateFile` against the real `/files` API, with a loading state and a user-facing error message on failure — the same pattern `code-editor` uses. **Scope of what's saved:** a flattened PNG export of the canvas (`composite().toDataURL('image/png')`), not the editable object graph — there is no load-an-existing-file-back-into-Paint-Studio path (see TASK-030), so a saved file opens elsewhere as a static image, not as a resumable Paint Studio document. It genuinely writes to Drive; it just isn't round-trippable yet.
* **Status** `PARTIALLY_WORKING` — drawing/shape/flowchart tools now verified correct (Playwright regression sweep: raster fill-inside-shape, resize-after-draw, no-copy-on-click-away, all 8 flowchart presets draggable); Save to Drive writes a real file, but only as a flattened image, not an editable document, so the app still can't be reopened for further editing from Drive
* **Risk** Low for the tools themselves (fixed and verified this pass); Medium for the save gap — a user who expects "Save to Drive" to mean "resume editing later" will be surprised it only produces a flat image

## PDF Viewer

* **Location** `src/apps/pdf-viewer/` (2,285 lines)
* **Uses** `pdfjs-dist` (Mozilla's PDF renderer, bundled locally with its own worker via a Vite `?url` import — no CDN fetch, offline-first per `CLAUDE.md` §18) for real parsing, canvas rendering and text extraction; `platform.files` (`FileService.getFile`/`downloadUrl`) to fetch a Drive file's actual bytes; the real File Explorer `ShareModal` (`apps/file-explorer/components/ShareModal.tsx`) for sharing, not a bespoke one
* **Rebuilt 2026-09-09 (TASK-011).** Previously the entire app was a mock: `data/samplePdfs.ts` held three hand-written fake "documents" (JSON text posing as page content) with no relationship to any real file, `<canvas>` was used only for freehand-ink overlay, "Download" serialized that JSON instead of producing a PDF, "Print" ran `window.print()` on the fake HTML, "Share" fabricated a `studio.workspace.app` link that went nowhere, and File Explorer's `handleOpenWithApp` had no case for `pdf-viewer` at all — double-clicking a real PDF silently did nothing. All of that is gone. The app now:
  * Renders real PDF bytes page-by-page to `<canvas>` via `pdfjs-dist`, with a real selectable/searchable text layer (`pdfjs-dist`'s `TextLayer`) positioned exactly over the glyphs — not synthesized text.
  * Opens three ways: (1) double-click a `.pdf` in File Explorer — routed through the existing `EditorRegistry` (`pdf-viewer` was already mapped there; only the File Explorer dispatch was missing) into a new `pendingPdfViewerFiles` window-open mechanism mirroring `pendingEditorWindowFiles`'s two paths (reuse the primary window, or force a new one); (2) the toolbar's "Open PDF" split button → "From Drive OSX", which opens File Explorer as a real file picker (`requestFilePick`, the same mechanism Code Editor uses) filtered client-side to `.pdf`; (3) "From This Computer", a native `<input type=file>` reading local bytes with no Drive round-trip, or drag-and-drop onto the window.
  * Supports real password-protected PDFs via pdf.js's own `PasswordException`/retry flow (`hooks/usePdfDocument.ts`) — not a hardcoded "drive" string.
  * Highlight, underline and strikeout markup is built from the real text selection's `Range.getClientRects()` — one rect per visual line, so a selection spanning a paragraph wrap renders one box per line instead of a single box stretched across all of them (a real bug found and fixed this pass). Underline and strikeout are drawn as independently-positioned lines calibrated against pdf.js's glyph-cropped span boxes (not a full ascent-to-descent line box), so underline clears descenders and strikeout runs through glyph-middle rather than either landing mid-glyph. Hovering an annotation in Select mode shows a delete button directly on the page.
  * Full-text search (`hooks/usePdfTextIndex.ts`) matches against each page's real extracted text, not fixture strings.
  * Download produces the actual PDF bytes as a `Blob`; Print opens that same blob in a new tab for the browser's native print dialog; Share opens the platform's real `/shares`-backed dialog, but only for a document actually opened from Drive (has a real file id) — a locally-opened file is told to save to Drive first rather than pretending to generate a link for it.
* **Known limitation.** Highlights, underlines, strikeouts, sticky notes, freehand ink and bookmarks are **in-memory `useState` only** — nothing is written to the server or to `localStorage`. Closing the window or reopening the same document loses all of it. This is a new, real gap (not present in the old mock, which had nothing to lose) and is not yet tracked as its own task.
* **Status** `WORKING` — the second frontend entry in this document verified by **live browser automation** (Playwright): local-file open and real page rendering, multi-line highlight/underline/strikeout with corrected positioning verified pixel-by-pixel against both a synthetic and a real-world PDF's fonts, hover-to-delete, full-text search (toolbar button correctly switches the sidebar to Search and autofocuses it — previously a dead button), sticky notes, the password-protected unlock flow, and the Drive-file picker's open → focus → title-update round trip (a genuine focus-stealing bug was found and fixed in that path: the parent window's own click-to-focus handler was re-stealing focus from the freshly-opened picker window, the same bug Code Editor had already hit and fixed elsewhere — same `stopPropagation()` guard applied here). The Drive picker's actual byte-fetch was exercised against the real `/files` API surface (a live 500 was observed and handled correctly when no backend was running) but not against a fully running backend + object storage stack in this pass — same "not exercised against a live API" caveat most of Part 2 carries, scoped narrowly here to *fetching Drive bytes* rather than the open-wiring itself, which is verified.
* **Risk** Low — annotation persistence is the one real gap, and it fails safely (data is simply not there next time, never corrupted or shown as saved when it isn't)

## Settings

* **Status** `PARTIALLY_WORKING` — preferences persist to `localStorage`, not to the user profile, so they do not follow the account to another device
* **Risk** Low

## Calculator, Clock, Terminal, Browser, Launcher

* **Calculator, added 2026-09-09** A fifth mode, Financial (Loan/EMI, compound interest, simple interest, profit margin), alongside the existing Basic, Scientific, Programmer and Converter modes — same in-memory, no-server-state model as the rest of this group.
* **Status** `WORKING` — local-only by nature; no server state is appropriate
* **Risk** Low

---

# Part 3 — Shell and platform layer

| Component | Location | Status |
| --------- | -------- | ------ |
| Window manager | `shell/window-manager/` | `WORKING` — shared chrome, one status bar, portal-rendered menus. Drag and resize keep their state in refs and commit to the store **once on release**; a 120-event drag produces exactly one store write. 44 assertions cover the gesture arithmetic, clamping at every edge and dock size, and the commit count. **The motion itself is unverified** — no browser automation. See [Windows and the dock](../features/shell-windows-and-dock.md). |
| Dock | `shell/taskbar/Dock.tsx`, `dockZone.ts` | `WORKING` — hides whenever a window covers its strip (maximized, dropped over it, or dragged into it mid-gesture), reveals while the cursor is at the bottom edge. 51 assertions cover the full visibility truth table and the live-gesture store. **Not visually reviewed.** |
| Application menus | `platform/menus/` | `WORKING` — dynamic per app, submenus escape clipping via portals |
| Preferences | `shell/preferences/AppSettingsModal.tsx` | `WORKING` — per-app modal, replaced the old shared `PreferencesDialog` (deleted 2026-08-24). Reads/writes only `state.settings.appPreferences[appId]`: per-app theme, per-app default window size, and each app's own `settingsSchema` fields. Editor opts out and keeps its own Settings page (see Code Editor, Part 2). Platform-wide settings (default window mode/size/placement, remember layout, focus-follows-mouse, reduce motion, etc.) moved to the Settings app's new Desktop → Window management tab. See `docs/architecture.md` → Theming for the precedence chain (per-app > global > manifest default). |
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
