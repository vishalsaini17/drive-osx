# Integration Map

What depends on what, so you can tell what a change will break **without
reading the whole codebase first**.

Status values are evidenced: `VERIFIED` means exercised against the running
stack during the 2026-08-13 audit; `REVIEWED` means the code was read but the
path was not executed; `UNVERIFIED` means neither.

---

## 1. Frontend → Backend

Every call goes through `platform/api/http.ts`, which is the single place that
attaches the bearer token, adds `X-Organization-Id`, refreshes an expired
token, classifies errors and detects being offline. **Do not call `fetch`
directly from an application.**

| Source | Destination | Method | Purpose | Auth | Failure handling | Status |
| ------ | ----------- | ------ | ------- | ---- | ---------------- | ------ |
| Login/Register screens | `/register` `/login` | POST | Create session | None | Field-level errors from `details.fields` | `VERIFIED` |
| `http.ts` interceptor | `/auth/refresh` | POST | Rotate expired access token | Refresh token | One retry, then `expired` session event → redirect to login | `REVIEWED` |
| File Explorer, Code Editor | `/files/*` | REST | Drive CRUD, versions, trash | Bearer | Store rolls back and notifies on failure | `VERIFIED` |
| File Explorer | `/shares/*` | REST | Grants and links | Bearer | Error surfaced in share dialog | `REVIEWED` |
| Trash app | `/files/trash`, `/files/:id/permanent` | GET/DELETE | Server-owned trash | Bearer | Partial failure keeps failed items listed and says how many | `VERIFIED` |
| Messenger | `/messaging/*` | REST | Requests, conversations, messages | Bearer | Inline error banner + retry; offline worded separately | `VERIFIED` |
| Messenger, Contacts | `/contacts/*` | REST | Address book | Bearer | Optimistic writes roll back on rejection | `VERIFIED` |
| Shell (`usePresenceHeartbeat`) | `/contacts/presence/*` | POST | Publish presence | Bearer | Silent by design — ambient, retried next beat, server decays it | `VERIFIED` |
| Mail Studio | `/mail/*` | REST | Mailbox | Bearer | Empty and error states distinguished | `VERIFIED` |
| Meet | `/meetings/*` | REST | Meeting lifecycle | Bearer | Error toast | `REVIEWED` |
| Shell | `/notifications` | GET/PATCH | Notification centre | Bearer | Falls back to local list | `VERIFIED` |
| Shell command palette | `/search` | GET | Cross-domain search | Bearer | Empty result state | `VERIFIED` |

**Data mapping caution.** `FileService` maps API `id` onto local `_id`/`id` in
places. When changing a file field, check both the mapper and the consumer.

## 2. Backend → PostgreSQL

| Source | Purpose | Transaction | Status |
| ------ | ------- | ----------- | ------ |
| Every module service | Domain reads and writes | `withTransaction` for multi-statement changes | `VERIFIED` |
| `publishEvent` | Outbox row | **Same transaction as the change** — never separate | `VERIFIED` |
| `access-control.ts` | Membership and effective role | Read-only, cached 60s in Redis | `VERIFIED` |
| `migrate.ts` | Schema | One transaction per file, checksum-verified | `VERIFIED` |

Only the API and worker connect to PostgreSQL. **The UI and the SMTP gateway
never do**, and must not start.

## 3. Backend → object storage

| Source | Purpose | Failure handling | Status |
| ------ | ------- | ---------------- | ------ |
| `files.service` | Store bytes before metadata | Failed upload leaves no row; failed transaction deletes the object | `VERIFIED` |
| `files.service` | Presigned download URLs | Signed with the **public** endpoint — SigV4 covers `Host`, so rewriting it afterwards breaks the signature | `REVIEWED` |
| Worker `file.purge` | Erase objects after permanent delete | At-least-once; deleting an absent object is a no-op | `REVIEWED` |

## 4. Backend → Redis

