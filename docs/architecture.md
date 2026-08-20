# Drive OSX — implementation architecture

How the platform described in [CLAUDE.md](../CLAUDE.md) is actually built today.
CLAUDE.md states the principles; this document states what exists, and where the
seams are for what comes next.

## Shape of the system

```text
                       Browser (OS shell + applications)
                                     │
                    IndexedDB ── Sync engine ── Service worker
                                     │
                                 HTTP / WS
                                     │
                    ┌────────────────┴─────────────────┐
                    │           drive-osx-api          │
                    │        (modular monolith)        │
                    │                                  │
                    │  platform/   configuration, auth │
                    │              authorization,      │
                    │              events, http        │
                    │  modules/    identity, orgs,     │
                    │              files, sharing,     │
                    │              mail, meetings,     │
                    │              notifications,      │
                    │              search, audit       │
                    │  infrastructure/  db, redis,     │
                    │              storage, queue,     │
                    │              realtime, logging   │
                    └────────────────┬─────────────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              ▼                      ▼                      ▼
         PostgreSQL           Object storage               Redis
      (system of record)      (file contents)      (cache, queue, fan-out)
                                     ▲                      ▲
                                     └──── drive-osx-worker ┘
                                        (jobs + event outbox)

     drive-osx-mail (SMTP) ──► API /mail/receive
```

## Backend layout

```text
drive-osx-api/src/
├── main.ts                    API process
├── worker.ts                  background process
├── app.ts                     express assembly and route mounting
├── platform/
│   ├── configuration/         validated environment
│   ├── errors/                error taxonomy
│   ├── http/                  async handler, validation, errors, rate limit,
│   │                          request context, health, OpenAPI
│   ├── authentication/        tokens, authenticate middleware
│   ├── authorization/         roles, central access control
│   └── events/                domain event catalogue + transactional outbox
├── infrastructure/
│   ├── database/              pool, transactions, migrations
│   ├── redis/                 clients, cache
│   ├── storage/               ObjectStorage interface + S3 implementation
│   ├── queue/                 Redis-backed job queue
│   ├── realtime/              WebSocket gateway
│   └── observability/         structured logging with request context
├── modules/
│   ├── identity/              users, sessions, password recovery
│   ├── organizations/         tenants, memberships, teams, storage quota
│   ├── files/                 drive metadata, contents, versions, search
│   ├── sharing/               user/team/link grants, eligible-user search, per-file activity
│   ├── mail/                  mailboxes, delivery
│   ├── meetings/              meetings, participants, chat
│   ├── notifications/         durable + realtime notifications
│   ├── messaging/             chat requests, direct conversations, messages
│   ├── contacts/              personal address book, presence
│   ├── search/                cross-domain search
│   └── audit/                 append-only audit trail
└── workers/                   domain-event handlers and job handlers
```

A module owns its repository (SQL), service (rules), and routes. Cross-module
calls go through another module's service — never into its tables. That is what
makes a later extraction into a service a move rather than a rewrite.

## Multi-tenancy

One database, `organization_id` on every tenant-scoped table. The tenant for a
request comes from the session (or an `X-Organization-Id` header checked against
membership) — never from the request body. Every query filters on it, and
`platform/authorization/access-control.ts` is the only place that decides
whether an actor may touch a resource.

Roles: `owner`, `admin`, `manager`, `member`, `guest` for the workspace;
`owner`, `editor`, `commenter`, `viewer` for individual resources. The strongest
grant wins — ownership, workspace administration, a direct/team share on the
file itself, or a share on one of its ancestor folders (`effectiveFileRole` in
`access-control.ts` walks `parent_id` up to the root, so sharing a folder
implicitly shares everything inside it). Missing access is reported as "not
found" so the API does not confirm the existence of resources the caller
cannot see.

"Share with..." only offers people already in the sharer's contacts
(`modules/contacts`) — the app's existing notion of a connection — rather than
searching the full `users` table, via `GET /shares/files/:fileId/eligible-users`.
Public links (`POST /shares/files/:fileId/links`) remain the one path that can
reach outside the tenant, gated by the organization's sharing policy; a link is
resolved anonymously at `GET /shares/links/:token` and opened in the UI at
`/s/:token`.

### Every user starts alone in their own tenant

Registration provisions a **`personal` organization** per user
(`identity.service.ts` → `createOrganizationInTransaction(…, type: 'personal')`).
Two people who sign up independently are therefore *never* co-members, and in a
fresh deployment every organization has exactly one member.

