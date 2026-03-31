<#
.SYNOPSIS
    One-stop cleanup for a Windows .NET / Visual Studio dev box.

.DESCRIPTION
    Recursively removes common build artifacts under a git root, clears optional IDE/tool caches,
    and can optionally wipe NuGet, workload, mobile, and dev-cert state.

    Safer defaults:
    - No automatic workload updates
    - NuGet wiping is toggleable
    - Deep/aggressive cache wipes are toggleable
    - Wildcard directory matching works correctly
#>

# ── SETTINGS ────────────────────────────────────────────────────────

$GitRoot = 'C:\git'   # Change if needed

# Core cleanup
$WipeRepoArtifacts      = $true   # bin / obj / .vs / _ReSharper* under $GitRoot
$WipeUserFiles          = $true   # *.user / *.suo / *.cache under $GitRoot
$RunGitClean            = $false  # git clean -xfd per repo (destructive)

# .NET / NuGet
$WipeNuGet              = $true   # dotnet nuget locals + ~/.dotnet/store + tool store
$WipeWorkloadCaches     = $true   # dotnet workload clean --all
$UpdateWorkloads        = $false  # usually should stay false in a cleanup script

# Visual Studio / editors
$WipeVsCaches           = $true
$WipeDeepVsCaches       = $false  # more aggressive VS cache wipe
$WipeVsCodeCaches       = $true
$WipeCursorCaches       = $true
$WipeReSharperCaches    = $true

# Mobile / MAUI / Android
$WipeMauiCaches         = $true

# ASP.NET / build caches
$WipeAspNetCaches       = $true
$WipeMsBuildCaches      = $true

# Optional
$WipeDevCerts           = $false  # dotnet dev-certs https --clean / --trust

# Process shutdown
$StopVisualStudio       = $true
$StopVsCode             = $true
$StopCursor             = $true
$StopBuildProcesses     = $true
$StopAllDotnetProcesses = $false  # aggressive; usually leave false

# ───────────────────────────────────────────────────────────────────

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Log {
    param([string]$Message)
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message"
}

function Invoke-Safe {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    Log $Label

    try {
        $global:LASTEXITCODE = 0
        & $Action

        if ($LASTEXITCODE -ne 0) {
            throw "Exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Host "❌  $Label failed" -ForegroundColor Red
        $_ | Format-List * -Force
        throw
    }
}

function Stop-App {
    param([Parameter(Mandatory)][string]$Name)

    Get-Process -Name $Name -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $_.CloseMainWindow() | Out-Null
        }
        catch {
        }
    }

    Start-Sleep -Seconds 2

    Get-Process -Name $Name -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function Stop-BuildOrphans {
    Log "Stopping stray build / test processes..."

    foreach ($name in @(
        'MSBuild',
        'VBCSCompiler',
        'vstest.console',
        'MSTest',
        'xunit.console',
        'testhost',
        'testhost.net',
        'testhost.x86',
        'EdgeWebView2'
    )) {
        Get-Process -Name $name -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }

    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like 'testhost*' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function Remove-DirectoryRobust {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return
    }
    catch {
    }

    try {
        Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                try {
                    $_.Attributes = [System.IO.FileAttributes]::Normal
                }
                catch {
                }
            }

        $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($null -ne $item) {
            try {
                $item.Attributes = [System.IO.FileAttributes]::Directory
            }
            catch {
            }
        }

        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to remove: $Path  ($_)"
    }
}

function Remove-MatchingDirsUnder {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        return
    }

    $dirs = Get-ChildItem -Path $Root -Directory -Recurse -Force -ErrorAction SilentlyContinue

    foreach ($dir in $dirs) {
        foreach ($pattern in $Patterns) {
            if ($dir.Name -like $pattern) {
                Remove-DirectoryRobust -Path $dir.FullName
                break
            }
        }
    }
}

function Remove-FilesUnder {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        return
    }

    Get-ChildItem -Path $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object {
            $file = $_
            foreach ($pattern in $Patterns) {
                if ($file.Name -like $pattern) {
                    return $true
                }
            }

            return $false
        } |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "Failed to remove file: $($_.FullName)  ($_)"
            }
        }
}

