#Requires -Version 5.1
<#
.SYNOPSIS
    从一份声明式 spec 生成完整的 Power BI PBIP 工程。

.DESCRIPTION
    这是本仓库的主线工具：把「需求」写成一份 JSON，直接产出可以交给 Desktop 打开的工程。

    流程：
      spec (JSON)
        → 脚手架工程骨架（复用 new-project.ps1）
        → 生成 tmdl（表 / 列 / 度量 / M 分区）
        → 生成 PBIR 页面与视觉（以真实导出样例为投影模板）
        → 输出到 projects/<工程名>/

.PARAMETER Spec
    spec 文件路径（JSON）。格式见 examples/spec-sample.json。

.PARAMETER OutRoot
    输出根目录。默认 <仓库>\projects。

.PARAMETER Force
    目标工程已存在时覆盖。

.EXAMPLE
    .\build-from-spec.ps1 -Spec .\examples\spec-sample.json
.EXAMPLE
    .\build-from-spec.ps1 -Spec .\my.json -OutRoot D:\reports -Force

.NOTES
    为什么 spec 用 JSON 而不是 YAML：PowerShell 5.1 没有内置 YAML 解析器，
    引第三方模块就破坏了本仓库「零依赖」的前提。JSON 原生支持，且 YAML 是
    JSON 的超集，需要 YAML 的话可以自己转一下。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Spec,

    [string]$OutRoot,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutRoot) { $OutRoot = Join-Path $repoRoot 'projects' }

# ═══════════════════════════════════════════════════════════════
# 序列化：Power BI 的 JSON 风格
# ═══════════════════════════════════════════════════════════════
# PowerShell 5.1 的 ConvertTo-Json 会把非 ASCII 转义成 \uXXXX。
# 那虽然仍是合法 JSON，但会让整个仓库「可读、可 diff」的意义消失 ——
# 谁也不想在 code review 里看一串 \u9500\u552e\u989d。
# 所以序列化之后要把转义还原回真实字符，并统一去掉 BOM。
function ConvertTo-PbirJson {
    param([Parameter(Mandatory = $true)]$InputObject)

    $json = $InputObject | ConvertTo-Json -Depth 100

    # \uXXXX -> 真实字符（中文都在 BMP 内，不需要处理代理对）
    $json = [regex]::Replace($json, '\\u([0-9a-fA-F]{4})', {
        param($m) [char][int]("0x" + $m.Groups[1].Value)
    })

    return $json
}

function Write-PbirJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$InputObject
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $json = ConvertTo-PbirJson -InputObject $InputObject
    # 无 BOM：Power BI 的 JSON 解析器不认 BOM
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# ═══════════════════════════════════════════════════════════════
# 投影（projection）：PBIR 里「某个数据角色绑哪一列」的结构
# ═══════════════════════════════════════════════════════════════
# 聚合函数的枚举值。**只有 CountNonNull = 5 是从真实导出里核对过的**，
# 其余按 Analysis Services 的 AggregationFunction 枚举顺序推断，未实测。
# 用到别的聚合时，先在 Desktop 里手动建一个同类型的视觉、导出确认再依赖。
$script:AggregationFunctions = @{
    'Sum'             = 0
    'Average'         = 1
    'Count'           = 2
    'Min'             = 3
    'Max'             = 4
    'CountNonNull'    = 5
    'Median'          = 6
    'StandardDeviation' = 7
    'Variance'        = 8
}

function New-ColumnProjection {
    param(
        [Parameter(Mandatory = $true)][string]$Entity,
        [Parameter(Mandatory = $true)][string]$Column,
        [string]$Aggregation
    )

    $columnExpr = [ordered]@{
        Expression = [ordered]@{ SourceRef = [ordered]@{ Entity = $Entity } }
        Property   = $Column
    }

    if ($Aggregation) {
        if (-not $script:AggregationFunctions.ContainsKey($Aggregation)) {
            throw "不认识的聚合方式 '$Aggregation'。支持：$($script:AggregationFunctions.Keys -join ', ')"
        }
        $fn = $script:AggregationFunctions[$Aggregation]
        $field = [ordered]@{
            Aggregation = [ordered]@{
                Expression = [ordered]@{ Column = $columnExpr }
                Function   = $fn
            }
        }
        $queryRef = "$Aggregation($Entity.$Column)"
        $nativeRef = "$Column 的$Aggregation"
        # 中文化的显示名，跟 Desktop 生成的习惯一致
        $cn = @{ Sum = '求和'; Average = '平均值'; Count = '计数'; Min = '最小值'; Max = '最大值';
                 CountNonNull = '计数'; Median = '中值'; StandardDeviation = '标准差'; Variance = '方差' }
        if ($cn.ContainsKey($Aggregation)) { $nativeRef = "$Column 的$($cn[$Aggregation])" }
    } else {
        $field = [ordered]@{ Column = $columnExpr }
        $queryRef = "$Entity.$Column"
        $nativeRef = $Column
    }

    return [ordered]@{
        field          = $field
        queryRef       = $queryRef
        nativeQueryRef = $nativeRef
    }
}

