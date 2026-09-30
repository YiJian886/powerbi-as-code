#Requires -Version 5.1
<#
    build-from-spec.ps1 的测试。

    思路：拿 examples/spec-sample.json 生成一个工程，然后
      - 结构类断言（目录齐全、JSON 合法、不留模板残渣）
      - 黄金文件对比（TMDL / pages.json / 视觉投影摘要）

    黄金文件里的内容都是确定的（生成过程没有随机性），所以可以逐字节比。
    要更新黄金文件：.\tests\run-tests.ps1 -UpdateGolden
#>

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent $PSScriptRoot
    $script:ScriptsDir = Join-Path $RepoRoot 'scripts'
    $script:Builder    = Join-Path $ScriptsDir 'build-from-spec.ps1'
    $script:SpecPath   = Join-Path $RepoRoot 'examples\spec-sample.json'
    $script:GoldenDir  = Join-Path $PSScriptRoot 'expected'
    $script:UpdateGolden = ($env:PBIW_UPDATE_GOLDEN -eq '1')

    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pbiw-gen-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $script:OutRoot = Join-Path $script:WorkDir 'out'
    New-Item -ItemType Directory -Force -Path $script:OutRoot | Out-Null

    # 生成
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Builder -Spec $SpecPath -OutRoot $OutRoot 2>&1 | Out-String)
        $script:BuildCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }

    $script:Proj      = Join-Path $OutRoot 'SalesDash'
    $script:ReportDir = Join-Path $Proj 'SalesDash.Report'
    $script:SmDir     = Join-Path $Proj 'SalesDash.SemanticModel'

    # 把生成结果压成「确定的、可比的」摘要。
    # 直接比整个 visual.json 不好 —— 15KB 里大部分是从模板继承来的样式，
    # 真正由 spec 决定的只有 name / position / visualType / 各角色的投影。
    function Get-VisualSummary {
        param([string]$VisualFile)
        $o = Get-Content $VisualFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $roles = [ordered]@{}
        foreach ($role in $o.visual.query.queryState.PSObject.Properties) {
            $proj = @()
            foreach ($p in $role.Value.projections) {
                $entry = [ordered]@{ queryRef = $p.queryRef; nativeQueryRef = $p.nativeQueryRef }
                if ($p.field.Aggregation) { $entry['Function'] = $p.field.Aggregation.Function }
                $proj += $entry
            }
            $roles[$role.Name] = $proj
        }
        return [ordered]@{
            name       = $o.name
            visualType = $o.visual.visualType
            position   = "$($o.position.x),$($o.position.y) $($o.position.width)x$($o.position.height)"
            hasFilter  = [bool]$o.PSObject.Properties['filterConfig']
            sortBy     = if ($o.visual.query.sortDefinition) { $o.visual.query.sortDefinition.sort[0].direction } else { $null }
            roles      = $roles
        }
    }

    function Get-GeneratedSummary {
        $visuals = [ordered]@{}
        $pagesDir = Join-Path $ReportDir 'definition\pages'
        foreach ($pd in (Get-ChildItem $pagesDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
            foreach ($vf in (Get-ChildItem $pd.FullName -Recurse -Filter 'visual.json' -ErrorAction SilentlyContinue | Sort-Object FullName)) {
                $visuals[$vf.BaseName + '@' + $pd.Name] = Get-VisualSummary -VisualFile $vf.FullName
            }
        }
        return $visuals
    }

    function Compare-OrUpdateGolden {
        param([string]$Name, [string]$Actual)
        New-Item -ItemType Directory -Force -Path $GoldenDir | Out-Null
        $goldenPath = Join-Path $GoldenDir $Name
        if ($UpdateGolden -or -not (Test-Path $goldenPath)) {
            [System.IO.File]::WriteAllText($goldenPath, $Actual, (New-Object System.Text.UTF8Encoding($false)))
            return $true
        }
        $expected = Get-Content $goldenPath -Raw -Encoding UTF8
        return ($expected -eq $Actual)
    }

    function Read-OrUpdateGolden {
        param([string]$Name, [string]$Actual)
        $null = Compare-OrUpdateGolden -Name $Name -Actual $Actual
        $p = Join-Path $GoldenDir $Name
        if (Test-Path $p) { return (Get-Content $p -Raw -Encoding UTF8) }
        return $null
    }
}