This is easy to forget and expensive to forget, because it makes
"scope it to the caller's organization" the wrong default for anything social.
Applied to direct messaging it produced two defects that made the feature
completely unusable: nobody could be found, and an accepted conversation was
invisible to the person who accepted it (`TASK-001`, `TASK-002`).

The rule that resolves it:

| Concern | Boundary | Why |
| ------- | -------- | --- |
| Files, folders, shares, mail, meetings, audit | `organization_id` | Genuinely tenant-owned resources. |
| Conversations, messages | participation (`conversation_participants`) | A direct conversation spans two tenants by construction. |
| Chat requests | involvement (`requester_id` / `recipient_id`) | The row carries the *sender's* tenant; the recipient is elsewhere. |
| Contacts | `owner_id` | A personal address book, not a shared directory. |
| Directory search | exact handle → platform-wide; substring → shared organizations | A username must work as an address without the user table becoming enumerable. |

`organization_id` is still recorded on conversations and messages as
originating context for audit — it is simply not the access check.

## Files

A file is metadata in PostgreSQL plus objects in storage:

```text
originals/{org}/{fileId}                current contents
versions/{org}/{fileId}/{versionId}     archived contents
previews/{org}/{fileId}                 generated preview
thumbnails/{org}/{fileId}               generated thumbnail
```

The newest `file_versions` row points at `originals/…`. When contents are
replaced, the outgoing bytes are copied to an immutable `versions/…` key, that
row is repointed at the copy, and a new row is inserted for the new contents.
History is therefore immutable without storing anything twice, and a failed
archive aborts the edit rather than silently discarding a version.

Writes go to storage first and metadata second, so a failed upload leaves no row
pointing at a missing object; if the transaction then fails, the object is
deleted. Small text files are returned inline as `content`; everything else is
fetched with a short-lived signed URL so bytes never proxy through the API.

Presigned URLs are signed with the *public* storage endpoint, because SigV4
covers the `Host` header — rewriting the host afterwards invalidates the
signature.

## Events and background work

State changes write a row to `domain_events` inside the same transaction
(transactional outbox). The worker claims batches with `FOR UPDATE SKIP LOCKED`,
runs the registered handlers, and marks the event processed only if all of them
succeeded; an unprocessed claim expires after five minutes and is retried.

Handlers enqueue jobs on the Redis queue (text extraction for search, preview
generation, object purging, notifications). Delivery is at least once, so
handlers are idempotent; failures back off exponentially and end in a
dead-letter list rather than disappearing.

## Offline and synchronisation

```text
User action → local state updated → operation queued in IndexedDB
                                          │
                              online?  ───┴─── offline?
                                 │              │
                          replay in order   stay queued, UI shows the state
```

`platform/offline/sync-engine.ts` replays operations oldest-first. If an
operation fails because the server is unreachable, the run stops there —
sending later operations first would reorder the user's intent. Permanent
failures (4xx) are marked as needing attention with retry and discard actions in
the system tray. Reads fall back to the IndexedDB cache; the service worker
keeps the shell itself bootable offline and marks cached API responses with
`X-Served-From`.

Operation states — `idle`, `pending`, `processing`, `success`, `failed`,
`retrying`, `offline` — are rendered directly, so the user can always tell
whether their work is saved.

## Frontend layout

```text
drive-osx-ui/src/
├── shell/          desktop, window-manager, taskbar, launcher, notifications,
│                   system-tray, context-menu, auth screens, shell state
├── apps/           one directory per application, all lazily loaded
├── platform/       api (http client, ApiService), files, meetings, storage,
│                   permissions, registry, events, offline, types, facade
├── design-system/  tokens + shared primitives
└── App.tsx         routing and desktop composition
```

Applications consume `platform` (`src/platform/index.ts`) — `platform.files.open()`,
`platform.windows.open()`, `platform.notifications.show()`, `platform.sync.status()` —
rather than HTTP endpoints or shell internals.

Every app is a separate chunk: the shell boots without loading applications the
user has not opened.

State is kept separate by kind: server state through the platform services,
shell/UI state in the Zustand store, local/offline state in IndexedDB.

### Window gestures and the dock

One boundary here is load-bearing enough to state in the architecture rather
than only in the component: **a pointer gesture does not write to the system
store while the pointer is down.**

The store owns `windows` and replaces the whole array on every change, so a
write during a drag re-renders every subscriber — the dock, the launcher, the
terminal, every other open window. At sixty writes a second that is not a slow
render, it is a render storm, and effects keyed on `windows` amplify it until
React stops with *Maximum update depth exceeded*.

