# Drive OSX

A browser-based operating environment: an OS shell (desktop, window manager, dock,
launcher, notifications) hosting integrated applications — Drive, Documents,
Spreadsheets, Presentations, Mail, Meetings, Chat, Calculator and more — on a
multi-tenant platform.

Architecture principles and long-term direction live in [CLAUDE.md](CLAUDE.md);
the concrete implementation is described in [docs/architecture.md](docs/architecture.md).

## Stack

| Concern | Choice |
| --- | --- |
| Frontend | React + TypeScript, Vite, Tailwind, Zustand |
| Backend | TypeScript modular monolith on Express |
| System of record | PostgreSQL |
| File bytes | S3-compatible object storage (MinIO locally) |
| Cache, queues, realtime | Redis |
| Offline | IndexedDB + service worker + sync engine |
| Search | PostgreSQL full text (`tsvector` + trigram) |

## Services

| Service | Port (dev) | Purpose |
| --- | --- | --- |
| `drive-osx-ui` | 3000 | OS shell and applications; proxies `/api` and `/ws` to the API |
| `drive-osx-api` | 3001 | Platform API and realtime gateway |
| `drive-osx-worker` | — | Background jobs and the domain-event outbox |
| `drive-osx-mail` | 1025 | SMTP gateway; hands inbound mail to the API |
| `postgres` | — | System of record |
| `redis` | — | Cache, job queue, realtime fan-out |
| `minio` | 9000 / 9001 | Object storage and its console |

## Run everything with Docker (recommended)

Requires Docker with the Compose plugin. Nothing else needs to be installed —
Node, PostgreSQL, Redis and object storage all run in containers.

```sh
git clone <this-repo> && cd drive-osx

# Creates the four .env files from their templates and generates a JWT secret.
./scripts/check-env.sh --fix

docker compose up --build
```

`.env` files are not committed, so the bootstrap step is needed once per
checkout — Compose fails immediately if they are missing. After that,
`docker compose up` is the only command you need; re-run it any time and it
picks up your `.env`.

### Choosing development or production

One line in the root `.env` decides which stack `docker compose up` runs — no
`-f` flags, no different commands:

```sh
# development (the default in .env.example): watch mode, bind-mounted source,
# datastore ports published on the host
COMPOSE_FILE=docker-compose.yml:docker-compose.dev.yml

# production: compiled images only, nginx serving the shell, datastores internal
COMPOSE_FILE=docker-compose.yml
```

Each mode builds its own image tags (`drive-osx/api:dev` vs `drive-osx/api:prod`),
so switching can never silently run the other mode's artefact. The first `up`
after switching builds the missing images; add `--build` to force a rebuild
after code changes in production mode.

Two files are needed rather than one: Compose cannot omit a bind mount based on
a variable, and mounting your source over a production image would defeat the
build. Everything else that differs between the modes *is* environment-driven.

First start takes a few minutes while images build. When `drive-osx-api` reports
healthy, open <http://localhost:3000> and create an account — the shell
provisions a personal workspace and drive for it.

Useful commands:

```sh
docker compose ps                        # what is running, and whether it is healthy
docker compose logs -f drive-osx-api     # follow one service
docker compose restart drive-osx-worker  # restart a single service
docker compose down                      # stop (data volumes are kept)
docker compose down -v                   # stop and delete all data
```

In development every service is built from its `dev` image target and runs in
watch mode with the source bind-mounted, so edits reload without a rebuild.

Production can also be selected per command, without touching `.env`:

```sh
docker compose -f docker-compose.yml up --build
```

That builds the `production` targets — compiled output, runtime dependencies
only, unprivileged users, pinned base images — and serves the shell through
nginx on `UI_PORT` (80 by default) instead of the Vite dev server on 3000.

The API applies its migrations on boot, creates the storage bucket if it is
missing, and refuses to start if PostgreSQL, Redis or object storage is
unreachable — a half-connected API is worse than one that fails loudly.

