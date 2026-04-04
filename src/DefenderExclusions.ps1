<#
.SYNOPSIS
    Applies Microsoft Defender exclusions for a Windows .NET / Visual Studio dev box.

.DESCRIPTION
    Adds common high-value exclusions for Visual Studio, .NET, NuGet, test output,
    and transient repo build directories under a configured git root.

    Safer defaults:
    - No blanket exclusion of the entire git root
    - No PowerShell / Python / git process exclusions by default
    - Only adds missing exclusions
    - Uses repo wildcard exclusions so future build folders are covered too
#>

# ── SETTINGS ────────────────────────────────────────────────────────

$GitRoot = 'C:\git'   # Change if needed

# Main exclusions
$IncludeVisualStudio       = $true
$IncludeDotNet             = $true
$IncludeJetBrains          = $true
$IncludeNode               = $false
$IncludeNgrok              = $false
$IncludeCursor             = $true

# Additional dev/build exclusions
$IncludeTestArtifacts      = $true
$IncludeArtifactsDir       = $true
$IncludeNuGetExe           = $true
$IncludeDotnetWatch        = $false
$IncludeTestProcesses      = $true

# Repo handling
$ExcludeRepoTransientDirs  = $true   # bin / obj / .vs / packages / node_modules\.cache / TestResults / artifacts under $GitRoot
$ExcludeGitRoot            = $true

# Optional aggressive process exclusions
$ExcludeGitProcess         = $false
$ExcludePythonProcess      = $false
$ExcludePowerShellProcess  = $false

# ───────────────────────────────────────────────────────────────────

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Log {
    param([string]$Message)
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message"
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script as Administrator.'
    }
}

function Get-DefenderPreferences {
    try {
        return Get-MpPreference
    }
    catch {
        throw "Unable to access Microsoft Defender preferences. $($_.Exception.Message)"
    }
}

function Add-UniqueStrings {
    param(
        [Parameter(Mandatory)]$Set,
        [AllowEmptyCollection()][string[]]$Values = @()
    )

    foreach ($value in @($Values)) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [void]$Set.Add($value)
        }
    }
}

function Get-ExistingPaths {
    param([Parameter(Mandatory)][string[]]$Candidates)

    $result = @()

    foreach ($candidate in @($Candidates)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        if (Test-Path -LiteralPath $candidate) {
            $result += [System.IO.Path]::GetFullPath($candidate)
        }
    }

    return @($result)
}

function Apply-DefenderExclusions {
    param(
        [string[]]$Paths = @(),
        [string[]]$Processes = @(),
        [string[]]$Extensions = @()
    )

    $pref = Get-DefenderPreferences

    $existingPaths = @($pref.ExclusionPath)
    $existingProcesses = @($pref.ExclusionProcess)
    $existingExtensions = @($pref.ExclusionExtension)

    $pathsToAdd = @(
        $Paths |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not ($existingPaths -icontains $_) } |
        Sort-Object -Unique
    )

    $processesToAdd = @(
        $Processes |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not ($existingProcesses -icontains $_) } |
        Sort-Object -Unique
    )

    $extensionsToAdd = @(
        $Extensions |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not ($existingExtensions -icontains $_) } |
        Sort-Object -Unique
    )

    if ($pathsToAdd.Count -gt 0) {
        Log "Adding $($pathsToAdd.Count) Defender path exclusion(s)..."
        Add-MpPreference -ExclusionPath $pathsToAdd
    }
    else {
        Log 'No new path exclusions needed.'
    }

    if ($processesToAdd.Count -gt 0) {
        Log "Adding $($processesToAdd.Count) Defender process exclusion(s)..."
        Add-MpPreference -ExclusionProcess $processesToAdd
    }
    else {
        Log 'No new process exclusions needed.'
    }

    if ($extensionsToAdd.Count -gt 0) {
        Log "Adding $($extensionsToAdd.Count) Defender extension exclusion(s)..."
        Add-MpPreference -ExclusionExtension $extensionsToAdd
    }
    else {
        Log 'No new extension exclusions needed.'
    }

    $after = Get-DefenderPreferences

    Write-Host ''
    Write-Host 'Done.' -ForegroundColor Green
    Write-Host "  Paths:      $(@($after.ExclusionPath).Count)"
    Write-Host "  Processes:  $(@($after.ExclusionProcess).Count)"
    Write-Host "  Extensions: $(@($after.ExclusionExtension).Count)"
}

Assert-Admin

$pathSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$processSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$extensionSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

# ── VISUAL STUDIO / BUILD ──────────────────────────────────────────

