# Deletes all .log files under the target path.

param(
    [string]$Path = "C:\git",
    [bool]$Recurse = $true
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "Path does not exist: $Path"
    exit 1
}

Write-Host "Starting .log file deletion in directory: $Path"
Write-Host "Recursive: $Recurse"

$getChildItemParams = @{
    LiteralPath = $Path
    File = $true
    Filter = "*.log"
}

if ($Recurse) {
    $getChildItemParams.Recurse = $true
}

$logFiles = @(Get-ChildItem @getChildItemParams)

if ($logFiles.Count -eq 0) {
    Write-Host "No .log files found." -ForegroundColor Yellow
    exit 0
}

$deletedCount = 0
$failedCount = 0

foreach ($logFile in $logFiles) {
    try {
        Remove-Item -LiteralPath $logFile.FullName -Force -ErrorAction Stop
        $deletedCount++
        Write-Host "Deleted: $($logFile.FullName)" -ForegroundColor Green
    }
    catch {
        $failedCount++
        Write-Host "Failed to delete: $($logFile.FullName) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Deleted $deletedCount .log file(s). Failed: $failedCount." -ForegroundColor Green
