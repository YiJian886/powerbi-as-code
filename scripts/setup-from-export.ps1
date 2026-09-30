#Requires -Version 5.1
<#
.SYNOPSIS
    从你自己的 Power BI Desktop 导出里提取 schema 版本和主题，校准模板。

.DESCRIPTION
    本仓库的模板是照着某一份 PBIP 导出冻结的。如果你的 Desktop 版本不同，
    schema 版本号可能对不上，生成的工程会打不开或者静默丢内容。

    这个脚本读你导出的工程，把各文件的 $schema 版本号打出来，跟模板里的对比，
    差异标红；顺便把主题文件复制到模板目录。

    不修改你的导出，也不动模板里已冻结的值 —— 只报告 + 复制主题。
    确认要更新版本表的话，自己改 templates/pbir/NOTES.md。

.PARAMETER ExportPath
    你的导出目录。可以是：
      - 工程根目录（里面有 *.pbip）
      - 或者直接是 <工程>.Report 目录

.PARAMETER Apply
    把提取到的版本号写入 templates/pbir/NOTES.md 的版本表。
    不加这个开关就只报告不改。

.EXAMPLE
    .\setup-from-export.ps1 -ExportPath 'C:\Users\me\Documents\MyReport'
.EXAMPLE
    .\setup-from-export.ps1 -ExportPath 'C:\Users\me\Documents\MyReport' -Apply
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExportPath,

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$templateReport = Join-Path $repoRoot 'templates\pbir\MyReport.Report'
$notesPath = Join-Path $repoRoot 'templates\pbir\NOTES.md'

# ---------------------------------------------------------------- 定位 Report 目录
function Resolve-ReportDir {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "路径不存在: $Path" }

    # 情况一：给的目录本身就是 Report 目录（里面有 definition/report.json）
    if (Test-Path (Join-Path $Path 'definition\report.json')) { return (Resolve-Path $Path).Path }

    # 情况二：给的是工程根目录，找里面的 *.Report
    $sub = Get-ChildItem $Path -Directory -Filter '*.Report' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sub) { return $sub.FullName }

    # 情况三：从 .pbix 解压出来的目录（Report 不带前缀）
    $plain = Join-Path $Path 'Report'
    if (Test-Path (Join-Path $plain 'definition\report.json')) { return (Resolve-Path $plain).Path }

    throw "在 '$Path' 下没找到 *.Report 目录。请指向 Power BI 导出的工程根目录，或者直接指向 <工程>.Report。"
}

$reportDir = Resolve-ReportDir -Path $ExportPath
Write-Host "导出目录: $reportDir"
Write-Host ""

# ---------------------------------------------------------------- 读版本号
# 两边都用同一个函数取值，避免拿苹果比橘子
function Get-SchemaSignature {
    param([string]$File)
    if (-not $File -or -not (Test-Path $File)) { return $null }
    try {
        $o = Get-Content $File -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return '(JSON 解析失败)'
    }
    $sig = $null
    $schema = $o.'$schema'
    if ($schema -and $schema -match '/([^/]+)/([\d.]+)/schema\.json$') {
        $sig = "$($Matches[1]) / $($Matches[2])"
    } elseif ($schema) {
        $sig = "(未识别的 schema: $schema)"
    }
    # version.json 除了 $schema 还有个 version 字段，一起报出来
    if ($o.PSObject.Properties['version'] -and $o.version) {
        $sig = if ($sig) { "$sig  (version=$($o.version))" } else { "version=$($o.version)" }
    }
    return $sig
}

