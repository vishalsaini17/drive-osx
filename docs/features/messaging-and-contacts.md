# Messaging and Contacts

## Purpose

Direct messaging between users, gated by a request the recipient must accept,
with an address book that fills itself as a side effect of accepting.

## Business requirements

1. Find people by username; no fabricated directory.
2. Send a **short note only** — 280 characters — until the request is accepted.
3. The recipient accepts or rejects.
4. Acceptance creates the conversation **and** adds each person to the other's
   contacts.
5. No normal messaging before acceptance.
6. Contacts show real connection status.
7. Everything persists in PostgreSQL. No mock data anywhere.

## User flow

```text
A opens Messenger ──► searches B's username ──► exact match found (any tenant)
      │
      └─► composes ≤280 chars ──► POST /messaging/requests ──► 201
                                        │
                        domain_events: chat.request_sent
                                        │
                                     Worker ──► notification for B
                                        │
B opens Messenger ──► request inbox shows it ──► Accept
      │
      └─► POST /messaging/requests/:id/respond {accept}
                    │  ONE TRANSACTION
                    ├── chat_requests.status = 'accepted'
                    ├── conversations row
                    ├── conversation_participants ×2
                    ├── direct_conversation_keys (ordered pair, unique)
                    ├── contacts ×2  (source = 'chat_request')
                    └── domain_events: chat.request_accepted
                                        │
                                     Worker ──► notification for A
      │
      └─► both sides see the conversation; messages flow both ways
                                        │
                        each message ──► chat.message_sent ──► notification
```

Rejection sets `status = 'rejected'` and creates nothing else.

## Frontend

| Piece | Location |
| ----- | -------- |
| Messenger | `src/apps/messages/index.tsx` |
| Messenger theme | `src/apps/messages/useMessengerTheme.ts` |
| Contacts | `src/apps/contacts/index.tsx` |
| Contacts adapter | `src/apps/contacts/adapter.ts` |
| Messaging client | `src/platform/messaging/MessagingService.ts` |
| Contacts client | `src/platform/contacts/ContactsService.ts` |
| Presence heartbeat | `src/platform/contacts/usePresenceHeartbeat.ts` (mounted in `App.tsx`) |
| Realtime socket | `src/platform/realtime/RealtimeClient.ts` (shell-level) |
| OS notifications | `src/platform/notifications/SystemNotifier.ts` |
| Realtime → desktop bridge | `src/shell/notifications/useRealtimeNotifications.ts` (mounted in `App.tsx`) |

Delivery is realtime over `/ws`. Polling remains as a fallback for when the
socket is down: the conversation list every 15s, and the **open thread every
10s** — the latter was missing entirely, which is what made messages appear
only after switching conversations.

**The adapter exists** because the API stores one `displayName` — many names do
not split into exactly two parts — while the Contacts components were built
around first/last. It also derives a stable avatar colour from the id, so a
contact keeps the same colour across reloads instead of flickering.

## Backend

| Piece | Location |
| ----- | -------- |
| Messaging | `src/modules/messaging/` |
| Contacts and presence | `src/modules/contacts/` |
| Event handlers | `src/workers/handlers.ts` |

## APIs

```text
GET    /messaging/users/search?q=&limit=
GET    /messaging/requests
POST   /messaging/requests                     { recipientId, message ≤280 }
POST   /messaging/requests/:id/respond         { action: accept | reject }
DELETE /messaging/requests/:id
GET    /messaging/conversations
GET    /messaging/conversations/:id/messages?limit=&before=
POST   /messaging/conversations/:id/messages   { body, replyToId?, threadParentId?, mentions? }
POST   /messaging/conversations/:id/read
DELETE /messaging/messages/:id

GET    /contacts?search=&favourites=
POST   /contacts                               { displayName, … } or { contactUserId }
GET    /contacts/:id
PATCH  /contacts/:id
DELETE /contacts/:id
POST   /contacts/presence/heartbeat            { status?, statusText?, statusEmoji? }
POST   /contacts/presence/offline
POST   /contacts/presence/lookup               { userIds: [] }
```

## Database

Migration `0004`: `chat_requests`, `conversations`, `conversation_participants`,
`direct_conversation_keys`, `messages`, `contacts`, `user_presence`.
Migration `0005`: contact detail fields.

Constraints doing real work:

```sql
-- At most one live request between a pair, in either direction
CREATE UNIQUE INDEX chat_requests_pending_pair_idx
  ON chat_requests (least(requester_id, recipient_id), greatest(requester_id, recipient_id))
  WHERE status = 'pending';

-- Exactly one direct conversation per pair, regardless of who asked
CONSTRAINT direct_pair_ordered CHECK (user_a_id < user_b_id)
CREATE UNIQUE INDEX direct_conversation_pair_idx ON direct_conversation_keys (user_a_id, user_b_id);

-- A person appears once in an address book
CREATE UNIQUE INDEX contacts_owner_user_idx
  ON contacts (owner_id, contact_user_id) WHERE contact_user_id IS NOT NULL;

-- The gate, in the schema rather than only in code
message text NOT NULL DEFAULT '' CHECK (char_length(message) <= 280)
```

## Permissions

| Action | Rule |
| ------ | ---- |
| Search | Exact handle: any active user. Substring: shared organizations only. |
| Send a request | Any active user; not yourself; no pending request; no existing conversation. |
| Respond | **Recipient only.** |
| Withdraw | Requester only, while pending. |
| Read or send messages | Participants only (`assertParticipant`). |
| Delete a message | Its sender only. |
| Read or write a contact | Its owner only — others get `404`, not `403`. |

