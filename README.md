[![](https://img.shields.io/nuget/v/soenneker.scripts.dev.svg?style=for-the-badge)](https://www.nuget.org/packages/soenneker.scripts.dev/)
[![](https://img.shields.io/github/actions/workflow/status/soenneker/soenneker.scripts.dev/publish-package.yml?style=for-the-badge)](https://github.com/soenneker/soenneker.scripts.dev/actions/workflows/publish-package.yml)
[![](https://img.shields.io/nuget/dt/soenneker.scripts.dev.svg?style=for-the-badge)](https://www.nuget.org/packages/soenneker.scripts.dev/)
[![](https://img.shields.io/github/actions/workflow/status/soenneker/soenneker.scripts.dev/codeql.yml?label=CodeQL&style=for-the-badge)](https://github.com/soenneker/soenneker.scripts.dev/actions/workflows/codeql.yml)

# Soenneker.Scripts.Dev

Development-machine maintenance, setup, test, and diagnostics scripts used in Soenneker repositories.

These files modify machine state and are intended to be reviewed and run directly. Several contain configuration switches near the top; set those for your machine before execution.

## Included scripts

| File | Purpose | Important behavior |
| --- | --- | --- |
| `EnvironmentSetup.ps1` | Updates .NET workloads and installs `wasm-tools`. | Requires an installed `dotnet` CLI and may download or replace workload packs. |
| `CleanEnvironment.ps1` | Cleans repository artifacts and Windows development-tool caches. | Defaults to `C:\git`, stops multiple IDE/build processes, clears NuGet/workload caches, and recursively deletes configured artifacts. Review every `$Wipe*`, `$Stop*`, and `$GitRoot` setting first. |
| `DefenderExclusions.ps1` | Adds Microsoft Defender exclusions for selected development tools and transient build paths. | Must run as Administrator. Exclusions reduce malware scanning; broad repository and process exclusions are opt-in settings. |
| `DeleteLogs.ps1` | Deletes `.log` files below a supplied path. | Defaults to `C:\git` with recursion enabled and permanently removes matching files. |
| `KillAllDotnet.ps1` | Force-terminates processes whose names begin with `dotnet`. | Can interrupt builds, tests, servers, and unrelated .NET applications. |
| `RunBradixPlaywrightTest.ps1` | Builds and launches the Bradix Playwright test executable with method, class, or query filtering. | Assumes the repository layout beneath `C:\git\Soenneker`; it can terminate stale Bradix test/demo process trees unless `-SkipCleanup` is supplied. |
| `dotMemoryLinux.sh` | Installs prerequisites and downloads the pinned JetBrains dotMemory console distribution in a Linux container. | Uses `apt-get` or `apk`, writes beneath the current directory and `/home/site/dotmemory`, and is configured to inspect PID 1. The attach command is left commented for deliberate execution. |

## Examples

Install the WebAssembly workload:

```powershell
pwsh -File .\src\EnvironmentSetup.ps1
```

Delete logs from one specific repository without recursion:

```powershell
pwsh -File .\src\DeleteLogs.ps1 -Path C:\git\MyRepo -Recurse $false
```

Run one Bradix Playwright test method:

```powershell
pwsh -File .\src\RunBradixPlaywrightTest.ps1 -Method MyTestMethod -Build
```

Prepare dotMemory inside a Linux container:

```bash
bash ./src/dotMemoryLinux.sh
```

## Safety

Do not invoke `CleanEnvironment.ps1`, `DeleteLogs.ps1`, `KillAllDotnet.ps1`, or `DefenderExclusions.ps1` blindly from shared automation. Their changes affect the workstation outside the repository and may be difficult to reverse. Use an elevated shell only for the operations that require it, and keep the broad or destructive options disabled unless you intentionally need them.
