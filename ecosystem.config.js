// PM2 process list for running the platform outside Docker.
// Build first: (cd drive-osx-api && npm run build) and the same for the mail
// gateway — both services run compiled output in this mode.
module.exports = {
  apps: [
    {
      name: 'drive-osx-api',
      cwd: './drive-osx-api',
      script: 'dist/main.js',
      instances: 1,
      env: { NODE_ENV: 'production' },
    },
    {
      // Background jobs and the domain-event outbox. Runs as its own process so
      // slow work never blocks an API request.
      name: 'drive-osx-worker',
      cwd: './drive-osx-api',
      script: 'dist/worker.js',
      instances: 1,
      env: { NODE_ENV: 'production' },
    },
    {
      name: 'drive-osx-mail',
      cwd: './drive-osx-mail',
      script: 'dist/main.js',
      instances: 1,
      env: { NODE_ENV: 'production' },
    },
  ],
};