function Get-DevenvPaths {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'

    if (-not (Test-Path -LiteralPath $vswhere)) {
        $cmd = Get-Command vswhere.exe -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $vswhere = $cmd.Source
        }
    }

    if (-not $vswhere -or -not (Test-Path -LiteralPath $vswhere)) {
        return @()
    }

    $paths = & $vswhere -all -products * -property productPath -format value

    return @($paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
}

function Get-GitRepoRoots {
    param([Parameter(Mandatory)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return @()
    }

    return @(
        Get-ChildItem -Path $Root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') } |
            Select-Object -ExpandProperty FullName
    )
}

# ── STOP PROCESSES ──────────────────────────────────────────────────

if ($StopVsCode) {
    Invoke-Safe "Stopping VS Code..." {
        foreach ($name in @('Code', 'Code - Insiders', 'code')) {
            Stop-App -Name $name
        }
    }
}

if ($StopCursor) {
    Invoke-Safe "Stopping Cursor IDE..." {
        Stop-App -Name 'Cursor'
    }
}

if ($StopVisualStudio) {
    Invoke-Safe "Stopping Visual Studio..." {
        Stop-App -Name 'devenv'
    }
}

if ($StopBuildProcesses) {
    Invoke-Safe "Stopping ReSharper helpers..." {
        foreach ($name in @('JetBrains.ReSharper.TaskRunner', 'jb_eap_agent', 'JetBrains.Etw.Collector')) {
            Stop-App -Name $name
        }
    }

    Invoke-Safe "Stopping build servers..." {
        dotnet build-server shutdown
    }

    Invoke-Safe "Stopping build / test orphans..." {
        Stop-BuildOrphans
    }
}

if ($StopAllDotnetProcesses) {
    Invoke-Safe "Stopping all dotnet.exe processes..." {
        Get-Process dotnet -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

# ── REPO CLEANUP ────────────────────────────────────────────────────

if ($WipeRepoArtifacts) {
    Invoke-Safe "Cleaning repo artifacts under $GitRoot..." {
        Remove-MatchingDirsUnder -Root $GitRoot -Patterns @('bin', 'obj', '.vs', '_ReSharper*')
    }
}

if ($WipeUserFiles) {
    Invoke-Safe "Removing *.user / *.suo / *.cache files under $GitRoot..." {
        Remove-FilesUnder -Root $GitRoot -Patterns @('*.user', '*.suo', '*.cache')
    }
}

if ($RunGitClean -and (Test-Path -LiteralPath $GitRoot)) {
    Invoke-Safe "Running 'git clean -xfd' in each git repo under $GitRoot..." {
        foreach ($repo in Get-GitRepoRoots -Root $GitRoot) {
            Push-Location $repo
            try {
                git clean -xfd | Out-Null
            }
            finally {
                Pop-Location
            }
        }
    }
}

# ── DOTNET / NUGET ──────────────────────────────────────────────────

if ($WipeNuGet) {
    Invoke-Safe "Cleaning NuGet locals..." {
        dotnet nuget locals all --clear
    }

    Invoke-Safe "Removing ~/.dotnet/store..." {
        $store = Join-Path $env:USERPROFILE '.dotnet\store'
        if (Test-Path -LiteralPath $store) {
            Remove-DirectoryRobust -Path $store
        }
    }

    Invoke-Safe "Cleaning global tool cache..." {
        $toolStore = Join-Path $env:USERPROFILE '.dotnet\tools\.store'
        if (Test-Path -LiteralPath $toolStore) {
            Remove-DirectoryRobust -Path $toolStore
        }
    }
}

if ($WipeWorkloadCaches) {
    Invoke-Safe "Pruning orphaned workload packs..." {
        dotnet workload clean --all
    }
}

if ($UpdateWorkloads) {
    Invoke-Safe "Updating workload packs..." {
        dotnet workload update
    }
}

# ── ASP.NET / BUILD CACHES ──────────────────────────────────────────

if ($WipeAspNetCaches) {
    Invoke-Safe "Cleaning legacy ASP.NET temp..." {
        $legacy = Join-Path $env:LOCALAPPDATA 'Temp\Temporary ASP.NET Files'
        if (Test-Path -LiteralPath $legacy) {
            Remove-DirectoryRobust -Path $legacy
        }
    }

    Invoke-Safe "Cleaning ASP.NET Core temp..." {
        Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Temp') -Directory -Filter 'aspnetcore-*' -ErrorAction SilentlyContinue |
            ForEach-Object {
                Remove-DirectoryRobust -Path $_.FullName
            }
    }
}

if ($WipeMsBuildCaches) {
    Invoke-Safe "Cleaning MSBuild / BuildCache..." {
        foreach ($dir in @('MSBuild', 'BuildCache')) {
            $path = Join-Path $env:LOCALAPPDATA "Microsoft\$dir"
            if (Test-Path -LiteralPath $path) {
                Remove-DirectoryRobust -Path $path
            }
        }
    }
}

# ── VISUAL STUDIO ───────────────────────────────────────────────────

if ($WipeVsCaches) {
    $devenvPaths = Get-DevenvPaths

    foreach ($exe in $devenvPaths) {
        Invoke-Safe "VS cache clear via $([System.IO.Path]::GetFileName($exe))..." {
            & $exe /clearcache
            & $exe /updateconfiguration
        }
    }

    Invoke-Safe "Cleaning VS caches..." {
        $roots = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\VisualStudio'),
            (Join-Path $env:APPDATA 'Microsoft\VisualStudio')
        )

        $subdirs = @(
            'ComponentModelCache',
            'Roslyn',
            'MEFCacheBackup',
            'ActivityLog',
            'Designer',
            'Cache',
            'ProjectTemplatesCache',
            'ItemTemplatesCache',
            'AnalyzerCache',
            'Diagnostics',
            'ServerHub',
            'ImageLibrary',
            'ImageService',
            'VBCSCompiler'
        )

        foreach ($root in $roots) {
            if (-not (Test-Path -LiteralPath $root)) {
                continue
            }

            Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                ForEach-Object {
                    foreach ($subdir in $subdirs) {
                        $path = Join-Path $_.FullName $subdir
                        if (Test-Path -LiteralPath $path) {
                            Remove-DirectoryRobust -Path $path
                        }
                    }
                }
        }

        foreach ($extra in @(
            (Join-Path $env:USERPROFILE '.vs-lsp-cache'),
            (Join-Path $env:LOCALAPPDATA 'Temp\SymbolCache'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\VSApplicationInsights'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\VSCommon\Cache')
        )) {
            if (Test-Path -LiteralPath $extra) {
                Remove-DirectoryRobust -Path $extra
            }
        }
    }

    if ($WipeDeepVsCaches) {
        Invoke-Safe "Cleaning deep VS caches..." {
            $vsRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\VisualStudio'

            if (Test-Path -LiteralPath $vsRoot) {
                Get-ChildItem -Path $vsRoot -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        foreach ($subdir in @(
                            'ComponentModelCache',
                            'Roslyn',
                            'ProjectTemplatesCache',
                            'ItemTemplatesCache',
                            'AnalyzerCache',
                            'Diagnostics',
                            'Cache',
                            'ServerHub',
                            'Extensions'
                        )) {
                            $path = Join-Path $_.FullName $subdir
                            if (Test-Path -LiteralPath $path) {
                                Remove-DirectoryRobust -Path $path
                            }
                        }
                    }
            }
        }
    }
}

if ($WipeReSharperCaches) {
    Invoke-Safe "Cleaning ReSharper caches..." {
        Remove-MatchingDirsUnder -Root $GitRoot -Patterns @('_ReSharper*')

        $jetBrainsRoot = Join-Path $env:LOCALAPPDATA 'JetBrains'
        if (Test-Path -LiteralPath $jetBrainsRoot) {
            $transient = Join-Path $jetBrainsRoot 'Transient'
            if (Test-Path -LiteralPath $transient) {
                Get-ChildItem -Path $transient -Directory -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like 'ReSharper*' } |
                    ForEach-Object {
                        Remove-DirectoryRobust -Path $_.FullName
                    }
            }

            Get-ChildItem -Path $jetBrainsRoot -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'ReSharperPlatformVs*' } |
                ForEach-Object {
                    $cache = Join-Path $_.FullName 'Cache'
                    if (Test-Path -LiteralPath $cache) {
                        Remove-DirectoryRobust -Path $cache
                    }
                }
        }
    }
}