if ($IncludeVisualStudio) {
    Add-UniqueStrings -Set $pathSet -Values (Get-ExistingPaths -Candidates @(
        "$env:ProgramFiles\Microsoft Visual Studio",
        "$env:ProgramFiles(x86)\Microsoft Visual Studio",
        "$env:ProgramFiles\MSBuild",
        "$env:ProgramData\Microsoft\VisualStudio\Packages",
        "$env:LOCALAPPDATA\Microsoft\VisualStudio",
        "$env:LOCALAPPDATA\Temp\VS",
        "$env:LOCALAPPDATA\Temp\VisualStudio",
        "$env:LOCALAPPDATA\Temp\MsBuild",
        "$env:TEMP\VS",
        "$env:TEMP\MsBuild"
    ))

	Add-UniqueStrings -Set $processSet -Values @(
		'devenv.exe',
		'MSBuild.exe',
		'VBCSCompiler.exe',
		'csc.exe',

		# Roslyn / ServiceHub
		'ServiceHub.RoslynCodeAnalysisService.exe',
		'ServiceHub.Host.dotnet.x64.exe',
		'ServiceHub.Host.netfx.x86.exe',
		'Microsoft.ServiceHub.Controller.exe',
		'ServiceHub.IndexingService.exe',

		# Compiler server variants (sometimes used)
		'compiler.server.exe',
		'CompilerServer.exe'
	)
}

if ($IncludeJetBrains) {
    Add-UniqueStrings -Set $pathSet -Values (Get-ExistingPaths -Candidates @(
        "$env:LOCALAPPDATA\JetBrains\Transient",
        "$env:LOCALAPPDATA\JetBrains\Shared\vAny\Caches",
        "$env:LOCALAPPDATA\JetBrains\ReSharperPlatformVs*\Cache"
    ))

    Add-UniqueStrings -Set $pathSet -Values @(
        "$GitRoot\*\.idea",
        "$GitRoot\*\*\.idea",
        "$GitRoot\*\*\*\.idea"
    )

    Add-UniqueStrings -Set $processSet -Values @(
        'JetBrains.ReSharper.Host.exe',
        'JetBrains.ReSharper.Worker.exe',
        'jb.dotnet.processhost.exe'
    )
}

# ── .NET / NUGET ───────────────────────────────────────────────────

if ($IncludeDotNet) {
    Add-UniqueStrings -Set $pathSet -Values (Get-ExistingPaths -Candidates @(
        "$env:ProgramFiles\dotnet",
        "$env:USERPROFILE\.dotnet",
        "$env:USERPROFILE\.nuget\packages",
        "$env:LOCALAPPDATA\NuGet\Cache",
        "$env:APPDATA\NuGet\Cache",
        "$env:LOCALAPPDATA\NuGet\v3-cache",
        "$env:LOCALAPPDATA\NuGet\plugins-cache",
        "$env:TEMP\nuget",
        "$env:TEMP\NuGetScratch",
        "$env:USERPROFILE\.templateengine",
        "$env:LOCALAPPDATA\Temp\dotnet"
    ))

    Add-UniqueStrings -Set $processSet -Values @(
        'dotnet.exe'
    )

    if ($IncludeNuGetExe) {
        Add-UniqueStrings -Set $processSet -Values @(
            'nuget.exe'
        )
    }

    if ($IncludeDotnetWatch) {
        Add-UniqueStrings -Set $processSet -Values @(
            'dotnet-watch.exe'
        )
    }

    Add-UniqueStrings -Set $extensionSet -Values @(
        '.nupkg',
        '.snupkg'
    )
}

# ── TESTING ────────────────────────────────────────────────────────

if ($IncludeTestProcesses) {
	Add-UniqueStrings -Set $processSet -Values @(
		'testhost.exe',
		'testhost.net.exe',
		'vstest.console.exe',
		'vstest.executionengine.exe'
	)
}

# ── CURSOR ─────────────────────────────────────────────────────────

if ($IncludeCursor) {
    Add-UniqueStrings -Set $pathSet -Values (Get-ExistingPaths -Candidates @(
        "$env:LOCALAPPDATA\Programs\Cursor",
        "$env:APPDATA\Cursor",
        "$env:LOCALAPPDATA\Cursor",
        "$env:LOCALAPPDATA\cursor-updater",
        "$env:USERPROFILE\.cursor"
    ))

    Add-UniqueStrings -Set $pathSet -Values @(
        "$GitRoot\*\.cursor",
        "$GitRoot\*\*\.cursor",
        "$GitRoot\*\*\*\.cursor",
        "$GitRoot\*\*\*\*\.cursor"
    )

	Add-UniqueStrings -Set $processSet -Values @(
		'Cursor.exe',
		'Cursor Helper.exe',
		'cursor-updater.exe',
		'Code.exe',
		'Code Helper.exe'
	)
}

