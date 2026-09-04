# ADR-001 — Social features are scoped by participation, not by organization

* **Status** Accepted, 2026-08-13
* **Supersedes** The original messaging implementation, which scoped everything
  by `organization_id`

## Problem

Direct messaging, chat requests, contacts and presence were all scoped to the
caller's organization, in line with CLAUDE.md §15 ("core entities should
contain an organization identifier"). The result was a feature that could not
be used at all:

* directory search returned an empty list for every query;
* if a request had somehow been sent and accepted, the conversation was visible
  to the person who sent it and invisible to the person who accepted it;
* incoming requests were never listed for the recipient.

## Context

Registration provisions each new user a **private `personal` organization**
(`identity.service.ts`). On the live system at the time of the audit: 6 users,
6 organizations, all of type `personal`, one member each.

So "users in the same organization" describes almost nobody. Two people who
sign up independently are never co-members, and the product offers no other
route to a shared tenant.

Multi-tenancy was designed around resources a company owns — files, mail,
meetings, audit trails. A direct conversation is not owned by a company. It is
owned by the two people in it, who may be in different companies, or in no
company at all.

## Options considered

**A. Put every user in one shared organization.** Destroys multi-tenancy. Files
and mail would leak across every customer. Rejected immediately.

**B. Require an invitation into a shared organization before chatting.** Keeps
the model pure, but means two individuals cannot message each other without an
administrator provisioning a tenant. That is not a messenger.

**C. Scope social resources by participation; keep tenant scoping for tenant
resources.** Chosen.

**D. Make discovery fully global.** Would fix reachability but turn a two-
character query into a dump of every user on the platform.

## Decision

Each resource is scoped by the boundary that actually owns it:

| Resource | Boundary | Enforced by |
| -------- | -------- | ----------- |
| Files, shares, mail, meetings, audit | `organization_id` | `access-control.ts` |
| Conversations, messages | participation | `conversation_participants` |
| Chat requests | involvement | `requester_id` / `recipient_id` |
| Contacts | ownership | `owner_id` |
| Presence | public to authenticated callers, bounded by lookup | explicit id list |

Discovery splits reachability from enumerability:

* **exact** `username` or `email` → platform-wide, because a username has to
  work as an address;
* **substring** → only among people sharing an organization with the caller.

`organization_id` remains on conversations and messages as originating context
for audit. It is recorded, not enforced.

## Consequences

**Good.** Messaging works between any two users. Multi-tenant isolation is
untouched for the resources that need it — verified: a user still gets `404`
on another tenant's file. Group conversations and future organization-wide
channels fit the participation model without further change.

**Costs.** Two scoping rules now exist in one codebase, so the wrong one can be
chosen — mitigated by the table above, the note in `docs/guides/developer-guide.md`, and
`tests/e2e/messaging-and-contacts.sh`, which fails if organization scoping
creeps back. Exact-handle lookup also confirms whether a username exists; that
is inherent to being addressable, and it is rate limited.

**Do not** "restore consistency" by adding `WHERE organization_id = …` back to
a messaging query. That is the original defect.

## Verification

`tests/e2e/messaging-and-contacts.sh` — 49 assertions with three users in three
separate personal organizations, including the negative case that substring
search does not enumerate foreign tenants.
