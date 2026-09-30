# inspect-project.ps1 - print a project summary (pages / visuals / measures)
# Usage: powershell -ExecutionPolicy Bypass -File scripts/inspect-project.ps1 [-Project projects/SalesDash]
param(
    [string]$Project
)

$workspace = Split-Path $PSScriptRoot -Parent
if (-not $Project) { $Project = Join-Path $workspace 'projects' }

function Read-Utf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

$reportDir = Get-ChildItem $Project -Directory -Filter '*.Report' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $reportDir) { Write-Output "No project or *.Report found: $Project"; return }

$pagesRoot = Join-Path $reportDir.FullName 'definition\pages'
if (Test-Path $pagesRoot) {
    Get-ChildItem $pagesRoot -Directory | ForEach-Object {
        $pg = Join-Path $_.FullName 'page.json'
        if (Test-Path $pg) {
            $p = Read-Utf8 $pg | ConvertFrom-Json
            Write-Output "Page: $($p.displayName)  (folder $($_.Name))"
            $visRoot = Join-Path $_.FullName 'visuals'
            if (Test-Path $visRoot) {
                Get-ChildItem $visRoot -Directory | ForEach-Object {
                    $vj = Join-Path $_.FullName 'visual.json'
                    if (Test-Path $vj) {
                        $v = Read-Utf8 $vj | ConvertFrom-Json
                        Write-Output ("    - {0} : {1}  (x={2} y={3} w={4} h={5})" -f $v.visual.visualType, $v.name, $v.position.x, $v.position.y, $v.position.width, $v.position.height)
                    }
                }
            }
        }
    }
} else {
    Write-Output "No definition\pages in this project (empty skeleton?)"
}

$smDir = Get-ChildItem $Project -Directory -Filter '*.SemanticModel' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($smDir) {
    Write-Output "--- Semantic model ---"
    $tables = Join-Path $smDir.FullName 'definition\tables'
    if (Test-Path $tables) {
        Get-ChildItem $tables -Filter *.tmdl -File | ForEach-Object {
            $txt = Read-Utf8 $_.FullName
            $measures = ([regex]::Matches($txt, "(?m)^\s*measure\s+'?([^'=]+)'?\s*=") | ForEach-Object { $_.Groups[1].Value.Trim() })
            $cols = ([regex]::Matches($txt, "(?m)^\s*column\s+'?([^'=]+)'?") | ForEach-Object { $_.Groups[1].Value.Trim() })
            Write-Output "Table $($_.BaseName): cols[$($cols -join ', ')] measures[$($measures -join ', ')]"
        }
    }
}
