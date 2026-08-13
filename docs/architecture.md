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
│   ├── sharing/               user/team/link grants
│   ├── mail/                  mailboxes, delivery
│   ├── meetings/              meetings, participants, chat
│   ├── notifications/         durable + realtime notifications
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
grant wins — ownership, workspace administration, direct share, team share.
Missing access is reported as "not found" so the API does not confirm the
existence of resources the caller cannot see.

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