# 在一个目录树里找第一份某类文件。视觉样例可能叫 xxx.visual.json，所以模式放宽。
function Find-ReportFile {
    param([string]$Root, [string[]]$Filter)
    if (-not $Root -or -not (Test-Path $Root)) { return $null }
    foreach ($pat in $Filter) {
        $f = Get-ChildItem $Root -Recurse -File -Filter $pat -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    return $null
}

# 五个角色的文件，两边按同样的方式找、同样的方式取值
$roles = @(
    @{ Label = 'definition/version.json';      Filter = 'version.json' },
    @{ Label = 'definition/report.json';       Filter = 'report.json' },
    @{ Label = 'definition/pages/pages.json';  Filter = 'pages.json' },
    @{ Label = 'page.json';                    Filter = 'page.json' },
    @{ Label = 'visual.json';                  Filter = @('visual.json', '*.visual.json') }
)

$templateExamples = Join-Path $repoRoot 'templates\pbir\examples'

function Get-RoleTable {
    param([string]$ReportRoot, [string]$VisualRoot)
    $t = [ordered]@{}
    foreach ($r in $roles) {
        $isVisual = ($r.Filter -join ',') -match 'visual\.json'
        $root = if ($isVisual -and $VisualRoot) { $VisualRoot } else { $ReportRoot }
        $file = Find-ReportFile -Root $root -Filter $r.Filter
        $t[$r.Label] = Get-SchemaSignature -File $file
    }
    return $t
}

$theirs = Get-RoleTable -ReportRoot $reportDir -VisualRoot $reportDir
$ours   = Get-RoleTable -ReportRoot $templateReport -VisualRoot $templateExamples

Write-Host '=== 你的导出 ==='
foreach ($k in $theirs.Keys) {
    $v = if ($theirs[$k]) { $theirs[$k] } else { '(没有这个文件)' }
    Write-Host ("  {0,-32} {1}" -f $k, $v)
}
Write-Host ''

Write-Host '=== 和模板对比 ==='
$mismatch = 0
foreach ($k in $roles.Label) {
    $a = $ours[$k]; $b = $theirs[$k]
    if (-not $a) { Write-Host ("  {0,-32} 模板里没有，跳过" -f $k); continue }
    if ($a -eq $b) {
        Write-Host ("  {0,-32} 一致   {1}" -f $k, $a)
    } else {
        $mismatch++
        Write-Warning ("{0}`n      模板: {1}`n      你的: {2}" -f $k, $a, $b)
    }
}
Write-Host ''
# ---------------------------------------------------------------- 复制主题
$themeSrc = Join-Path $reportDir 'StaticResources\SharedResources\BaseThemes'
$themeDst = Join-Path $templateReport 'StaticResources\SharedResources\BaseThemes'

if (Test-Path $themeSrc) {
    if (-not (Test-Path $themeDst)) { New-Item -ItemType Directory -Force -Path $themeDst | Out-Null }
    $copied = 0
    foreach ($f in (Get-ChildItem $themeSrc -File)) {
        Copy-Item $f.FullName -Destination $themeDst -Force
        $copied++
        Write-Host "  已复制主题: $($f.Name)"
    }
    if ($copied -eq 0) { Write-Host '  你的导出里没有主题文件（可能是默认主题）' }
} else {
    Write-Host "  你的导出里没有 BaseThemes 目录，跳过主题复制。"
    Write-Host "  （如果是默认主题，Desktop 不会导出这个目录，不影响使用。）"
}

Write-Host ''
if ($mismatch -eq 0) {
    Write-Host '结论：你的 Desktop 版本和模板一致，可以直接用。' -ForegroundColor Green
    exit 0
}

Write-Warning "有 $mismatch 处版本不一致。"
Write-Host '要把你的版本写进模板的版本表，加 -Apply；或者自己改 templates/pbir/NOTES.md。'
Write-Host '（建议先按新版本生成一个最小工程，在 Desktop 里打开确认没问题再改模板。）'

if (-not $Apply) { exit 0 }

# ---------------------------------------------------------------- 写回 NOTES.md
if (-not (Test-Path $notesPath)) { throw "找不到 $notesPath" }

$lines = [System.IO.File]::ReadAllLines($notesPath, [System.Text.Encoding]::UTF8)
$out = New-Object System.Collections.Generic.List[string]
$inTable = $false
$updated = 0

foreach ($line in $lines) {
    if ($line -match '^\|\s*`?definition/version\.json`?\s*\|') {
        $inTable = $true
        $out.Add("| ``definition/version.json`` | versionMetadata/1.0.0, ``""version"": ""2.0.0""`` |")
        continue
    }
    if ($inTable -and $line -match '^\|\s*`?(definition/report\.json|definition/pages/pages\.json|页面 page\.json|视觉 visual\.json)`?\s*\|') {
        $key = switch -Regex ($line) {
            'report\.json'  { 'definition/report.json'; break }
            'pages\.json'   { 'definition/pages/pages.json'; break }
            'page\.json'    { 'page.json'; break }
            'visual\.json'  { 'visual.json'; break }
        }
        $label = switch -Regex ($line) {
            'report\.json'  { 'definition/report.json'; break }
            'pages\.json'   { 'definition/pages/pages.json'; break }
            'page\.json'    { '页面 page.json'; break }
            'visual\.json'  { '视觉 visual.json'; break }
        }
        $val = $found[$key]
        if ($val -and $val -notmatch '^\(') {
            $v = $val -replace '^[^/]+/\s*', ''
            $out.Add("| $label | **$v** |")
            $updated++
            continue
        }
    }
    if ($inTable -and $line -notmatch '^\|') { $inTable = $false }
    $out.Add($line)
}

[System.IO.File]::WriteAllLines($notesPath, $out, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "已更新 $notesPath 中的 $updated 行。" -ForegroundColor Green
