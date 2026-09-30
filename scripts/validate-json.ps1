# validate-json.ps1 - parse-check every JSON in a project + basic structure checks
# Usage: powershell -ExecutionPolicy Bypass -File scripts/validate-json.ps1 [-Project projects/SalesDash]
param(
    [string]$Project
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
if (-not $Project) { $Project = Join-Path $workspace 'projects' }
if (-not (Test-Path $Project)) { throw "Project not found: $Project" }

function Read-Utf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

$bad = @()
Get-ChildItem $Project -Recurse -Filter *.json -File -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $null = Read-Utf8 $_.FullName | ConvertFrom-Json
    } catch {
        $bad += $_.FullName
        Write-Warning "JSON parse failed: $($_.FullName) -> $($_.Exception.Message)"
    }
}

$reportDir = Get-ChildItem $Project -Directory -Filter '*.Report' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($reportDir) {
    $dp = Join-Path $reportDir.FullName 'definition.pbir'
    if (-not (Test-Path $dp)) { Write-Warning "Missing $dp" }
    $pagesJson = Join-Path $reportDir.FullName 'definition\pages\pages.json'
    if (-not (Test-Path $pagesJson)) { Write-Warning "Missing $pagesJson" }
    $repJson = Join-Path $reportDir.FullName 'definition\report.json'
    if (-not (Test-Path $repJson)) { Write-Warning "Missing $repJson (report.json required)" }
    $ext = Join-Path $reportDir.FullName 'definition\reportExtensions.json'
    if (Test-Path $ext) {
        $e = Read-Utf8 $ext | ConvertFrom-Json
        if (@($e.entities).Count -eq 0) { Write-Warning "reportExtensions.json has empty entities: delete the whole file" }
    }
} else {
    Write-Warning "No *.Report folder found under $Project"
}

$smDir = Get-ChildItem $Project -Directory -Filter '*.SemanticModel' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($smDir -and -not (Test-Path (Join-Path $smDir.FullName 'definition.pbism'))) {
    Write-Warning "Semantic model missing definition.pbism"
}

if ($bad.Count -eq 0) {
    Write-Output "[OK] All JSON parsed (UTF-8); basic structure checked: $Project"
} else {
    Write-Output "[FAIL] $($bad.Count) file(s) broken, see warnings above."
    exit 1
}