# ═══════════════════════════════════════════════════════════════
# 从模板生成一个视觉
# ═══════════════════════════════════════════════════════════════
function New-VisualFromTemplate {
    param(
        [Parameter(Mandatory = $true)]$Template,
        [Parameter(Mandatory = $true)]$VisualSpec,
        [Parameter(Mandatory = $true)][string]$Entity,
        [Parameter(Mandatory = $true)][string]$ParentPage
    )

    # 深拷贝模板，避免改到后续复用
    $v = $Template | ConvertTo-Json -Depth 100 | ConvertFrom-Json

    $v.name = $VisualSpec.name
    $v.position = [ordered]@{
        x      = [int]$VisualSpec.position.x
        y      = [int]$VisualSpec.position.y
        z      = 0
        width  = [int]$VisualSpec.position.width
        height = [int]$VisualSpec.position.height
    }
    $v.visual.visualType = $VisualSpec.type

    # 用 spec 里的角色替换模板的 queryState
    $queryState = [ordered]@{}
    $firstRole = $null
    foreach ($role in $VisualSpec.roles.PSObject.Properties) {
        $projections = @()
        foreach ($p in @($role.Value)) {
            $projections += New-ColumnProjection -Entity $Entity -Column $p.column -Aggregation $p.aggregation
        }
        $queryState[$role.Name] = [ordered]@{ projections = $projections }
        if (-not $firstRole) { $firstRole = $role.Name }
    }

    $v.visual.query = [ordered]@{ queryState = $queryState }

    # 模板自带的 filterConfig 引用的是模板那份数据的列（客户编号之类），
    # 对你的模型不一定存在。留着会让 Desktop 报错或静默丢筛选，所以默认删掉。
    # spec 里显式给了 filters 才重新生成。
    if ($v.PSObject.Properties['filterConfig']) { $v.PSObject.Properties.Remove('filterConfig') }
    if ($VisualSpec.filters) {
        $filters = @()
        foreach ($f in @($VisualSpec.filters)) {
            $filters += [ordered]@{
                name    = "filter_" + [guid]::NewGuid().ToString('N').Substring(0, 12)
                field   = (New-ColumnProjection -Entity $Entity -Column $f.column).field
                type    = 'Categorical'
                howCreated = 'User'
                isLocked = $false
                objects = [ordered]@{ general = @([ordered]@{ properties = [ordered]@{} }) }
            }
        }
        $v | Add-Member -NotePropertyName filterConfig -NotePropertyValue ([ordered]@{ filters = $filters }) -Force
    }

    # 排序：模板里有 sortDefinition，指向的字段必须仍然存在，否则删掉整个节点
    if ($VisualSpec.sortBy) {
        $sortProjection = $null
        foreach ($role in $queryState.Keys) {
            foreach ($p in $queryState[$role].projections) {
                if ($p.field.Aggregation -and -not $sortProjection) { $sortProjection = $p }
            }
        }
        if ($sortProjection) {
            $v.visual.query.sortDefinition = [ordered]@{
                sort = @([ordered]@{ field = $sortProjection.field; direction = $VisualSpec.sortBy })
            }
        }
    }

    return $v
}

