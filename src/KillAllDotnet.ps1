# Forcefully close all .NET Host processes (dotnet.exe, dotnet, dotnet-host, etc.)
# Run as Administrator if required.

Get-Process | Where-Object { $_.ProcessName -match '^dotnet' } | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "All .NET Host processes have been terminated." -ForegroundColor Green