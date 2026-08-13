# ADR-002 — Authentication strategy and service credentials

* **Status** Accepted, 2026-08-13
* **Amends** The original assumption that inbound-mail endpoints were protected
  by network placement

## Problem

Two distinct callers authenticate to this API:

1. **People**, through a browser, holding a session.
2. **The SMTP gateway**, relaying inbound mail, which by definition has no
   session — the message came from the internet, not from a signed-in user.

The second case was handled by assuming the endpoints were unreachable from
outside. That assumption was false, and the audit demonstrated it: with no
credential of any kind, `POST /api/v1/mail/receive` delivered a message into a
real user's inbox with an attacker-chosen `from` address, returning `201`.

## Context

The API is published on a host port in both the development and production
Compose stacks. Nothing in the deployment enforces the isolation the code's
comment claimed. `POST /mail/auth` — which verifies a user's password — was
open on the same public surface.

## Decision

### Users: JWT access token + rotating refresh token

Access token is a 1-hour JWT carrying user, organization and session. Refresh
token is opaque, 30 days, **rotated on every use**, and stored only as a
SHA-256 hash, so a database disclosure does not yield usable tokens. Changing
or resetting a password revokes every session.

Both are held in `localStorage` and refreshed transparently by
`platform/api/http.ts`.

### Services: a shared secret, presented explicitly

Endpoints with no user session authenticate the *service*:

| Endpoint | Caller |
| -------- | ------ |
| `POST /mail/receive` | `drive-osx-mail` |
| `POST /mail/auth` | `drive-osx-mail` |

`MAIL_GATEWAY_TOKEN`, sent as `X-Mail-Gateway-Token`, compared in constant time
(`platform/authentication/mail-gateway.ts`). The API refuses to boot in
production without it. Development permits an unset token so a fresh checkout
can receive mail, and warns once; a *wrong* token is rejected in both modes.

## Consequences

**Good.** Mail injection now requires the secret. The credential-check endpoint
is off the public surface. The failure is loud at boot rather than silent at
runtime. There is a reusable pattern for the next service-to-service endpoint.

**Costs.** One more value that must agree across two `.env` files — the first
thing to check when mail stops working, and covered by `./scripts/check-env.sh`.
A shared bearer secret does not identify *which* gateway instance called; if
that ever matters, this becomes mTLS or a signed assertion.

## Accepted risk: tokens in `localStorage`

Any script on the origin can read them. Accepted because the UI has **no XSS
sink** — `dangerouslySetInnerHTML` appears nowhere, and no user content reaches
`innerHTML` or `eval` — and this is the standard SPA trade-off.

The upgrade path, when it is worth the cost: refresh token in an `HttpOnly`,
`SameSite=Strict` cookie, access token in memory only. That requires CSRF
protection on every mutating route and a cookie-aware CORS configuration, which
is a larger change than it appears.

**Revisit this if** any `dangerouslySetInnerHTML` is introduced, or if
user-authored HTML is ever rendered. At that point the trade-off no longer
holds.

## Not decided here

MFA, SSO and SCIM are required by CLAUDE.md §28/§34 and are not implemented.
The session model above does not obstruct them: MFA becomes a step between
credential check and token issue, and SSO becomes another way to reach the same
issuance point.