# ── NODE ───────────────────────────────────────────────────────────

if ($IncludeNode) {
    Add-UniqueStrings -Set $pathSet -Values (Get-ExistingPaths -Candidates @(
        "$env:APPDATA\npm",
        "$env:LOCALAPPDATA\npm-cache",
        "$env:USERPROFILE\AppData\Local\Yarn",
        "$env:LOCALAPPDATA\Yarn\Cache",
        "$env:LOCALAPPDATA\pnpm-store",
        "$env:LOCALAPPDATA\Temp\esbuild"
    ))

    Add-UniqueStrings -Set $processSet -Values @(
        'node.exe',
        'npm.exe',
        'npx.exe',
        'pnpm.exe',
        'bun.exe',
        'deno.exe',
        'tsc.exe',
        'gulp.exe',
        'esbuild.exe',
        'webpack.exe',
        'rollup.exe',
        'vite.exe',
        'vite.cmd'
    )
}

# ── NGROK ──────────────────────────────────────────────────────────

if ($IncludeNgrok) {
    Add-UniqueStrings -Set $pathSet -Values (Get-ExistingPaths -Candidates @(
        "$env:ProgramData\chocolatey\lib\ngrok",
        "$env:ProgramData\chocolatey\lib\ngrok\tools",
        "$env:ProgramData\chocolatey\bin"
    ))

    Add-UniqueStrings -Set $processSet -Values @(
        'ngrok.exe'
    )
}

# ── REPO PATHS ─────────────────────────────────────────────────────

if ($ExcludeGitRoot -and (Test-Path -LiteralPath $GitRoot)) {
    Add-UniqueStrings -Set $pathSet -Values @([System.IO.Path]::GetFullPath($GitRoot))
}

if ($ExcludeRepoTransientDirs -and -not [string]::IsNullOrWhiteSpace($GitRoot)) {
    Add-UniqueStrings -Set $pathSet -Values @(
        "$GitRoot\*\bin",
        "$GitRoot\*\obj",
        "$GitRoot\*\.vs",
        "$GitRoot\*\packages",
        "$GitRoot\*\node_modules\.cache",

        "$GitRoot\*\*\bin",
        "$GitRoot\*\*\obj",
        "$GitRoot\*\*\packages",
        "$GitRoot\*\*\node_modules\.cache",

        "$GitRoot\*\*\*\bin",
        "$GitRoot\*\*\*\obj",
        "$GitRoot\*\*\*\packages",
        "$GitRoot\*\*\*\node_modules\.cache",

        "$GitRoot\*\*\*\*\bin",
        "$GitRoot\*\*\*\*\obj",
        "$GitRoot\*\*\*\*\packages",
        "$GitRoot\*\*\*\*\node_modules\.cache"
    )

    if ($IncludeTestArtifacts) {
        Add-UniqueStrings -Set $pathSet -Values @(
            "$GitRoot\*\TestResults",
            "$GitRoot\*\*\TestResults",
            "$GitRoot\*\*\*\TestResults",
            "$GitRoot\*\*\*\*\TestResults"
        )
    }

    if ($IncludeArtifactsDir) {
        Add-UniqueStrings -Set $pathSet -Values @(
            "$GitRoot\*\artifacts",
            "$GitRoot\*\*\artifacts",
            "$GitRoot\*\*\*\artifacts",
            "$GitRoot\*\*\*\*\artifacts"
        )
    }
}

# ── OPTIONAL AGGRESSIVE PROCESSES ──────────────────────────────────

if ($ExcludeGitProcess) {
    Add-UniqueStrings -Set $processSet -Values @('git.exe')
}

if ($ExcludePythonProcess) {
    Add-UniqueStrings -Set $processSet -Values @('python.exe')
}

if ($ExcludePowerShellProcess) {
    Add-UniqueStrings -Set $processSet -Values @('pwsh.exe', 'powershell.exe')
}

# ── APPLY ──────────────────────────────────────────────────────────

$paths = @($pathSet | Sort-Object)
$processes = @($processSet | Sort-Object)
$extensions = @($extensionSet | Sort-Object)

Write-Host ''
Write-Host 'Prepared exclusions:' -ForegroundColor Cyan
Write-Host "  Paths:      $($paths.Count)"
Write-Host "  Processes:  $($processes.Count)"
Write-Host "  Extensions: $($extensions.Count)"
Write-Host ''

Apply-DefenderExclusions -Paths $paths -Processes $processes -Extensions $extensions

Write-Warning @"
Exclusions improve build throughput but reduce scanning on those targets.
This script intentionally avoids broad exclusions unless you explicitly enable them at the top.
"@