# ── VS CODE ─────────────────────────────────────────────────────────

if ($WipeVsCodeCaches) {
    Invoke-Safe "Cleaning VS Code caches..." {
        foreach ($base in @(
            (Join-Path $env:APPDATA 'Code'),
            (Join-Path $env:APPDATA 'Code - Insiders')
        )) {
            if (-not (Test-Path -LiteralPath $base)) {
                continue
            }

            foreach ($pattern in @('Cache*', 'GPUCache', 'CachedData')) {
                Get-ChildItem -Path $base -Directory -Filter $pattern -Force -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        Remove-DirectoryRobust -Path $_.FullName
                    }
            }

            $workspaceStorage = Join-Path $base 'User\workspaceStorage'
            if (Test-Path -LiteralPath $workspaceStorage) {
                Remove-DirectoryRobust -Path $workspaceStorage
            }
        }

        $extensions = Join-Path $env:USERPROFILE '.vscode\extensions'
        if (Test-Path -LiteralPath $extensions) {
            Get-ChildItem -Path $extensions -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq '.cache' } |
                ForEach-Object {
                    Remove-DirectoryRobust -Path $_.FullName
                }
        }

        Get-ChildItem -Path $env:USERPROFILE -Directory -Filter '.vscode-server*' -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                Remove-DirectoryRobust -Path $_.FullName
            }
    }
}

