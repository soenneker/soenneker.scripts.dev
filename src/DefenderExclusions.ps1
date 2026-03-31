<#
.SYNOPSIS
    Applies Microsoft Defender exclusions for a Windows .NET / Visual Studio dev box.

.DESCRIPTION
    Adds common high-value exclusions for Visual Studio, .NET, NuGet, and transient
    repo build directories under a configured git root.

    Safer defaults:
    - No blanket exclusion of the entire git root
    - No PowerShell / Python / git process exclusions by default
    - Only adds missing exclusions
#>

# ── SETTINGS ────────────────────────────────────────────────────────

$GitRoot = 'C:\git'   # Change if needed

# Main exclusions
$IncludeVisualStudio       = $true
$IncludeDotNet             = $true
$IncludeNode               = $false
$IncludeNgrok              = $false

# Repo handling
$ExcludeRepoTransientDirs  = $true   # bin / obj / .vs / packages / node_modules\.cache under $GitRoot
$ExcludeGitRoot            = $false  # broad exclusion; usually leave false

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
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$Set,
        [Parameter(Mandatory)][string[]]$Values
    )

    foreach ($value in $Values) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [void]$Set.Add($value)
        }
    }
}

function Get-ExistingPaths {
    param([Parameter(Mandatory)][string[]]$Candidates)

    $result = [System.Collections.Generic.List[string]]::new()

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        if (Test-Path -LiteralPath $candidate) {
            $result.Add([System.IO.Path]::GetFullPath($candidate))
        }
    }

    return $result.ToArray()
}

function Get-RepoTransientDirectories {
    param([Parameter(Mandatory)][string]$Root)

    $result = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
        return $result.ToArray()
    }

    Log "Scanning transient repo directories under $Root..."

    try {
        $dirs = Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force -ErrorAction SilentlyContinue

        foreach ($dir in $dirs) {
            switch -Regex ($dir.Name) {
                '^\.vs$' {
                    [void]$result.Add($dir.FullName)
                    continue
                }

                '^bin$' {
                    [void]$result.Add($dir.FullName)
                    continue
                }

                '^obj$' {
                    [void]$result.Add($dir.FullName)
                    continue
                }

                '^packages$' {
                    [void]$result.Add($dir.FullName)
                    continue
                }

                '^\.cache$' {
                    if ($null -ne $dir.Parent -and $dir.Parent.Name -eq 'node_modules') {
                        [void]$result.Add($dir.FullName)
                    }

                    continue
                }
            }
        }
    }
    catch {
        Write-Warning "Failed scanning '$Root': $($_.Exception.Message)"
    }

    return $result.ToArray()
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
        Where-Object { $_ -and -not ($existingPaths -icontains $_) } |
        Sort-Object -Unique
    )

    $processesToAdd = @(
        $Processes |
        Where-Object { $_ -and -not ($existingProcesses -icontains $_) } |
        Sort-Object -Unique
    )

    $extensionsToAdd = @(
        $Extensions |
        Where-Object { $_ -and -not ($existingExtensions -icontains $_) } |
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
        'ServiceHub.RoslynCodeAnalysisService.exe'
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
        "$env:TEMP\NuGetScratch"
    ))

    Add-UniqueStrings -Set $processSet -Values @(
        'dotnet.exe'
    )

    Add-UniqueStrings -Set $extensionSet -Values @(
        '.nupkg',
        '.snupkg'
    )
}

# ── NODE ───────────────────────────────────────────────────────────

if ($IncludeNode) {
    Add-UniqueStrings -Set $pathSet -Values (Get-ExistingPaths -Candidates @(
        "$env:APPDATA\npm",
        "$env:LOCALAPPDATA\npm-cache",
        "$env:USERPROFILE\AppData\Local\Yarn",
        "$env:LOCALAPPDATA\pnpm-store"
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
        'webpack.exe'
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

if ($ExcludeRepoTransientDirs) {
    Add-UniqueStrings -Set $pathSet -Values (Get-RepoTransientDirectories -Root $GitRoot)
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