Dragging and resizing therefore keep their state in refs, move the element
directly inside one `requestAnimationFrame`, and commit once on `pointerup` or
`pointercancel`. Anything else that reacts to `windows` should depend on a
signature of the fields it actually reads — `App.tsx` routing keys on
`id:isOpen`, the dock on ids — rather than on the array, which changes whenever
any window moves.

The one consumer that genuinely needs a window's position *during* a gesture is
the dock, which hides whenever a window reaches its strip of the screen.
`shell/taskbar/dockZone.ts` owns that measurement and a small store carrying
the single fact the dock needs: which window is being moved, and whether it
currently covers the dock.

The full behaviour — the gesture state machine, the dock visibility truth
table, and the traps that make the obvious implementation wrong — is in
[Windows and the dock](features/shell-windows-and-dock.md). Read it before
changing `shell/window-manager/` or `shell/taskbar/`.

### Theming

Two independent inputs can decide whether something renders light or dark — the
desktop's own theme and the operating system's `prefers-color-scheme` — so an
application has to say *which* it follows. That is one preference with four
values, resolved in `platform/theme/`:

| Choice | Follows |
| ------ | ------- |
| `theme` (default) | the global theme, Settings → Appearance → Theme |
| `light` / `dark` | nothing; pinned |
| `system` | the operating system |

```text
Settings → Appearance → Theme  ──┐
                                 ├──►  resolveAppTheme()  ──►  light | dark
OS prefers-color-scheme        ──┤
appPreferences[appId].themeChoice┘
```

Themes and wallpapers are **catalogues**, not string literals: `THEMES` in
`platform/theme/themes.ts` and `WALLPAPERS` in `platform/theme/wallpapers.ts`.
`SystemSettings['theme']` and `['wallpaper']` are derived from them, so an id
that is not in a catalogue is a compile error.

Each theme declares a `family` — `light`, `dark` or `terminal` — plus its accent,
paired wallpaper and a full set of chrome classes. The family is what everything
else branches on: `globalThemeIsDark` is *derived* from it rather than testing
ids, so adding a dark theme does not require finding every `=== 'modern-dark'`
in the shell. Terminal families count as dark.

### Shell surfaces

Windows get `chrome`; everything outside a window — dock, top bar, popups,
menus, notification centre, application menu — gets `surfaces`, read through
`useShellTheme()`. That hook is deliberately separate from `useAppTheme`: the
shell is not a window and has no per-application preference, because a dock
disagreeing with the desktop behind it is an inconsistency no user could
explain.

Surfaces are held per *family*, not per theme, because they describe physics
rather than palette: how translucent a floating surface is, how it catches
light at its top edge, how far its shadow falls. The theme contributes only the
accent. That is what makes twelve themes read as one system.

**The glass recipe.** Four things together, and all four are load-bearing:

1. **A gradient fill, not a flat one** — real glass catches more light at its
   top edge, so the fill falls off downward. A flat wash at any opacity reads
   as a sheet of colour laid over the desktop.
2. **Saturation, not just blur** — blurring alone averages the wallpaper
   towards grey and the surface goes foggy. `backdrop-saturate-150` puts the
   colour back.
3. **Low fill, high blur** — panels sit at 44–62% so the wallpaper comes
   through, and a 64px blur turns it into a soft wash rather than detail
   competing with the text.
4. **Restrained shadow, faint inset highlight** — enough to seat the surface
   above the desktop, not enough to look lacquered.

Readability is protected by two rules: `card` is deliberately more solid than
the panel around it, so text sits on a readable ground rather than on the
wallpaper; and text tokens are a step stronger than they would be on an opaque
surface. Terminal themes stay near-opaque on purpose — a phosphor screen is a
lit surface, and glass would undo it.

| Token | Used for |
| ----- | -------- |
| `panel` | any floating surface — dock pill, popup, menu, context menu |
| `card` / `cardHover` | an inset row or tile inside a panel |
| `tile` / `tileHover` | application-menu tiles, deliberately lighter than `card` |
| `scrim` | the full-screen backdrop behind the application menu |
| `text` / `textMuted` / `textSubtle` | the three text weights |
| `hover` / `pressed` | neutral washes for controls on a panel |
| `control` / `controlFocus` / `placeholder` | inputs and segmented controls |
| `accent` | a raw colour for inline styles |

**Accents are inline styles, not classes.** Tailwind builds the classes it finds
as literal text in the source, so a class assembled at runtime from a hex value
would never exist. The same rule bans composing a variant with an interpolated
value — `` `hover:${shell.text}` `` looks reasonable and silently produces
nothing. `placeholder` is a token for exactly this reason: it is spelled out
rather than derived from `textSubtle`.

