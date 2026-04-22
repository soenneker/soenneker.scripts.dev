param(
    [string]$Method,
    [string]$Class,
    [string]$Query,
    [switch]$ListTests,
    [switch]$Build,
    [switch]$DetailedOutput,
    [switch]$SkipCleanup,
    [string]$Configuration = "Debug",
    [string]$Framework = "net10.0",
    [string]$ResultsDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($Method) -and [string]::IsNullOrWhiteSpace($Class) -and [string]::IsNullOrWhiteSpace($Query) -and -not $ListTests) {
    throw "Specify -Method, -Class, -Query, or -ListTests."
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot "..\..\.."))
$projectPath = Join-Path $repoRoot "Bradix\soenneker.bradix.suite\test\Soenneker.Bradix.Suite.Playwrights.Tests\Soenneker.Bradix.Suite.Playwrights.Tests.csproj"
$outputDir = Join-Path $repoRoot "Bradix\soenneker.bradix.suite\test\Soenneker.Bradix.Suite.Playwrights.Tests\bin\$Configuration\$Framework"
$exePath = Join-Path $outputDir "Soenneker.Bradix.Suite.Playwrights.Tests.exe"

if ($Build -or -not (Test-Path -LiteralPath $exePath)) {
    & dotnet build $projectPath -c $Configuration
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Test executable not found: $exePath"
}

if (-not $SkipCleanup) {
    $cleanupPatterns = @(
        '*Soenneker.Bradix.Suite.Playwrights.Tests*',
        '*Soenneker.Bradix.Suite.Demo*'
    )

    $staleProcesses = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'dotnet.exe' -and (
            $_.CommandLine -like $cleanupPatterns[0] -or
            $_.CommandLine -like $cleanupPatterns[1]
        )
    }

    foreach ($process in $staleProcesses) {
        Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c", "taskkill /PID $($process.ProcessId) /T /F" `
            -WindowStyle Hidden `
            -Wait
    }
}

if ([string]::IsNullOrWhiteSpace($ResultsDirectory)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $ResultsDirectory = Join-Path $outputDir "TestResults\single\$stamp"
}

New-Item -ItemType Directory -Path $ResultsDirectory -Force | Out-Null

$arguments = [System.Collections.Generic.List[string]]::new()
$arguments.Add("--results-directory")
$arguments.Add($ResultsDirectory)
$arguments.Add("--output")
$arguments.Add($(if ($DetailedOutput) { "Detailed" } else { "Normal" }))
$arguments.Add("--no-ansi")

if ($ListTests) {
    $arguments.Add("--list-tests")
}

$filterCount = @($Method, $Class, $Query).Where({ -not [string]::IsNullOrWhiteSpace($_) }).Count

if ($filterCount -gt 1) {
    throw "Specify only one of -Method, -Class, or -Query."
}

if (-not [string]::IsNullOrWhiteSpace($Method)) {
    $arguments.Add("--filter-method")
    $arguments.Add($Method)
}

if (-not [string]::IsNullOrWhiteSpace($Class)) {
    $arguments.Add("--filter-class")
    $arguments.Add($Class)
}

if (-not [string]::IsNullOrWhiteSpace($Query)) {
    $arguments.Add("--filter-query")
    $arguments.Add($Query)
}

Write-Host "Running: $exePath $($arguments -join ' ')"
& $exePath @arguments
exit $LASTEXITCODE
