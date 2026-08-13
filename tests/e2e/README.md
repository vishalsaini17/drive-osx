# End-to-end workflow probes

These scripts exercise the **running stack** over HTTP — the layer the unit
tests deliberately do not reach. Both defects that made messaging unusable
(`TASK-001`/`TASK-002`) and the request-id column collision (`TASK-020`) lived
in SQL, and none of them was visible to a typecheck, a build or a unit test.

They are shell + `curl` + `python3` on purpose: no new dependency, no build
step, runnable against any environment that answers HTTP.

## Running

Bring the stack up first, then:

```sh
./tests/e2e/platform-workflows.sh      # identity, files, sharing, trash, search, mail
./tests/e2e/messaging-and-contacts.sh  # cross-org messaging, contacts, presence, notifications
./tests/e2e/realtime-messaging.sh      # live WebSocket delivery and notification payloads
```

Credential endpoints are rate limited (20 per 5 minutes). Running all three
back to back more than once will exhaust that bucket and produce sign-in
failures that are the limiter working, not a regression — wait out the window
and re-run.

Both exit non-zero if any check fails, so they can gate a pipeline. They target
`http://localhost:3001/api/v1` (the development port published by
`docker-compose.dev.yml`); edit `API` at the top of each file for another
environment.

## What they assert

`platform-workflows.sh`

* registration, duplicate rejection, input validation
* login, wrong-password rejection, token and no-token profile access
* organization listing and storage summary
* folder/file creation, listing, breadcrumbs, content download
* **tenant isolation** — a second user gets 404, not 403, on another
  tenant's file (existence is not disclosed)
* trash → list → restore
* search, notifications, audit log, mail inbox

`messaging-and-contacts.sh`

* three users registered independently, each landing in their **own personal
  organization** — the shape that broke the original implementation
* exact username/email lookup resolves across organizations (case-insensitively)
* substring search does **not** enumerate users in other tenants
* chat request → the recipient in another tenant can see it → accept
* both sides then see the conversation, and messages flow both ways
* a third party is refused reads, writes and listing
* contacts are created for both sides by acceptance, with `source=chat_request`
* contact CRUD, search, favourites, cross-user isolation
* save-a-user-to-contacts is idempotent
* presence heartbeat, sign-off and lookup
* notifications are produced for request/accept/message

`realtime-messaging.sh`

* opens a **real WebSocket** through the UI's own origin, so it covers the
  dev-server proxy as well as the gateway — realtime silently failed in
  development because Vite was not configured to upgrade `/ws`
* asserts the pushed notification arrives without any polling, exactly once
* checks the payload carries what the client needs: a readable preview, the
  conversation to open, a message id for deduplication, and the target app
* confirms a message survives the recipient being offline, and that the sender
  is never notified of their own message

## Adding to these

When you fix a bug in a flow that crosses a process boundary, add the check
here rather than only in a unit test. A `chk` line is three tokens: label,
expected, actual.

## Known gap

These run against a shared database and leave their fixtures behind. A
disposable schema per run is proposed in `docs/guides/testing.md` (TASK-016).