# ── CURSOR ──────────────────────────────────────────────────────────

if ($WipeCursorCaches) {
    Invoke-Safe "Cleaning Cursor IDE caches..." {
        $cursor = Join-Path $env:APPDATA 'Cursor'
        if (Test-Path -LiteralPath $cursor) {
            foreach ($pattern in @('Cache*', 'GPUCache', 'CachedData')) {
                Get-ChildItem -Path $cursor -Directory -Filter $pattern -Force -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        Remove-DirectoryRobust -Path $_.FullName
                    }
            }

            $workspaceStorage = Join-Path $cursor 'User\workspaceStorage'
            if (Test-Path -LiteralPath $workspaceStorage) {
                Remove-DirectoryRobust -Path $workspaceStorage
            }
        }

        $extensions = Join-Path $env:USERPROFILE '.cursor\extensions'
        if (Test-Path -LiteralPath $extensions) {
            Get-ChildItem -Path $extensions -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq '.cache' } |
                ForEach-Object {
                    Remove-DirectoryRobust -Path $_.FullName
                }
        }

        Get-ChildItem -Path $env:USERPROFILE -Directory -Filter '.cursor-server*' -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                Remove-DirectoryRobust -Path $_.FullName
            }
    }
}

# ── MAUI / MOBILE / ANDROID ────────────────────────────────────────

if ($WipeMauiCaches) {
    Invoke-Safe "Cleaning XamarinBuildDownload cache..." {
        $path = Join-Path $env:LOCALAPPDATA 'XamarinBuildDownloadCache'
        if (Test-Path -LiteralPath $path) {
            Remove-DirectoryRobust -Path $path
        }
    }

    Invoke-Safe "Cleaning Xamarin / MAUI framework caches..." {
        $xamarin = Join-Path $env:LOCALAPPDATA 'Xamarin'
        if (Test-Path -LiteralPath $xamarin) {
            foreach ($pattern in @('Cache', 'Cache*', 'Logs', 'DeviceLogs', 'MTBS')) {
                Get-ChildItem -Path $xamarin -Directory -Filter $pattern -Force -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        Remove-DirectoryRobust -Path $_.FullName
                    }
            }
        }
    }

    Invoke-Safe "Cleaning .NET hot-reload caches..." {
        $path = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet-hot-reload'
        if (Test-Path -LiteralPath $path) {
            Remove-DirectoryRobust -Path $path
        }
    }

    Invoke-Safe "Cleaning Android caches..." {
        $android = Join-Path $env:LOCALAPPDATA 'Android'
        if (Test-Path -LiteralPath $android) {
            foreach ($name in @('Cache', 'adb', 'device-cache')) {
                $path = Join-Path $android $name
                if (Test-Path -LiteralPath $path) {
                    Remove-DirectoryRobust -Path $path
                }
            }
        }
    }
}

# ── OPTIONAL: DEV CERTS ─────────────────────────────────────────────

if ($WipeDevCerts) {
    Invoke-Safe "Resetting HTTPS dev certs..." {
        dotnet dev-certs https --clean
        dotnet dev-certs https --trust
    }
}

Log "==== CLEAN COMPLETE ===="