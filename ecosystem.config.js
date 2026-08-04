module.exports = {
  apps: [
    {
      name: "drive-osx-api",
      cwd: "./drive-osx-api",
      script: "npm",
      args: "start",
    },
    {
      name: "drive-osx-mail",
      cwd: "./drive-osx-mail",
      script: "npm",
      args: "start",
    },
    {
      name: "drive-osx-ui",
      cwd: "./drive-osx-ui",
      script: "npm",
      args: "run dev -- --host",
    },
  ],
};