**Not organization-scoped.** See
[ADR-001](../architecture/decisions/ADR-001-social-features-are-not-organization-scoped.md).

## Error handling

| Situation | Response | UI |
| --------- | -------- | -- |
| Note over 280 chars | `400` | Live counter blocks it first |
| Duplicate request | `409` "You already have a pending request" | Inline banner |
| Conversation already exists | `409` "You can already message this person" | Inline banner |
| Not the recipient | `403` | Inline banner |
| Not a participant | `403` | Inline banner |
| Contact of another owner | `404` | Inline banner |
| Offline | `offline` code | Worded distinctly from a server error, with Retry |

## Dependencies

Messaging depends on `identity` (users), `access-control` (membership),
`events` (outbox), and the worker (notifications). Contacts depends on
`identity` and is **written by messaging** during acceptance — the only
cross-module write in this feature, and it happens inside the acceptance
transaction so the two can never disagree.

## Configuration

None specific. Uses the standard database, Redis and JWT configuration.

## Testing

`tests/e2e/messaging-and-contacts.sh` — 49 assertions, three users in three
separate organizations.
`tests/e2e/realtime-messaging.sh` — 16 assertions driving a real WebSocket
through the UI's own origin: handshake, push content, dedupe, routing data,
offline retrieval, and that a sender is never notified of their own message.
`modules/contacts/contacts.service.test.ts` — 12 presence cases.

**Run both E2E scripts after any change to a query, the gateway, or a proxy
configuration in either module.**

## Realtime delivery and notifications

A sent message reaches the recipient over the gateway, with polling kept only
as a fallback:

```text
A sends ──► POST /messaging/conversations/:id/messages
                │ ONE TRANSACTION
                ├── messages row
                ├── conversations.last_message_at / preview
                └── domain_events: chat.message_sent
                            │
                    Worker  ├── reads the message body for a preview
                            └── createNotification(recipient)
                                      │
                            Redis `realtime:notifications`
                                      │
                            /ws gateway ──► deliverToUser(recipientId)
                                      │
                    Shell RealtimeClient (always on, app-independent)
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        ▼                             ▼                             ▼
  in-app notification         Messenger open?                 Messenger closed
       centre                 → append live,                  or tab hidden?
    (always)                    mark read                     → OS notification
```

**The socket belongs to the shell, not to Messenger.** A closed window is an
unmounted component; if the connection lived in the app, a message could only
be noticed while the user was already looking at it.

Three properties worth keeping:

* **No double announcement.** A system notification is raised only when the
  user cannot already see the message — Messenger closed, minimised, not the
  focused window, or the tab in the background.
* **Deduplicated.** `RealtimeClient` drops repeat notification ids (reconnects,
  two tabs), and each conversation uses one notification `tag`, so a burst
  updates in place instead of stacking.
* **Nothing is lost.** The socket is an accelerator, never the record. Messages
  live in PostgreSQL, so a recipient who was offline sees them — with unread
  counts — the moment they open the app.

### Permission

OS notifications need permission, which browsers only grant from a user
gesture. It is requested from **Notifications panel → Enable desktop alerts**,
never automatically on load: an origin that asks unprompted can be permanently
blocked.

### Limits of the browser

If the whole browser is closed, no page is running and no socket exists, so no
notification can be raised. Messages are still stored and appear on next open.
Delivering to a fully closed browser needs Web Push (VAPID keys, a push
service, and a service-worker `push` handler) — not implemented.

## Known limitations
* Group conversations: schema supports `kind = 'group'`; no API to create one.
* Threads, reactions and mentions: columns exist, no endpoints.
* Attachments: `messages.attachments` exists, not wired to `/files`.
* Blocking, muting a person, and deleting a conversation: not implemented.
* Contact photos come only from a user's real avatar; there is no upload.

## Troubleshooting

| Symptom | Cause |
| ------- | ----- |
| Messages only appear after switching conversations | The open thread is not being refetched. This was the original defect: `loadMessages` ran only on selection change. |
| No realtime, everything works on a delay | The socket is not connecting. In development check the Vite `/ws` proxy has `ws: true`; in production check the nginx `/ws` block. |
| No OS notifications | Permission not granted — Notifications panel → Enable desktop alerts. Nothing appears if the browser itself is closed. |
| Notification appears while the user is reading the chat | The visibility rule in `useRealtimeNotifications` is being bypassed. |
| Search finds nobody | Substring search only spans shared organizations — use the exact username or email. |
| Accept returns 404 | The request id is wrong. This was TASK-020: `r.id` clobbered by `u.id` in the list query. Check aliasing. |
| One side sees the conversation, the other does not | Organization scoping has crept back into a messaging query. See ADR-001. |
| No notifications | The worker is not running, or an event has no subscriber in `workers/handlers.ts`. |
| Everyone shows online forever | A read is using `user_presence.status` directly instead of `effectivePresence`. See ADR-003. |

## Change history

| Date | Change |
| ---- | ------ |
| 2026-08-13 | Contacts and presence module added; Contacts app moved off mock data; migration `0005` |
| 2026-08-13 | TASK-001/002/020 fixed: search, conversation listing, request-id collision |
| 2026-08-13 | TASK-004: chat events given notification handlers |
| Earlier | Messaging module and migration `0004`; Messenger rebuilt on the API |
