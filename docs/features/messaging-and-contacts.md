# Messaging and Contacts

## Purpose

Direct messaging between users, gated by a request the recipient must accept,
with an address book that fills itself as a side effect of accepting. Direct
conversations have since grown group chat, attachments, reactions, and
per-message actions (pin, forward, delete, react) on top of the same request
gate and permission model.

## Business requirements

1. Find people by username; no fabricated directory.
2. Send a **short note only** — 280 characters — until the request is accepted.
3. The recipient accepts or rejects.
4. Acceptance creates the conversation **and** adds each person to the other's
   contacts.
5. No normal messaging before acceptance.
6. Contacts show real connection status.
7. Everything persists in PostgreSQL. No mock data anywhere.
8. A group can only be built from people already in the creator's own
   contacts — the request gate that keeps direct messaging opt-in extends to
   groups by construction (see [Group conversations](#group-conversations)).

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

## Group conversations

Added 2026-08-24. A group is a `conversations` row with `kind = 'group'`,
built entirely on the existing schema plus two new columns — no parallel
group data model.

* **Create** — `POST /messaging/groups` `{title, memberUserIds[]}`.
  `createGroupConversation` (`messaging.service.ts`) requires every
  `memberUserId` to already be a contact of the creator (`contacts` table,
  `owner_id`/`contact_user_id`) — group creation cannot be used to reach
  someone who hasn't gone through the request flow. 2–200 members excluding
  the creator, so a group has at least three people.
* **Admin-gated actions** — rename, set description, set avatar, add a
  member. `assertGroupAdmin` requires
  `conversation_participants.role IN ('owner', 'admin')`. Everyone can still
  view, message, pin, react, and leave regardless of role.
  * Rename and description reuse the pre-existing `conversations.topic`
    column — no schema change for those two.
  * Avatar (`POST .../avatar`) stores a plain string — an emoji or a
    `http…` URL — on the new `conversations.avatar_url` column, the same
    convention as `users.avatar_url`. **This is not a file upload**; there is
    no object-storage path for group avatars.
  * Adding a member requires the new member to already be a contact of the
    admin who adds them — same boundary as group creation.
* **Leave** — `POST .../leave` deletes the caller's participant row outright
  (no revive, unlike the delete-chat behaviour below). If the owner leaves,
  ownership transfers automatically to the longest-standing admin, or failing
  that the longest-standing member.
* **Report** — `POST .../report` writes an audit-log entry
  (`group.reported`) via `recordAuditDetached`. There is no moderation
  queue or review UI behind it yet — it is a record, not a workflow.
* **Favourite** — `POST .../favourite` / `.../unfavourite` generalizes
  favouriting from contacts to any conversation, because a group has no
  single contact row to hang a favourite off of. New
  `conversation_participants.is_favourite` column (direct-chat favouriting
  still lives on the pre-existing `contacts` row).
* **Blocking does not apply to groups.** `assertCanMessage` explicitly skips
  the block check when `conversation.kind === 'group'` — a block between two
  members does not affect the group for anyone.

## Attachments and voice messages

Added 2026-08-24 (attachments), extending voice-message plumbing from
2026-08-21.

* **One generic endpoint** — `POST /messaging/conversations/:id/attachment`
  (multipart, field `file`) handles documents, images, and video together;
  kind is inferred from MIME type (`image/*` → `image`, `video/*` → `video`,
  else `file`) rather than routed by three separate endpoints.
* **Voice messages** are a separate endpoint (`POST .../voice-message`,
  field `audio`) that now shares the same upload core as file attachments —
  originally its own 10 MB path, folded into the shared 25 MB limit.
* **Limit** 25 MB, enforced both by `multer` in the route and
  `MAX_ATTACHMENT_BYTES` in the service. Rate-limited at 120 uploads/60s per
  actor.
* **Storage** bytes land in object storage first
  (`objectKeys.chatAttachment(orgId, conversationId, messageId)`); only the
  storage key is persisted, in `messages.attachments` (jsonb). Reads resolve
  a signed URL with a 1-hour expiry — attachments are never served
  unsigned.
* Conversation-list previews are kind-specific: `📷 Photo`, `🎥 Video`,
  `📎 {filename}`.
* Same `assertCanMessage` gate as text messages — membership, participant
  status, and (for direct chats) the block check.

## Message actions: react, pin, forward, delete, links

Added 2026-08-24, on top of `reply_to_id` and `reactions` columns that had
existed unused in the schema since migration `0004`.

* **React** — `POST /messages/:id/react` `{emoji}` (≤16 chars). One
  reaction per user per message: setting a new emoji replaces the caller's
  previous one, tapping the same emoji again clears it. The read-modify-write
  locks the row (`FOR UPDATE`) to avoid races. Stored in the pre-existing
  `messages.reactions` jsonb column.
  **There are no stickers.** Despite an early commit message claiming
  "emojis and stickers," no sticker feature — server or client — exists
  anywhere in either repository's history; only text reactions were built.
* **Pin / unpin** — `POST /messages/:id/pin` / `/unpin`. Any participant can
  pin, unlike the group-identity actions above — a pin only surfaces
  something already visible in the thread. New `messages.pinned_at` column
  with a partial index. `GET /conversations/:id/pinned` lists pinned
  messages, newest first.
* **Forward** — `POST /messages/:id/forward` `{conversationIds: string[]}`
  (1–20 targets). Copies the body and attachments **by reference** (same
  storage key, not re-uploaded) into a new, `forwarded = true` message per
  target. Does not carry over `replyToId`/`threadParentId`. Runs
  `assertCanMessage` per target, so forwarding into a conversation with
  someone who blocked you still fails.
* **Delete, two modes** — `DELETE /messages/:id?mode=me|everyone` (default
  `everyone`):
  * `mode=me` — any participant, including on messages they didn't send.
    Appends the caller's id to `messages.deleted_for` (a `uuid[]`); every
    listing query filters it out for that participant only. Nobody else's
    view changes.
  * `mode=everyone` — **sender only**. Tombstones the row (`body`,
    `attachments`, `reactions` cleared, `pinned_at` cleared, `deleted_at`
    set) but the row stays in the thread for everyone, rendered as "This
    message was deleted" — distinct from `deleted_for`, which removes the
    row from view entirely for one person.
* **Copy** is a client-side clipboard action against the existing message
  body. There is no server-side "copy" endpoint — nothing to document
  beyond the frontend.
* **Links** — `GET /conversations/:id/links` regex-extracts URLs out of
  message bodies for the Links tab of the conversation-details panel; no
  separate link-tracking table.

## Blocking, favourites, and conversation lifecycle

Added 2026-08-21–22.

* **Block / unblock** — `POST /contacts/:id/block` / `/unblock`. New
  `contacts.is_blocked` column. `isBlockedBetween` checks either direction
  of the pair and is enforced when sending a chat request and when sending a
  message in an existing direct conversation. **Not enforced** in group
  chats (see above) and **not enforced** in directory search — a blocked
  user still appears in search; blocking only stops requests and messages.
* **Delete a conversation** (per-participant) — `DELETE
  /messaging/conversations/:id`. Sets `conversation_participants.deleted_at`
  *and* `history_cleared_at`. `deleted_at` hides the thread from the list
  and auto-clears the moment either side sends a new message, so the thread
  reappears; `history_cleared_at` is a permanent per-participant cutoff that
  never auto-clears, and every message/media listing filters out anything
  created before it for that participant. (`history_cleared_at` was added a
  day after `deleted_at` alone, because a new message used to resurrect the
  *entire* pre-deletion history along with the thread.)
* **Clear history** (distinct from delete) — `POST
  /messaging/conversations/:id/clear`. Sets only `history_cleared_at` — the
  thread stays in the sidebar, just empty until new messages arrive.
* **Starting a chat with someone you'd deleted** —
  `GET /conversations/with/:userId` clears `deleted_at` (not
  `history_cleared_at`), so re-opening a hidden thread doesn't collide with
  the "you can already message this person" conflict check.
* **"Save shared media"** is a read-only browse —
  `GET /conversations/:id/media` — of past attachments, surfaced as the
  Media tab of the conversation-details panel. There is no explicit
  save-to-Drive action; nothing is copied out of the conversation.
* **Voice/video calling is not a messaging feature.** The chat panel's call
  buttons create and start a real Meeting via the pre-existing, separate
  `meetings` module, post the meeting code into the chat as a normal text
  message, and open the Meet app. No WebRTC signalling was added to
  messaging itself — calling is implemented entirely by delegating to
  Meetings.

## Delivery status and read receipts

Added 2026-08-21.

* New `conversation_participants.last_delivered_at`, alongside the
  pre-existing `last_read_at`. `last_delivered_at` bumps whenever a
  participant fetches messages (fetching = delivery); `last_read_at` (and
  `last_delivered_at`) bump on `POST .../read`.
* Per-message status is computed on read, not stored:
  `read` if every other participant's `last_read_at` is at or after the
  message's `created_at`, `delivered` if at least one is, else `sent`. Only
  attached to the sender's own messages. The "all read / any delivered"
  split is written to generalize cleanly if group read receipts are added
  later — today a direct conversation only ever has one "other" participant.

## Frontend

| Piece | Location |
| ----- | -------- |
| Messenger | `src/apps/messages/index.tsx` |
| Messenger theme | `src/apps/messages/useMessengerTheme.ts` |
| Emoji/sticker-label picker | `src/apps/messages/EmojiStickerPicker.tsx` |
| Contact details panel | `src/apps/messages/ContactDetailsPanel.tsx` |
| Group details panel | `src/apps/messages/GroupDetailsPanel.tsx` |
| Shared media/docs/links (used by both panels above) | `src/apps/messages/SharedMediaSection.tsx` |
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

The "Stickers" tab in `EmojiStickerPicker.tsx` sends large emoji as an
immediate message, not real sticker artwork — there is no Giphy/Tenor
integration or key configured. Treat it as a labeling choice in the UI, not a
distinct feature from reactions/emoji.

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
POST   /messaging/requests                       { recipientId, message ≤280 }
POST   /messaging/requests/:id/respond           { action: accept | reject }
DELETE /messaging/requests/:id

GET    /messaging/conversations
GET    /messaging/conversations/with/:userId
GET    /messaging/conversations/:id/messages?limit=&before=
POST   /messaging/conversations/:id/messages     { body, replyToId?, threadParentId?, mentions? }
POST   /messaging/conversations/:id/attachment   multipart, field "file" — image/video/document (25MB)
POST   /messaging/conversations/:id/voice-message multipart, field "audio" (25MB)
POST   /messaging/conversations/:id/read
DELETE /messaging/conversations/:id              per-participant delete (deleted_at + history_cleared_at)
POST   /messaging/conversations/:id/clear        history_cleared_at only, thread stays visible
GET    /messaging/conversations/:id/media
GET    /messaging/conversations/:id/links
GET    /messaging/conversations/:id/pinned

POST   /messaging/messages/:id/react             { emoji ≤16 chars } — toggle
POST   /messaging/messages/:id/pin
POST   /messaging/messages/:id/unpin
POST   /messaging/messages/:id/forward           { conversationIds: string[] (1–20) }
DELETE /messaging/messages/:id?mode=me|everyone  (default everyone)

POST   /messaging/groups                         { title, memberUserIds[] (2–200) }
POST   /messaging/conversations/:id/rename        admin only
POST   /messaging/conversations/:id/description   admin only, reuses conversations.topic
POST   /messaging/conversations/:id/avatar        admin only, string (emoji or URL), not an upload
POST   /messaging/conversations/:id/members       admin only, new member must be admin's contact
POST   /messaging/conversations/:id/leave
POST   /messaging/conversations/:id/report        writes audit log only, no moderation queue
POST   /messaging/conversations/:id/favourite
POST   /messaging/conversations/:id/unfavourite

GET    /contacts?search=&favourites=
POST   /contacts                                 { displayName, … } or { contactUserId }
GET    /contacts/:id
PATCH  /contacts/:id
DELETE /contacts/:id
POST   /contacts/:id/block
POST   /contacts/:id/unblock
POST   /contacts/presence/heartbeat              { status?, statusText?, statusEmoji? }
POST   /contacts/presence/offline
POST   /contacts/presence/lookup                 { userIds: [] }
```

**In progress, not yet committed** (`drive-osx-api`: `messaging.routes.ts`,
`messaging.service.ts`; `drive-osx-ui`: `src/apps/messages/index.tsx`,
`src/platform/messaging/MessagingService.ts`): `PATCH
/messaging/messages/:id` to edit a sent text message (sender only, ≤8000
chars, blocked on messages that carry an attachment or are already deleted).
No accompanying migration — `messages.edited_at`/`is_edited` already existed
unused since migration `0004`. Do not treat this as shipped until it lands
in a commit; re-check this section then.

## Database

Migration `0004`: `chat_requests`, `conversations`, `conversation_participants`,
`direct_conversation_keys`, `messages`, `contacts`, `user_presence` — including
columns (`reactions`, `reply_to_id`, `edited_at`) that sat unused until the
2026-08-21–24 work gave them a service layer.
Migration `0005`: contact detail fields.
Migration `0006`: `contacts.is_blocked`; `conversation_participants.deleted_at`.
Migration `0007`: `conversation_participants.history_cleared_at` (added the
same day `0006` proved insufficient — see "Delete a conversation" above).
Migration `0008`: `conversation_participants.last_delivered_at`.
Migration `0009`: `conversation_participants.is_favourite`.
Migration `0010`: `conversations.avatar_url`.
Migration `0011`: `messages.pinned_at` + partial index `messages_pinned_idx`.
Migration `0012`: `messages.forwarded`, `messages.deleted_for uuid[]`.

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
| Send a request | Any active user; not yourself; no pending request; no existing conversation; not blocked either direction. |
| Respond | **Recipient only.** |
| Withdraw | Requester only, while pending. |
| Read or send messages | Participants only (`assertParticipant`); blocked pair cannot message in a **direct** conversation — block is not checked in groups. |
| React, pin, forward, view media/links/pinned | Any participant. |
| Delete a message (`mode=me`) | Any participant, any message. |
| Delete a message (`mode=everyone`) | Its sender only. |
| Rename, set description/avatar, add member | Group `owner`/`admin` only (`assertGroupAdmin`). |
| Leave a group | Any participant; ownership auto-transfers if the owner leaves. |
| Create a group / add a member | Only with people already in the actor's own contacts. |
| Read or write a contact | Its owner only — others get `404`, not `403`. |
| Block / unblock | The contact's owner only. |

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
| Not a group admin | `403` | Inline banner |
| Attachment over 25MB | `400`/`413` | Rejected client-side first where the picker knows the size |
| Contact of another owner | `404` | Inline banner |
| Offline | `offline` code | Worded distinctly from a server error, with Retry |

## Dependencies

Messaging depends on `identity` (users), `access-control` (membership),
`events` (outbox), `storage` (attachments), and the worker (notifications).
Contacts depends on `identity` and is **written by messaging** during
acceptance — the only cross-module write in this feature, and it happens
inside the acceptance transaction so the two can never disagree. Calling
from the chat panel depends on the separate `meetings` module (see
[Blocking, favourites, and conversation lifecycle](#blocking-favourites-and-conversation-lifecycle));
messaging does not implement calling itself.

## Configuration

None specific. Uses the standard database, Redis, JWT and object-storage
configuration. If this deployment is reached over a LAN or the internet by
more than one machine, `STORAGE_PUBLIC_URL` must point at a browser-reachable
host, not `localhost`, or chat attachments (and every other signed-URL
download) will fail to load for everyone but the person on the host machine
— see the comment on that variable in `.env.example`.

## Testing

`tests/e2e/messaging-and-contacts.sh` — 49 assertions, three users in three
separate organizations.
`tests/e2e/realtime-messaging.sh` — 16 assertions driving a real WebSocket
through the UI's own origin: handshake, push content, dedupe, routing data,
offline retrieval, and that a sender is never notified of their own message.
`modules/contacts/contacts.service.test.ts` — 12 presence cases.

**Run both E2E scripts after any change to a query, the gateway, or a proxy
configuration in either module.** Neither suite yet covers group
conversations, attachments, reactions, pin/forward/delete modes, or
blocking — added 2026-08-21–24 without accompanying test coverage. Add
assertions there before relying on this feature set being regression-safe.

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

* Message editing: `PATCH /messages/:id` exists only as uncommitted,
  in-progress work — see [APIs](#apis). Not shipped.
* Stickers: no real sticker/GIF feature (Giphy, Tenor, or otherwise) exists;
  the "Stickers" tab sends large emoji as messages.
* Group size and message-rate limits beyond the 2–200 member cap and the
  120/60s upload rate limit are not enforced.
* Group avatars accept any string (emoji or URL) with no upload path and no
  validation that a pasted URL resolves to an image.
* Reporting a group only writes an audit-log entry; there is no moderation
  queue or reviewer workflow behind it.
* Blocking is not enforced in group chats or in directory search — only in
  direct requests and direct messaging.
* No Web Push — notifications require the browser (a tab, even hidden) to be
  running.
* Contact photos come only from a user's real avatar; there is no upload
  (group avatars are separate, see above).
* Neither E2E suite covers the 2026-08-21–24 additions (groups, attachments,
  reactions, pin/forward/delete, blocking) — see [Testing](#testing).

## Troubleshooting

| Symptom | Cause |
| ------- | ----- |
| Messages only appear after switching conversations | The open thread is not being refetched. This was the original defect: `loadMessages` ran only on selection change. |
| No realtime, everything works on a delay | The socket is not connecting. In development check the Vite `/ws` proxy has `ws: true`; in production check the nginx `/ws` block. |
| No OS notifications | Permission not granted — Notifications panel → Enable desktop alerts. Nothing appears if the browser itself is closed. |
| Notification appears while the user is reading the chat | The visibility rule in `useRealtimeNotifications` is being bypassed. |
| Search finds nobody | Substring search only spans shared organizations — use the exact username or email. A blocked user still appears in search; blocking only stops requests/messages. |
| Accept returns 404 | The request id is wrong. This was TASK-020: `r.id` clobbered by `u.id` in the list query. Check aliasing. |
| One side sees the conversation, the other does not | Organization scoping has crept back into a messaging query. See ADR-001. |
| No notifications | The worker is not running, or an event has no subscriber in `workers/handlers.ts`. |
| Everyone shows online forever | A read is using `user_presence.status` directly instead of `effectivePresence`. See ADR-003. |
| Deleted thread comes back with its full old history | Only `deleted_at` was cleared on a new message; `history_cleared_at` must also be respected by the listing query (see "Delete a conversation"). This was the exact bug `0007` fixed — watch for a regression if the delete/clear queries are touched again. |
| Group message reaches someone who blocked the sender | Expected — blocking is intentionally not enforced in groups. Not a bug. |
| Attachment upload silently fails over 25MB with a generic error | Client should reject oversized files before the request; if it isn't, check the picker's size check against `MAX_ATTACHMENT_BYTES`. |

## Change history

| Date | Change |
| ---- | ------ |
| 2026-08-24 | Group conversations (create/rename/describe/avatar/add-member/leave/report/favourite); attachments (image/video/document, 25MB); message reactions; pin/unpin and pinned list; forward; two-mode delete (`me`/`everyone`); links tab. Migrations `0009`–`0012`. |
| 2026-08-24 | Frontend: group creation UI, attachment/camera/voice send menu, emoji picker (no real stickers), contact and group details panels, shared media/docs/links tabs, per-message action menu (react/reply/copy/forward/pin/delete), chat "call" buttons delegating to the Meetings module. |
| (in progress, uncommitted) | `PATCH /messages/:id` to edit a sent text message — see [APIs](#apis). |
| 2026-08-21–22 | Blocking (`contacts.is_blocked`); per-participant conversation delete and clear-history, with the two-column (`deleted_at` + `history_cleared_at`) fix after a same-day bug; delivery/read-receipt status (`last_delivered_at`); `.env.example` comment clarifying `STORAGE_PUBLIC_URL` must be browser-reachable, not `localhost`, in multi-user deployments. Migrations `0006`–`0008`. |
| 2026-08-13 | Contacts and presence module added; Contacts app moved off mock data; migration `0005` |
| 2026-08-13 | TASK-001/002/020 fixed: search, conversation listing, request-id collision |
| 2026-08-13 | TASK-004: chat events given notification handlers |
| Earlier | Messaging module and migration `0004`; Messenger rebuilt on the API |