# ═══════════════════════════════════════════════════════════════
# TMDL：表 / 列 / 度量 / M 分区
# ═══════════════════════════════════════════════════════════════
function New-MPartitionExpression {
    param([Parameter(Mandatory = $true)]$DataSource, [Parameter(Mandatory = $true)][string]$Table)

    $kind = $DataSource.kind
    switch ($kind) {
        'csv' {
            $p = $DataSource.path
            return @"
            let
                Source = Csv.Document(File.Contents("$p"), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
                #"Promoted Headers" = Table.PromoteHeaders(Source, [PromoteAllScalars = true])
            in
                #"Promoted Headers"
"@
        }
        'excel' {
            $p = $DataSource.path
            $sheet = if ($DataSource.sheet) { $DataSource.sheet } else { 'Sheet1' }
            return @"
            let
                Source = Excel.Workbook(File.Contents("$p"), null, true),
                Sheet = Source{[Item = "$sheet", Kind = "Sheet"]}[Data],
                #"Promoted Headers" = Table.PromoteHeaders(Sheet, [PromoteAllScalars = true])
            in
                #"Promoted Headers"
"@
        }
        'mysql' {
            $server = $DataSource.server
            $db = $DataSource.database
            $schema = if ($DataSource.schema) { $DataSource.schema } else { $db }
            return @"
            let
                Source = MySql.Database("$server", "$db"),
                Data = Source{[Schema = "$schema", Item = "$Table"]}[Data]
            in
                Data
"@
        }
        default {
            throw "不支持的数据源类型 '$kind'。支持：csv / excel / mysql"
        }
    }
}

function New-TmdlTable {
    param(
        [Parameter(Mandatory = $true)]$Model,
        [Parameter(Mandatory = $true)]$DataSource
    )

    $table = $Model.table
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("table '$table'")

    foreach ($c in $Model.columns) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("    column '$($c.name)'")
        [void]$sb.AppendLine("        dataType: $($c.dataType)")
        if ($c.formatString) { [void]$sb.AppendLine("        formatString: '$($c.formatString)'") }
        if ($c.summarizeBy)  { [void]$sb.AppendLine("        summarizeBy: $($c.summarizeBy)") }
    }

    if ($Model.measures) {
        foreach ($m in $Model.measures) {
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("    measure '$($m.name)' = $($m.expression)")
            if ($m.formatString) { [void]$sb.AppendLine("        formatString: '$($m.formatString)'") }
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("    partition '$table' = m")
    [void]$sb.AppendLine("        mode: Import")
    [void]$sb.AppendLine("        source =")
    [void]$sb.AppendLine((New-MPartitionExpression -DataSource $DataSource -Table $table).TrimEnd())

    return $sb.ToString()
}

# ═══════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════
if (-not (Test-Path $Spec)) { throw "spec 文件不存在: $Spec" }

try {
    $specObj = Get-Content $Spec -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    throw "spec 不是合法 JSON: $($_.Exception.Message)"
}

foreach ($need in 'name', 'dataSource', 'model', 'pages') {
    if (-not $specObj.PSObject.Properties[$need]) { throw "spec 缺少必填字段: $need" }
}

$name = $specObj.name
Write-Host "工程名: $name"

# 1) 骨架：复用 new-project.ps1，保证两条路径产出的结构一致
#    （注意变量别叫 $args —— 那是 PowerShell 的自动变量）
$newProject = Join-Path $PSScriptRoot 'new-project.ps1'
$newArgs = @{ Name = $name; OutRoot = $OutRoot }
if ($Force) { $newArgs['Force'] = $true }
& $newProject @newArgs | Out-Null

$projPath = Join-Path $OutRoot $name
Write-Host "  输出: $projPath"

$reportDir = Join-Path $projPath "$name.Report"
$smDir     = Join-Path $projPath "$name.SemanticModel"

# 2) 语义模型：TMDL
$tmdl = New-TmdlTable -Model $specObj.model -DataSource $specObj.dataSource
$tmdlPath = Join-Path $smDir "definition\tables\$($specObj.model.table).tmdl"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $tmdlPath) | Out-Null
[System.IO.File]::WriteAllText($tmdlPath, $tmdl, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  TMDL: $($specObj.model.table).tmdl（$(@($specObj.model.columns).Count) 列 / $(@($specObj.model.measures).Count) 度量）"

# 3) 报表：页面与视觉
$templatePath = Join-Path $repoRoot 'templates\pbir\examples\clusteredBarChart.visual.json'
$template = Get-Content $templatePath -Raw -Encoding UTF8 | ConvertFrom-Json

$pagesRoot = Join-Path $reportDir 'definition\pages'
$pageOrder = @()
$activePage = $null
$visualCount = 0

# 清掉骨架里带的示例页
Get-ChildItem $pagesRoot -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force

foreach ($page in $specObj.pages) {
    $pageDir = Join-Path $pagesRoot $page.name
    New-Item -ItemType Directory -Force -Path $pageDir | Out-Null

    # page.json：沿用模板页的 schema，只改 name/displayName
    $pageTemplate = Get-ChildItem (Join-Path $repoRoot 'templates\pbir\MyReport.Report\definition\pages') -Recurse -Filter 'page.json' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pageTemplate) { throw '模板里找不到 page.json' }
    $pageObj = Get-Content $pageTemplate.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $pageObj.name = $page.name
    $pageObj.displayName = if ($page.displayName) { $page.displayName } else { $page.name }
    Write-PbirJson -Path (Join-Path $pageDir 'page.json') -InputObject $pageObj

    foreach ($v in $page.visuals) {
        $visual = New-VisualFromTemplate -Template $template -VisualSpec $v -Entity $specObj.model.table -ParentPage $page.name
        $vDir = Join-Path $pageDir "visuals\$($v.name)"
        Write-PbirJson -Path (Join-Path $vDir 'visual.json') -InputObject $visual
        $visualCount++
    }

    $pageOrder += $page.name
    if (-not $activePage) { $activePage = $page.name }
    Write-Host "  页面: $($page.name)（$(@($page.visuals).Count) 个视觉）"
}

# pages.json：页面顺序
$pagesJsonTemplate = Join-Path $repoRoot 'templates\pbir\MyReport.Report\definition\pages\pages.json'
$pagesObj = Get-Content $pagesJsonTemplate -Raw -Encoding UTF8 | ConvertFrom-Json
$pagesObj.pageOrder = $pageOrder
$pagesObj.activePageName = $activePage
Write-PbirJson -Path (Join-Path $pagesRoot 'pages.json') -InputObject $pagesObj

Write-Host ""
Write-Host "完成：$projPath" -ForegroundColor Green
Write-Host "  $($pageOrder.Count) 个页面 / $visualCount 个视觉"
Write-Host ""
Write-Host "下一步：双击 $name.pbip 在 Desktop 里打开。需要拉数就点「刷新」。"
Write-Host "注意：聚合函数的枚举值只有 CountNonNull(=5) 是从真实导出核对过的，"
Write-Host "      用到别的聚合时请先在 Desktop 里确认一次。"
