# Drive OSX Docker setup

The stack has three containers:

- `drive-osx-ui`: production React UI at http://localhost:3000. Requests to `/api/*` are proxied to the API.
- `drive-osx-api`: Node API at http://localhost:3001, with Swagger available at `/api-docs`.
- `drive-osx-mail`: SMTP service on `localhost:1025`, which authenticates against the API over the internal Docker network.
- `mongo`: persistent MongoDB instance used by the API.

## Run

1. Copy the environment templates and set real values, especially `MONGO_URI` and `JWT_SECRET`:

   ```sh
   cp drive-osx-api/.env.example drive-osx-api/.env
   cp drive-osx-mail/.env.example drive-osx-mail/.env
   ```

2. Start the stack:

   ```sh
   docker compose up --build
   ```

MongoDB data is retained in the named `mongo-data` volume. To use an external database, set `MONGO_URI` in the root `.env` before starting Compose; the API container will use that value instead of the bundled database.
