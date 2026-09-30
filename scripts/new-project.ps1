# new-project.ps1 - scaffold a new PBIP report project from templates
# Usage: powershell -ExecutionPolicy Bypass -File scripts/new-project.ps1 -Name SalesDash [-Force]
param(
    [Parameter(Mandatory = $true)][string]$Name,

    # 输出根目录。默认 <仓库>\projects
    [string]$OutRoot,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
$tmpl = Join-Path $workspace 'templates\pbir'
if (-not $OutRoot) { $OutRoot = Join-Path $workspace 'projects' }
if (-not (Test-Path $OutRoot)) { New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null }
$dst = Join-Path $OutRoot $Name

if (-not (Test-Path $tmpl)) { throw "Template dir missing: $tmpl" }
if (Test-Path $dst) {
    if (-not $Force) { throw "Target exists: $dst (add -Force to overwrite)" }
    Remove-Item $dst -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $dst | Out-Null

$reportDir = Join-Path $dst "$Name.Report"
$smDir     = Join-Path $dst "$Name.SemanticModel"

# 1) report side: copy template tree
Copy-Item (Join-Path $tmpl 'MyReport.Report') $reportDir -Recurse

# 2) project entry .pbip
$pbip = (Get-Content -Raw (Join-Path $tmpl 'MyReport.pbip')) -replace 'MyReport\.Report', "$Name.Report"
[System.IO.File]::WriteAllText((Join-Path $dst "$Name.pbip"), $pbip, (New-Object System.Text.UTF8Encoding($false)))

# 3) fix reference to semantic model inside definition.pbir
$dp = Join-Path $reportDir 'definition.pbir'
$content = (Get-Content -Raw $dp) -replace 'MyReport\.SemanticModel', "$Name.SemanticModel"
[System.IO.File]::WriteAllText($dp, $content, (New-Object System.Text.UTF8Encoding($false)))

# 4) semantic model skeleton
New-Item -ItemType Directory -Force -Path (Join-Path $smDir 'definition\tables') | Out-Null
$pbism = @'
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/semanticModel/definitionProperties/1.0.0/schema.json",
  "version": "4.2",
  "settings": {}
}
'@
[System.IO.File]::WriteAllText((Join-Path $smDir 'definition.pbism'), $pbism, (New-Object System.Text.UTF8Encoding($false)))

Write-Output "Project created: $dst"
Write-Output "  report: $reportDir   (PBIR pages/visuals JSON)"
Write-Output "  model:  $smDir       (TMDL: definition\tables\*.tmdl)"
Write-Output "  entry:  $dst\$Name.pbip   (double-click to open in Power BI Desktop)"
Write-Output ""
Write-Output "Next: add tables/columns/measures + M partitions per templates\tmdl\semantic-model-reference.md,"
Write-Output "      then lay out pages per templates\pbir\NOTES.md (copy same-type visual.json first)."