| Source | Purpose | If Redis is down | Status |
| ------ | ------- | ---------------- | ------ |
| `rate-limit.ts` | Request budgets | Requests proceed — availability chosen over enforcement | `REVIEWED` |
| `cache.ts` | Membership cache | Falls through to PostgreSQL | `VERIFIED` |
| `queue.ts` | Job queue | Jobs stop; events stay unprocessed in the outbox and resume | `REVIEWED` |
| `notifications` | Realtime fan-out | Logged; the durable row is still written | `REVIEWED` |

## 5. API → Worker (the outbox)

```text
Service call
   │ (one transaction)
   ├── domain row written
   └── domain_events row written
                │
        Worker claims a batch  (FOR UPDATE SKIP LOCKED)
                │
        Runs every handler for the event
                │
        All succeeded ──► mark processed
        Any failed    ──► leave unprocessed; claim expires after 5 min; retried
```

| Event | Handlers | Status |
| ----- | -------- | ------ |
| `file.uploaded` | index for search; preview if image | `REVIEWED` |
| `file.updated` | re-index | `REVIEWED` |
| `file.deleted` | purge objects | `REVIEWED` |
| `file.shared` | notify the recipient | `REVIEWED` |
| `mail.received` | notify the mailbox owner | `REVIEWED` |
| `user.registered` | welcome notification | `VERIFIED` |
| `organization.member_added` | notify the new member | `REVIEWED` |
| `chat.request_sent` | notify the recipient | `VERIFIED` |
| `chat.request_accepted` | notify the requester | `VERIFIED` |
| `chat.message_sent` | notify every other participant, skipping muted | `VERIFIED` |

**Handlers must be idempotent.** Delivery is at-least-once and a whole event is
re-dispatched when any sibling handler fails.

## 6. SMTP gateway → API

```text
Internet ──SMTP──► drive-osx-mail ──HTTPS + X-Mail-Gateway-Token──► API /mail/receive
                        │                                               │
                        └── /mail/auth (mailbox credentials)            └── mailbox + mail.received
```

| Property | Value |
| -------- | ----- |
| **Authentication** | `MAIL_GATEWAY_TOKEN`, constant-time compared |
| **Configuration** | Identical value in `drive-osx-api/.env` and `drive-osx-mail/.env` |
| **Failure handling** | Retries 5xx/429/network with exponential backoff; never retries 4xx |
| **Timeout** | 15s per request |
| **Rate limit** | 600/min on `/mail/receive` |
| **If they disagree** | Every delivery 401s. First thing to check when mail stops. |
| **Status** | `VERIFIED` — a real SMTP message traversed the whole path after the change |

The gateway holds **no state** and never touches PostgreSQL or object storage.

## 7. Browser ↔ realtime gateway

| Property | Value |
| -------- | ----- |
| Transport | WebSocket (`infrastructure/realtime/signaling.ts`) |
| Client | `platform/realtime/RealtimeClient.ts`, connected by the **shell** |
| Purpose | Meeting signalling, per-user notification fan-out |
| Backing | Redis pub/sub, so any API instance can serve any client |
| Auth | Access token in the query string — a WebSocket cannot set headers |
| Reconnect | Exponential backoff with jitter; 4401 backs off further so a refresh can land |
| Status | `VERIFIED (LIVE)` — a real socket received a pushed message, 16 assertions |

**Proxy configuration is part of this integration.** The socket is opened
against the page origin, so `/ws` has to be proxied *with upgrade support* at
whatever serves the UI:

* production — the `location /ws` block in the UI image's nginx config;
* development — `server.proxy['/ws']` with **`ws: true`** in `vite.config.ts`.

The development half was missing, so realtime silently failed there (for Meet
as well as Messenger) while working in production.

## 8. Cross-application dependencies inside the UI

