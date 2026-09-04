# Package & Tooling Inventory

Every package, library, framework, and infrastructure tool this project
depends on, grouped by where it's used. Licenses were read from the npm
registry (or, for base images, from the upstream project's own license file)
at the time this document was written — not assumed from memory. Where a
license or cost status genuinely could not be confirmed this way, it's marked
**Verify** rather than guessed.

"Paid / Free" describes the package/tool itself, not the cloud infrastructure
it might talk to (e.g. the AWS SDK is free; an AWS account you point it at is
not).

- **Type** — `Production` (ships/runs in the deployed service) or
  `Development` (build-time/type-checking/test tooling only).
- Versions are as pinned in the relevant `package.json` / `docker-compose*.yml`,
  not necessarily what's currently installed.

---

<details>
<summary><strong>Architecture &amp; Infrastructure Tools</strong> — the non-npm layer (<code>docker-compose.yml</code>, <code>docker-compose.dev.yml</code>, Dockerfiles)</summary>

| Tool | Purpose | License | Paid / Free |
| --- | --- | --- | --- |
| Docker Engine / Docker CLI | Builds and runs every service as a container; `docker-compose.yml` is the deployment unit. | Apache-2.0 | Free — **Verify** if your team uses Docker Desktop instead of Engine directly: Desktop has separate paid-subscription terms for larger companies. |
| Docker Compose | Orchestrates the multi-service stack (`docker-compose.yml` + `docker-compose.dev.yml` overlay). | Apache-2.0 | Free |
| `node:24.13-alpine` | Base image for the API, worker, mail gateway, and the UI's build stage. | MIT (Node.js) | Free |
| `nginxinc/nginx-unprivileged:1.27-alpine` | Serves the built UI and proxies `/api` and `/ws` to the API in production. | Custom permissive (2-clause-BSD-style nginx license) | Free — NGINX Plus is a separate paid product from F5/NGINX Inc., not what's used here. |
| `postgres:17.2-alpine` | Primary system-of-record database (users, orgs, files, permissions, etc. per `CLAUDE.md`). | PostgreSQL License (permissive, OSI-approved) | Free |
| `redis:7.4-alpine` | Cache, sessions, rate limiting, job queue (`ioredis` client, `noeviction` policy). | **RSALv2 / SSPLv1** (dual, source-available — not an OSI-approved open-source license as of the 7.4 line) | **Verify** — free for most internal/self-hosted use, but neither RSALv2 nor SSPLv1 is a standard open-source license; confirm your usage (especially if you ever offer this stack as a hosted service to others) is covered. |
| `minio/minio:RELEASE.2025-09-07T16-13-09Z` | S3-compatible object storage for uploaded files (`CLAUDE.md` §11 — binaries never go in Postgres). | AGPLv3 | Free — copyleft (AGPL requires sharing modifications if you distribute/host a modified MinIO); MinIO Inc. sells enterprise support/features (AIStor) separately, not used here. |
| Git | Version control; each of the four services also carries its own nested `.git`. | GPL-2.0 | Free |

</details>

<details>
<summary><strong>Root</strong> — process supervisor (<code>package.json</code>)</summary>

| Type | Package | Purpose | License | Paid / Free |
| --- | --- | --- | --- | --- |
| Production | `pm2` | Boots and supervises the API/worker/mail processes per `ecosystem.config.js`. | AGPL-3.0 | Free — Keymetrics sells a separate hosted monitoring dashboard (PM2 Plus) on top; not used here. |
| Production | `pm2-runtime` | Invoked by the root `start` script. | **UNLICENSED** | **Verify** — this npm name resolves to a small third-party wrapper (`alxndrsn/alias-in-wonderland`, not Keymetrics), with no license granted, whose entire implementation is a shell script that re-fetches and runs `pm2`'s own bundled `pm2-runtime` binary via `npx --yes` on every start. `pm2` already ships this exact binary itself — worth confirming whether this dependency is even needed. |

</details>

<details>
<summary><strong>drive-osx-api</strong> — backend (<code>drive-osx-api/package.json</code>)</summary>

| Type | Package | Purpose | License | Paid / Free |
| --- | --- | --- | --- | --- |
| Production | `express` | HTTP server and routing for the whole API. | MIT | Free |
| Production | `pg` | PostgreSQL driver — the connection to the system-of-record database. | MIT | Free |
| Production | `ioredis` | Redis client for cache, sessions, and rate limiting. | MIT | Free |
| Production | `@aws-sdk/client-s3` | S3-compatible object storage client (talks to MinIO). | Apache-2.0 | Free — the SDK is free; the storage backend it talks to may not be. |
| Production | `@aws-sdk/s3-request-presigner` | Signs time-limited upload/download URLs for object storage. | Apache-2.0 | Free |
| Production | `jsonwebtoken` | Issues and verifies session JWTs. | MIT | Free |
| Production | `bcryptjs` | Password hashing for local accounts. | BSD-3-Clause | Free |
| Production | `helmet` | Sets security-related HTTP response headers. | MIT | Free |
| Production | `cors` | Cross-origin request handling for the UI's API calls. | MIT | Free |
| Production | `multer` | Multipart form parsing for file uploads. | MIT | Free |
| Production | `ws` | WebSocket gateway — realtime chat, presence, notifications. | MIT | Free |
| Production | `zod` | Request/schema validation across every module. | MIT | Free |
| Production | `pino` | Structured JSON logging. | MIT | Free |
| Production | `pino-http` | Request/response logging middleware built on `pino`. | MIT | Free |
| Production | `swagger-jsdoc` | Generates the OpenAPI spec from JSDoc route comments. | MIT | Free |
| Production | `swagger-ui-express` | Serves the interactive API docs UI. | MIT | Free |
| Production | `dotenv` | Loads `.env` into process configuration. | BSD-2-Clause | Free |
| Development | `typescript` | Language/compiler for the whole backend. | Apache-2.0 | Free |
| Development | `tsx` | Runs TypeScript directly in watch mode (`npm run dev`). | MIT | Free |
| Development | `vitest` | Test runner (`npm run test`). | MIT | Free |
| Development | `@types/node` | Type definitions for the Node.js runtime. | MIT | Free |
| Development | `@types/express` | Type definitions for `express`. | MIT | Free |
| Development | `@types/cors` | Type definitions for `cors`. | MIT | Free |
| Development | `@types/pg` | Type definitions for `pg`. | MIT | Free |
| Development | `@types/bcryptjs` | Type definitions for `bcryptjs`. | MIT | Free |
| Development | `@types/jsonwebtoken` | Type definitions for `jsonwebtoken`. | MIT | Free |
| Development | `@types/multer` | Type definitions for `multer`. | MIT | Free |
| Development | `@types/ws` | Type definitions for `ws`. | MIT | Free |
| Development | `@types/swagger-jsdoc` | Type definitions for `swagger-jsdoc`. | MIT | Free |
| Development | `@types/swagger-ui-express` | Type definitions for `swagger-ui-express`. | MIT | Free |

</details>

<details>
<summary><strong>drive-osx-mail</strong> — SMTP gateway (<code>drive-osx-mail/package.json</code>)</summary>

| Type | Package | Purpose | License | Paid / Free |
| --- | --- | --- | --- | --- |
| Production | `smtp-server` | Implements the SMTP protocol this gateway listens on, feeding the Mail app. | MIT-0 | Free |
| Production | `dotenv` | Loads gateway configuration from `.env`. | BSD-2-Clause | Free |
| Development | `typescript` | Language/compiler for the gateway. | Apache-2.0 | Free |
| Development | `tsx` | Runs TypeScript directly in watch mode. | MIT | Free |
| Development | `vitest` | Test runner. | MIT | Free |
| Development | `@types/node` | Type definitions for the Node.js runtime. | MIT | Free |
| Development | `@types/smtp-server` | Type definitions for `smtp-server`. | MIT | Free |

</details>

<details>
<summary><strong>drive-osx-ui</strong> — frontend (<code>drive-osx-ui/package.json</code>)</summary>

| Type | Package | Purpose | License | Paid / Free |
| --- | --- | --- | --- | --- |
| Production | `react` | UI rendering for the entire shell and every application. | MIT | Free |
| Production | `react-dom` | React's browser DOM renderer. | MIT | Free |
| Production | `react-router-dom` | Client-side routing for windows/apps and deep links. | MIT | Free |
| Production | `zustand` | Client/UI state stores, kept separate from server state per `CLAUDE.md` §6. | MIT | Free |
| Production | `motion` | Window, menu, and transition animation (formerly Framer Motion). | MIT | Free |
| Production | `lucide-react` | Icon set used across the shell and every application. | ISC | Free |
| Production | `@tiptap/core` | Rich-text document engine (ProseMirror wrapper) behind the Word Book editor. | MIT | Free |
| Production | `@tiptap/starter-kit` | Bundled base set of Tiptap nodes/marks/extensions. | MIT | Free |
| Production | `@tiptap/react` | React bindings for the Tiptap editor. | MIT | Free |
| Production | `@tiptap/pm` | Tiptap's bundled ProseMirror packages. | MIT | Free |
| Production | `@tiptap/extension-underline` | Underline mark for the Word Book editor. | MIT | Free |
| Production | `@tiptap/extension-text-style` | Base extension enabling inline style attributes (e.g. color). | MIT | Free |
| Production | `@tiptap/extension-color` | Text color support. | MIT | Free |
| Production | `@tiptap/extension-highlight` | Text highlight/marker support. | MIT | Free |
| Production | `@tiptap/extension-link` | Hyperlink support. | MIT | Free |
| Production | `@tiptap/extension-text-align` | Paragraph/heading alignment. | MIT | Free |
| Production | `@tiptap/extension-table` | Table node support. | MIT | Free |
| Production | `@tiptap/extension-table-row` | Table row node. | MIT | Free |
| Production | `@tiptap/extension-table-cell` | Table cell node. | MIT | Free |
| Production | `@tiptap/extension-table-header` | Table header-cell node. | MIT | Free |
| Production | `@tiptap/extension-image` | Image node support. | MIT | Free |
| Production | `@tiptap/extension-bubble-menu` | Floating selection toolbar for the Word Book editor. | MIT | Free |
| Production | `@tiptap/extension-font-family` | Font family support. | MIT | Free |
| Production | `@tiptap/extension-subscript` | Subscript mark. | MIT | Free |
| Production | `@tiptap/extension-superscript` | Superscript mark. | MIT | Free |
| Production | `monaco-editor` | The editing engine behind the Code Editor app — bundled locally (no CDN fetch) per `CLAUDE.md` §18's offline-first requirement. | MIT | Free |
| Production | `@monaco-editor/react` | React bindings for Monaco; also supplies the loader pointed at the bundled `monaco-editor` package instead of its jsdelivr CDN default. | MIT | Free |
| Production | `prettier` | Real code formatting inside the Code Editor (`prettier/standalone` + parser plugins), running client-side — no server round-trip. | MIT | Free |
| Production | `eslint-linter-browserify` | ESLint's real core `Linter` class, built for the browser (no Node filesystem/module resolution) — lints JavaScript/JSX files opened in the Code Editor. Not related to this repository's own (currently absent) lint tooling — see `docs/status/audit-and-plan.md` TASK-026 vs TASK-028. | MIT | Free |
| Production | `xlsx` | Spreadsheet app's `.xlsx` read/write (SheetJS Community Edition). | Apache-2.0 | Free — SheetJS also sells a separate Pro edition with more formats/performance; the npm `xlsx` package used here is the free community build. |
| Production | `pptxgenjs` | Generates `.pptx` files for the Presentation app. | MIT | Free |
| Production | `jspdf` | Client-side PDF generation for exports. | MIT | Free |
| Production | `pdfjs-dist` | Mozilla's PDF renderer — powers the PDF Viewer app. | Apache-2.0 | Free |
| Production | `express` | Serves the built frontend directly outside Docker (in the container, nginx does this job). | MIT | Free |
| Production | `vite` | Dev server and production bundler. | MIT | Free |
| Production | `@vitejs/plugin-react` | React fast-refresh/JSX support for Vite. | MIT | Free |
| Production | `@tailwindcss/vite` | Utility-CSS pipeline for the design system. | MIT | Free |
| Production | `dotenv` | Loads UI build/runtime configuration. | BSD-2-Clause | Free |
| Development | `typescript` | Language/compiler; `npm run lint` is `tsc --noEmit`. | Apache-2.0 | Free |
| Development | `tsx` | Runs TypeScript directly for local scripting. | MIT | Free |
| Development | `esbuild` | Fast transpilation used by the Vite toolchain. | MIT | Free |
| Development | `tailwindcss` | Utility CSS framework. | MIT | Free |
| Development | `autoprefixer` | Adds vendor-prefixed CSS automatically. | MIT | Free |
| Development | `vite` | Also listed as a `devDependency` in this `package.json` alongside the production entry above. | MIT | Free |
| Development | `@types/node` | Type definitions for the Node.js runtime. | MIT | Free |
| Development | `@types/express` | Type definitions for `express`. | MIT | Free |
| Development | `@types/react` | Type definitions for `react`. | MIT | Free |
| Development | `@types/react-dom` | Type definitions for `react-dom`. | MIT | Free |

</details>

---

## Notes

- **59** npm packages across the four `package.json` files are `dependencies`
  (production), and **28** are `devDependencies` (build/type-check/test only).
  The infrastructure table above covers everything the stack depends on that
  isn't installed via npm.
- **Nothing in this stack requires a purchased license to run.** A few items
  are worth a second look before treating this repo as unconditionally free
  in every deployment shape:
  - **`pm2-runtime`** (root) — marked `UNLICENSED` on the npm registry and
    published by an unrelated third party, not Keymetrics. See the row above.
  - **`redis:7.4-alpine`** — Redis moved off a permissive OSS license
    starting with the 7.4 line (dual RSALv2/SSPLv1). Confirmed by reading the
    license file in the `redis/redis` repository at tag `7.4.0` directly,
    not assumed from general knowledge of the relicensing news.
  - **Docker Desktop**, if that's how anyone on the team runs these
    `docker-compose` files locally, has its own paid-subscription terms for
    companies above a certain size — independent of Docker Engine/Compose
    themselves, which stay Apache-2.0.
- Everything else checked resolves to a standard permissive or copyleft
  open-source license (MIT, Apache-2.0, BSD-2/3-Clause, ISC, MIT-0,
  PostgreSQL License, AGPL-3.0) with no purchase required to use as this
  project uses it.
