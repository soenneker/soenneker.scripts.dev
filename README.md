[![](https://img.shields.io/nuget/v/soenneker.scripts.dev.svg?style=for-the-badge)](https://www.nuget.org/packages/soenneker.scripts.dev/)
[![](https://img.shields.io/github/actions/workflow/status/soenneker/soenneker.scripts.dev/publish-package.yml?style=for-the-badge)](https://github.com/soenneker/soenneker.scripts.dev/actions/workflows/publish-package.yml)
[![](https://img.shields.io/nuget/dt/soenneker.scripts.dev.svg?style=for-the-badge)](https://www.nuget.org/packages/soenneker.scripts.dev/)
[![](https://img.shields.io/github/actions/workflow/status/soenneker/soenneker.scripts.dev/codeql.yml?label=CodeQL&style=for-the-badge)](https://github.com/soenneker/soenneker.scripts.dev/actions/workflows/codeql.yml)

# Soenneker.Scripts.Dev

Development bootstrap scripts used by Codex and CI-style Linux environments.

## What it provides

- `src/Codex.txt` installs the .NET 10 SDK into the current user's `~/.dotnet` directory without configuring an apt package feed.
- It updates the current process immediately, persists `DOTNET_ROOT` and `PATH` through `/etc/profile.d/dotnet.sh`, and can run a temporary xUnit project to verify the installation.

## Included files

- `src/Codex.txt` — a Bash bootstrap script stored with a `.txt` extension so it can be copied into automation tasks.

## How to use it

Review the configuration variables at the top of `src/Codex.txt`, especially `DOTNET_CHANNEL`, `DOTNET_QUALITY`, and `RUN_DOTNET_TEST`. Copy it into your automation or execute it with Bash after reviewing it.

## Important behavior

- The script uses `sudo apt-get` to install prerequisites and writes `/etc/profile.d/dotnet.sh`, so it needs elevated access.
- The SDK is installed per user under `~/.dotnet`; it does not add Microsoft's apt repository.
- With `RUN_DOTNET_TEST=true`, it creates and runs a temporary xUnit project, then removes the temporary directory.
