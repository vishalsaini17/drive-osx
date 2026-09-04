# ADR-003 — Presence is derived on read, not trusted as stored

* **Status** Accepted, 2026-08-13

## Problem

Contacts shows whether someone is online. The obvious implementation — write
`online` on sign-in, `offline` on sign-out, read the column — is wrong in the
common case: browsers close without a clean sign-off. A crashed tab, a closed
laptop, a dropped connection or a killed process all leave `online` in the
table permanently.

The result is a contact list confidently reporting that someone is available
when they have not been there for days. That is worse than showing nothing,
because a user acts on it.

## Decision

Presence is a **heartbeat plus a read-time decision**.

* The shell posts `/contacts/presence/heartbeat` every 45 seconds while the
  desktop is open and visible, updating `status` and `last_seen_at`.
* Every read resolves the effective status through `effectivePresence`: a
  stored status older than `PRESENCE_TTL_SECONDS` (120) reads as `offline`,
  whatever the column says.
* An explicit sign-off (`/contacts/presence/offline`, and `pagehide`) sets
  `offline` immediately, so a clean exit is instant rather than waiting out the
  TTL.

The 45-second beat inside a 120-second TTL means a single missed request does
not flip a user offline for everyone watching.

## Why the TTL is on read, not a sweeper job

A background job marking stale rows offline would work, but it adds a scheduled
task, and correctness would then depend on it having run recently. Deciding on
read means presence is correct *by construction* — there is no window in which
the answer is stale because a job is late. It also costs nothing: the
comparison is on a row already being fetched.

## Consequences

**Good.** A user who closes their laptop shows offline within two minutes with
no cleanup process. The rule is one exported pure function, so it is tested
without a database or a clock (12 cases, including clock skew, unparseable
timestamps and non-`online` statuses decaying too). Every surface — contact
list, messenger sidebar, anything later — gets the same answer, because they
all call it.

**Costs.** Up to two minutes of staleness after an unclean exit. Acceptable:
presence is ambient information, not a lock. Every reader must go through
`effectivePresence` — reading `user_presence.status` directly reintroduces the
bug, which is why `presenceFor` and the contacts query both call it.

**Heartbeats cost requests.** One per user per 45 seconds, suppressed while the
tab is hidden. If that becomes significant, the beat moves onto the existing
WebSocket gateway, where connection liveness replaces the polling entirely —
the read-time decay rule stays the same.

## Implementation

* `modules/contacts/contacts.service.ts` — `effectivePresence`, `heartbeat`,
  `goOffline`, `presenceFor`
* `platform/contacts/usePresenceHeartbeat.ts` — session-wide, mounted once in
  the shell, **not per application**
* `modules/contacts/contacts.service.test.ts` — the decay rule