The default is **Nova** — `nova-light` / `nova-dark`, paired with the `nova-day`
and `nova-night` wallpapers: layered paper-cut waves running from deep indigo
in the lower left through violet and magenta to pink at the top right, with one
pale sliver breaking the spectrum. Halo remains available.

A theme with a strong identity may also carry a `surfaceTint`, merged over its
family's surfaces. The family still owns the *behaviour* — transparency, blur,
shadow — and the theme only restates the colour, so Nova's dock and panels
carry its lilac and plum while matching every other theme's depth.

Nova Night is not Nova Day darkened. Its brightness peaks in the middle band
and falls away at both the top and the bottom, so the spectrum reads as burning
through near-black rather than as a lit sky. Uniformly darkening a light
palette produces a washed-out result, which is worth remembering for any future
pair.

Most wallpapers are a base plus blurred or patterned layers and are pure data,
rendered by one component; the original four use SVG or generated content and
are flagged `bespoke: true` with their own renderers.

A wallpaper also declares a `tone`. Desktop icon labels sit directly on the
wallpaper, so they take their colour from the tone rather than the theme —
before light wallpapers existed those labels were hardcoded white.

`resolveAppTheme` and `resolveWindowTheme` are pure and live in
`platform/theme/appTheme.ts`; `useAppTheme(appId)` is the React binding and is
the only thing an application should call. Every window's menu carries the four
choices, and Preferences → Applications lists them for every installed app.
Because everything is derived from store state and a live `matchMedia`
subscription, changing the global theme re-themes open windows immediately.

Window chrome deliberately keeps the *concrete* theme rather than collapsing to
light/dark, which is what lets a window wear Amber Terminal or Ember instead of
a generic dark. Surfaces that still hold their own class map keyed by the
original three ids use `chromeTheme`, which reduces any theme to its family's
representative — so a new theme renders as its family rather than falling
through to light.

**Adding a theme or wallpaper** is one catalogue entry. A theme needs a family,
an accent, an existing wallpaper id and eight chrome classes; a wallpaper needs
a tone, a group, a swatch, and either `base`/`layers` or a bespoke renderer.
Settings, the window menu, the terminal's `settings theme` command, every shell
surface and the type union all pick it up with no further edits.

`themeForMode` decides where the global Light/Dark control lands: it stays put
when you are already on the requested side, and otherwise moves to the theme's
counterpart where one exists. Someone on Carbon who clicks Dark keeps Carbon.

**Migration.** The preference used to be `appPreferences[appId].theme` with
three values, where `'system'` meant *follow the desktop*. It is read once and
mapped onto `'theme'`, which is the same behaviour under the new name, then the
old key is dropped so one setting is never described twice. Shell surfaces —
the dock popups, context menus, notification centre — follow the global theme
directly; they are not windows and have no per-app preference.

## Errors

The API answers with a stable envelope:

```json
{
  "message": "…",
  "error": { "code": "conflict", "message": "…", "details": {}, "retryable": false, "requestId": "…" }
}
```

`code` drives client behaviour (re-authenticate, queue offline, show field
errors, retry), `details.fields` carries per-field validation messages, and
`requestId` ties a user-visible failure to the server logs. Server errors are
logged with full context and answered with a generic message.

## Security

- Passwords hashed with bcrypt; refresh and reset tokens stored only as SHA-256
  hashes and rotated on every use.
- Password reset and login answer identically for unknown accounts, so neither
  can be used to enumerate users.
- Resetting or changing a password revokes every existing session.
- Rate limits per bucket (credentials, uploads, mail, general API).
- Share links store only a token hash; the token is shown once.
- Meeting passcodes are never returned by the API.
- Audit entries are written in the same transaction as the change they describe.

### The SMTP gateway is a credentialled caller, not a trusted network

Two endpoints cannot carry a user session, because there is no logged-in actor
on the other end:

| Endpoint | Called by | Why it has no session |
| -------- | --------- | --------------------- |
| `POST /mail/receive` | `drive-osx-mail` | Inbound mail arrives from the internet. |
| `POST /mail/auth` | `drive-osx-mail` | It *is* the credential check for SMTP/IMAP. |

Both are gated by `MAIL_GATEWAY_TOKEN`, presented as `X-Mail-Gateway-Token` and
compared in constant time (`platform/authentication/mail-gateway.ts`).