| Application A | Application B | Via | What flows | Status |
| ------------- | ------------- | --- | ---------- | ------ |
| Messenger | Contacts | `/contacts` (server) | Accepting a request creates both contact rows **in the acceptance transaction** | `VERIFIED` |
| Messenger | Notification centre | `/notifications` | Request, acceptance and message notifications | `VERIFIED` |
| File Explorer | Code Editor, PDF Viewer, Paint | `EditorRegistry` | Which app opens which MIME type | `REVIEWED` |
| File Explorer | Trash | Shell store + `/files/trash` | Trashed items | `VERIFIED` |
| Any app | Window manager | `platform.windows` | Open, focus, close | `REVIEWED` |
| Window manager | Dock | `shell/taskbar/dockZone.ts` | Which window is being dragged, and whether it covers the dock's strip. Published per frame during a gesture **instead of** writing geometry to the shell store — see [Windows and the dock](../features/shell-windows-and-dock.md) | `VERIFIED (TEST)` |
| Window manager | Shell store | `handleMoveWindow` / `handleResizeWindow` | Final geometry, committed **once on pointer release**. Anything reading `windows` in an effect must key on the fields it uses, not the array | `VERIFIED (TEST)` |
| Any app | Window status bar | `WindowStatusContext` | Contributed status content — **the reason apps stopped showing two footers** | `REVIEWED` |
| Any app | Title-bar menu | `AppMenuContext` | Per-app menu contributions | `REVIEWED` |
| Shell | Presence | `usePresenceHeartbeat` | Session-wide presence, published once — **not per app** | `VERIFIED` |
| Any app | Theme | `platform/theme` (`useAppTheme`) | Light/dark decision, from the global theme, the OS, or a pin — see `docs/architecture.md` | `REVIEWED` |
| Mail Studio | Contacts | *none* | Still uses its own local list (TASK-010) | Gap |
| Calendar | *nothing* | — | No persistence at all (TASK-009) | Gap |

## 9. Configuration coupling

Values that must agree **across** services. Each has broken something before.

| Value | Must match between | Symptom when wrong |
| ----- | ------------------ | ------------------ |
| `MAIL_GATEWAY_TOKEN` | API ↔ mail gateway | All inbound mail 401s |
| `CORS_ORIGINS` | API ↔ the UI's real origin | Browser blocks every request |
| `VITE_API_BASE_URL` | UI build ↔ nginx proxy path | 404 on every call |
| `STORAGE_PUBLIC_URL` | API ↔ the browser's route to storage | Downloads fail signature validation |
| `DATABASE_URL` | API ↔ worker | Worker cannot drain the outbox |
| `API_VERSION` | API ↔ gateway ↔ UI base URL | 404 on every call |

Verify with `./scripts/check-env.sh` before committing.

## 10. What breaks what — quick reference

| If you change | Re-verify |
| ------------- | --------- |
| `platform/api/http.ts` | Every application; auth refresh; offline detection |
| `access-control.ts` | Files, sharing, meetings, messaging, contacts — **all** authorization |
| A `*.routes.ts` | Its service client in `drive-osx-ui/src/platform/` |
| A migration | Never edit an applied one — add a new file |
| `domain-events.ts` | `workers/handlers.ts`, and whether new events need subscribers |
| `systemStore.tsx` | Every app reading shell state; File Explorer and Trash especially |
| `platform/theme/appTheme.ts` | Every window's chrome and every app that calls `useAppTheme` — the resolution table is pure, so check it directly |
| `platform/theme/themes.ts` | Window chrome, menus, context menus, notification centre, and `SystemSettings['theme']`. Removing an id is a breaking change for stored settings |
| `platform/theme/wallpapers.ts` | The desktop background **and desktop icon label colour** (via `tone`), plus `SystemSettings['wallpaper']` |
| `WindowStatusContext` / `AppMenuContext` | Every app that contributes to them |
| Messaging or contacts scoping | Run `tests/e2e/messaging-and-contacts.sh` — it exists because this went wrong twice |