### How the images are built

Each service has **one** `Dockerfile` with multiple targets, so development and
production share the same base image and dependency resolution and cannot drift:

| Target | Used by | Contains |
| --- | --- | --- |
| `deps` | both | dependencies installed with `npm ci --ignore-scripts` |
| `build` | production | compiled TypeScript / built bundle |
| `dev` | `docker-compose.dev.yml` | all dependencies, watch mode |
| `production` | `docker-compose.yml` | compiled output and runtime dependencies only |

Build a single target directly if you need to:

```sh
docker build --target production -t drive-osx-api ./drive-osx-api
```

The API and worker run from the same image; only the command differs. Every
image carries its own `HEALTHCHECK`, runs as a non-root user (`node`, or `nginx`
for the UI), and uses an exec-form command so the process receives `SIGTERM`
directly and shuts down gracefully.

## Ports and URLs

The two Docker modes publish different ports on purpose, so a development stack
and a production-shaped stack never collide.

| What | `docker compose up` (dev) | `-f docker-compose.yml` (prod) | Run on host |
| --- | --- | --- | --- |
| Shell | <http://localhost:3000> | `UI_PORT`, default <http://localhost:80> | <http://localhost:3000> |
| API | <http://localhost:3001/api/v1> | `API_PORT`, default <http://localhost:7000/api/v1> | <http://localhost:7000/api/v1> |
| API docs (non-production only) | `/api/v1/docs` | disabled | `/api/v1/docs` |
| Readiness probe | `/api/v1/health/ready` | `/api/v1/health/ready` | `/api/v1/health/ready` |
| Worker health | internal `:7001/health` | internal `:7001/health` | <http://localhost:7001/health> |
| Object storage console | <http://localhost:9001> | <http://localhost:9001> | <http://localhost:9001> |
| SMTP | `localhost:1025` | `localhost:1025` | `localhost:2525` |
| PostgreSQL | `localhost:5432` | not published | `localhost:5432` |
| Redis | `localhost:6379` | not published | `localhost:6379` |

PostgreSQL and Redis are reachable from the host in development only; the
production file keeps them on the internal network.

Credentials for the local object storage console are `MINIO_ROOT_USER` /
`MINIO_ROOT_PASSWORD` from the root `.env`.

The worker has no public port. To check it:

```sh
docker compose exec drive-osx-worker \
  node -e "fetch('http://127.0.0.1:7001/health').then(r=>r.text()).then(console.log)"
```

It reports queue depth and event backlog, so a worker that is running but stuck
is visible.

## Run the services on your machine (without Docker)

Useful when you want a debugger attached or a faster edit loop. The datastores
still run in containers — install Node 22+ and start them first:

```sh
docker compose up -d postgres redis minio
```

In development these publish `5432`, `6379` and `9000` on the host (see
`docker-compose.dev.yml`).

The committed `.env` files use Docker hostnames (`postgres`, `redis`, `minio`),
which do not resolve outside the network, so point the services at `localhost`.
Exported variables take precedence over `.env`, so no file needs editing:

```sh
export DATABASE_URL="postgres://drive:drive@localhost:5432/drive"
export REDIS_URL="redis://localhost:6379"
export STORAGE_ENDPOINT="http://localhost:9000"
export STORAGE_PUBLIC_URL="http://localhost:9000"
```

Then run each service in its own terminal, with those variables exported:

```sh
cd drive-osx-api  && npm install && npm run dev         # API on :7000
cd drive-osx-api  && npm run dev:worker                 # background worker
cd drive-osx-mail && npm install && npm run dev         # SMTP on :2525
cd drive-osx-ui   && npm install && npm run dev         # shell on :3000
```

The UI dev server proxies `/api/v1` to `http://drive-osx-api:7000`, which only
resolves inside Docker. When the API runs on your host, point the proxy at it:

```sh
cd drive-osx-ui && VITE_API_BASE_URL="http://localhost:7000/api/v1" npm run dev
```