This replaced an assumption that the endpoints were "reachable only from the
internal network". They were not: the API is published on a host port, and a
live probe delivered a message into a real mailbox with an attacker-chosen
`from` address, no credential of any kind (`TASK-003`). **Network placement is
not an authentication mechanism here.**

The API refuses to boot in production without the token. In development an
unset token is allowed so a fresh checkout can receive mail, and logs a warning
once. A *wrong* token is always rejected, in both modes.

### Accepted risks

- Access and refresh tokens are held in `localStorage`, so any script running
  on the origin can read them. No XSS sink exists today (`dangerouslySetInnerHTML`
  appears nowhere in the UI), and this is the standard SPA trade-off. The
  stronger option — refresh token in an `HttpOnly` cookie — needs CSRF
  protection and cookie-aware CORS; see `docs/architecture/decisions/ADR-002`.
- `ApiService.register/login` name their field `passwordHash` but send the
  plaintext password over TLS for the server to bcrypt. The behaviour is
  correct; the name is not. Do **not** "fix" it by hashing in the browser —
  that makes the hash password-equivalent and gains nothing.

## Configuration

Each service reads its own `.env`; the API validates the result against a schema
at boot and refuses to start on anything missing or malformed, so a
misconfigured deployment fails immediately rather than at the first request that
needs the value.

`.env` files are not committed. `.env.example` is therefore the only description
of what a service needs, and the two must change together — the rule and its
rationale are in CLAUDE.md §35. `./scripts/check-env.sh` reports drift across all
four pairs and exits non-zero when they disagree, which makes it usable from a
hook or CI.

## Containers

One multi-stage `Dockerfile` per service, with `dev` and `production` targets
sharing the same base image and dependency resolution — the two environments
cannot drift, and there is no second file to keep in sync. `COMPOSE_FILE` in
the root `.env` selects the layer — `docker-compose.yml` alone builds
`production`, adding `docker-compose.dev.yml` builds `dev` — and each mode
carries its own image tag so switching never reuses the other's artefact.
The two files exist only because Compose cannot omit a bind mount based on a
variable; every other difference between the modes is environment-driven.

Runtime containers are unprivileged (`node` uid 1000; nginx uid 101 on port
8080), run with `no-new-privileges`, install dependencies with
`--ignore-scripts`, carry their own `HEALTHCHECK`, and use exec-form commands so
the process is PID 1 and receives `SIGTERM` for graceful shutdown. Base images
are pinned; logs are capped at 10 MB × 3 files per container.

The worker exposes a small HTTP health endpoint (`WORKER_HEALTH_PORT`, default
7001) reporting queue depth and event backlog, so a background process with no
public socket can still be monitored and orchestrated.

## What is deliberately not here yet

Per CLAUDE.md §46, these are absent until there is a concrete need:
a dedicated search engine (PostgreSQL full text is doing the job), a vector
database (pgvector when AI retrieval arrives), an event-streaming platform,
CRDT collaboration, and image processing for real thumbnail generation. The
seams exist — `ObjectStorage`, the search routes, the event outbox, the job
queue — so each can be introduced without reshaping the platform.

Also absent, and tracked in `docs/status/audit-and-plan.md` rather
than assumed to exist:

- **Calendar persistence.** The Calendar app keeps events in the browser only;
  there is no `calendar` module and no `calendar_events` table (TASK-009).
- **Mail folders and rules.** Messages are real; custom folders and filter
  rules in Mail Studio are still local placeholders (TASK-010).
- **PDF Viewer file integration.** It opens bundled sample documents rather
  than the user's own Drive files (TASK-011).
- **Frontend tests.** No test runner is configured for `drive-osx-ui`
  (TASK-014); see `docs/guides/testing.md`.

## Application data sources at a glance

Which applications hold real, server-owned data, and which are local-only:

| Application | Data source | Status |
| ----------- | ----------- | ------ |
| File Explorer | API (`/files`, `/shares`) | Server-owned |
| Messenger | API (`/messaging`) | Server-owned |
| Contacts | API (`/contacts`) | Server-owned |
| Trash | API (`/files/trash`), local cache | Server-owned |
| Mail Studio | API (`/mail`) for messages | Messages server-owned; folders/rules local |
| Code Editor | API (`/files`) | Server-owned |
| Meet | API (`/meetings`) + WebRTC | Server-owned |
| Calendar | Browser only | Not persisted (TASK-009) |
| Spreadsheet, Presentation, Paint | Browser only | Documents not yet stored in Drive |
| PDF Viewer | Bundled samples | Not wired to Drive (TASK-011) |
| Calculator, Clock, Terminal, Browser | Browser only | Correct — no server state to hold |