AfterAll {
    if ($script:WorkDir -and (Test-Path $script:WorkDir)) {
        Remove-Item $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ═══════════════════════════════════════════════════════════════
Describe 'build-from-spec.ps1 生成器' {

    It '生成过程退出码为 0' {
        $BuildCode | Should -Be 0
    }

    It '生成的结构完整' {
        (Test-Path (Join-Path $Proj 'SalesDash.pbip'))                 | Should -BeTrue
        (Test-Path (Join-Path $ReportDir 'definition\report.json'))     | Should -BeTrue
        (Test-Path (Join-Path $ReportDir 'definition\pages\pages.json'))| Should -BeTrue
        (Test-Path (Join-Path $SmDir 'definition.pbism'))               | Should -BeTrue
        (Test-Path (Join-Path $SmDir 'definition\tables'))              | Should -BeTrue
    }

    It '所有生成的 JSON 可解析且无 BOM' {
        foreach ($j in (Get-ChildItem $Proj -Recurse -File -Filter *.json)) {
            { Get-Content $j.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Should -Not -Throw
            $b = [System.IO.File]::ReadAllBytes($j.FullName)
            ($b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191) | Should -BeFalse -Because "Power BI 不认带 BOM 的 JSON：$($j.Name)"
        }
    }

    It '中文没有被转义成 \uXXXX（否则「可读可 diff」就没意义了）' {
        $raw = Get-Content (Join-Path $ReportDir 'definition\pages\Overview\visuals\chart_amount_by_channel\visual.json') -Raw -Encoding UTF8
        $raw | Should -Match '渠道'
        $raw | Should -Not -Match '\\u6e20'   # 「渠」的转义形式
    }

    It '不残留模板自己的表名与列名' {
        # 模板的 filterConfig / queryState 引用的是模板那份数据的列。
        # 样例 spec 刻意用了完全不同的表名列名，所以这里出现任何一个都是残留。
        $templateNames = @('销售明细', '销售额', '订单数量', '客户编号')
        foreach ($vf in (Get-ChildItem $ReportDir -Recurse -Filter 'visual.json')) {
            $raw = Get-Content $vf.FullName -Raw -Encoding UTF8
            foreach ($n in $templateNames) {
                $raw | Should -Not -Match $n -Because "「$n」只存在于模板的示例数据里，出现在生成结果里说明有残留没清"
            }
        }
    }

    It 'TMDL 与黄金文件一致' {
        $tmdlPath = Join-Path $SmDir 'definition\tables\成交记录.tmdl'
        (Test-Path $tmdlPath) | Should -BeTrue
        $actual = (Get-Content $tmdlPath -Raw -Encoding UTF8).Replace("`r`n", "`n")

        $expected = Read-OrUpdateGolden -Name 'SalesDash.tmdl' -Actual $actual
        $actual | Should -Be $expected -Because 'TMDL 生成结果变了。确认是有意改动后再跑 -UpdateGolden'
    }

    It 'pages.json 与黄金文件一致' {
        $actual = (Get-Content (Join-Path $ReportDir 'definition\pages\pages.json') -Raw -Encoding UTF8).Replace("`r`n", "`n")
        $expected = Read-OrUpdateGolden -Name 'SalesDash.pages.json' -Actual $actual
        $actual | Should -Be $expected
    }

    It '视觉投影摘要与黄金文件一致' {
        $summary = (Get-GeneratedSummary | ConvertTo-Json -Depth 10)
        $expected = Read-OrUpdateGolden -Name 'SalesDash.visuals.json' -Actual $summary
        $summary | Should -Be $expected -Because 'spec 里定义的视觉投影变了'
    }
}

# ═══════════════════════════════════════════════════════════════
Describe 'build-from-spec.ps1 的错误处理' {

    It 'spec 文件不存在时报错' {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            $null = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Builder -Spec (Join-Path $WorkDir 'nope.json') 2>&1 | Out-String)
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $prev }
        $code | Should -Not -Be 0
    }

    It 'spec 缺必填字段时报错（而不是生成半个工程）' {
        $bad = Join-Path $WorkDir 'bad-spec.json'
        '{ "name": "X" }' | Set-Content $bad -Encoding UTF8
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Builder -Spec $bad -OutRoot $OutRoot 2>&1 | Out-String)
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $prev }
        $code | Should -Not -Be 0
        $out | Should -Match 'dataSource|缺少'
    }

    It 'spec 不是合法 JSON 时报错' {
        $bad = Join-Path $WorkDir 'broken.json'
        '{ 这不是 JSON' | Set-Content $bad -Encoding UTF8
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            $null = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Builder -Spec $bad 2>&1 | Out-String)
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $prev }
        $code | Should -Not -Be 0
    }

    It '不支持的聚合方式时报错' {
        $bad = Join-Path $WorkDir 'bad-agg.json'
        @'
{
  "name": "BadAgg",
  "dataSource": { "kind": "csv", "path": "x.csv" },
  "model": { "table": "T", "columns": [ { "name": "C", "dataType": "string" } ] },
  "pages": [ { "name": "P", "visuals": [ {
      "name": "v1", "type": "clusteredBarChart",
      "position": { "x": 0, "y": 0, "width": 100, "height": 100 },
      "roles": { "Category": [ { "column": "C" } ], "Y": [ { "column": "C", "aggregation": "不存在的聚合" } ] }
  } ] } ]
}
'@ | Set-Content $bad -Encoding UTF8
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Builder -Spec $bad -OutRoot $OutRoot 2>&1 | Out-String)
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $prev }
        $code | Should -Not -Be 0
    }
}