The API creates the storage bucket and applies migrations on boot, so there is
no separate setup step.

## Other commands

```sh
# Repository
./scripts/check-env.sh          # verify .env files match their templates
./scripts/install-git-hooks.sh  # enforce that check on commit (see CLAUDE.md §35)

# API and worker
cd drive-osx-api
npm run migrate      # apply migrations without starting the API
npm test             # unit tests
npm run typecheck
npm run build        # compile to dist/

# UI
cd drive-osx-ui
npm run lint         # tsc --noEmit
npm run build

# SMTP gateway
cd drive-osx-mail
npm test
npm run typecheck
```

### Sending a test message

```sh
python3 - <<'PY'
import smtplib
from email.message import EmailMessage
msg = EmailMessage()
msg['From'] = 'sender@example.com'
msg['To'] = 'YOUR_USERNAME@driveosx.com'
msg['Subject'] = 'Hello'
msg.set_content('Body text')
with smtplib.SMTP('localhost', 1025) as smtp:
    smtp.send_message(msg)
PY
```

The message appears in that account's inbox in the Mail application.

## Troubleshooting

- **API exits immediately at start.** It refuses to run without PostgreSQL,
  Redis and object storage. Check `docker compose logs drive-osx-api` — the
  first line names the dependency that failed. A `JWT_SECRET` shorter than 16
  characters also stops boot, by design.
- **`ECONNREFUSED postgres:5432` when running on the host.** The Docker
  hostnames are unresolvable outside the network; export the `localhost` URLs
  from the section above.
- **Shell loads but every request fails.** The UI proxy is pointing at the
  container API. Set `VITE_API_BASE_URL` as shown above.
- **Port already in use.** Override the published ports in the root `.env`:
  `UI_DEV_PORT` / `API_DEV_PORT` for the development stack, `UI_PORT` /
  `API_PORT` for the production one, plus `SMTP_PORT`, `MINIO_PORT`,
  `MINIO_CONSOLE_PORT`, `POSTGRES_PORT`, `REDIS_PORT`.
- **A service is up but never becomes healthy.** `docker compose ps` shows the
  state and `docker inspect --format '{{json .State.Health}}' <container>` shows
  the failing probe output. Health checks live in the images, so they apply to
  `docker run` too.
- **MinIO exits with `Unknown xl meta version`.** The pinned MinIO release is
  older than the one that wrote `minio-data`. MinIO cannot downgrade a data
  directory — move the pin in `docker-compose.yml` forward, or delete the
  volume to start fresh.
- **Start from a clean slate.** `docker compose down -v` deletes the database,
  Redis and object storage volumes; the next start recreates the schema.
- **Switched `COMPOSE_FILE` and a service fails to start.** The other mode's
  image has not been built yet. Run `docker compose up -d --build`.
- **A setting seems to be ignored.** Check that your `.env` files still match
  their templates:

  ```sh
  ./scripts/check-env.sh          # report drift
  ./scripts/check-env.sh --fix    # append missing keys from .env.example
  ```

  Keys documented in `.env.example` but absent from `.env` fall back to their
  built-in defaults; keys present in `.env` but missing from `.env.example` are
  undocumented and will not survive a fresh checkout.

## Data

- PostgreSQL holds users, organizations, memberships, teams, file metadata,
  permissions, shares, mail, meetings, notifications, audit logs and the
  domain-event outbox. Volume: `postgres-data`.
- Object storage holds file contents, versions and previews under
  `originals/`, `versions/`, `previews/` and `thumbnails/`, each prefixed by
  organization. Volume: `minio-data`.
- Redis holds cache entries, the job queue and realtime fan-out. Everything in
  Redis is rebuildable from PostgreSQL. Volume: `redis-data`.

Schema changes are forward-only SQL files in
`drive-osx-api/src/infrastructure/database/migrations`. Applied migrations are
checksummed and immutable — change the schema by adding a new file.
