#Requires -Version 5.1
<#
    powerbi-as-code 测试集。

    分四组：
      仓库约定   —— BOM、换行、真实数据不入库这类「不写测试就一定会违反」的规则
      模板完整性 —— 模板工程的必备文件和 schema 版本，含「文档与模板是否同步」的防漂移检查
      脚手架     —— new-project.ps1 生成的结构是否完整可用
      校验脚本   —— validate-json.ps1 能否通过合法工程、能否检出坏 JSON（负面测试）

    跑法：.\tests\run-tests.ps1
#>

BeforeAll {
    $script:RepoRoot     = Split-Path -Parent $PSScriptRoot
    $script:ScriptsDir   = Join-Path $RepoRoot 'scripts'
    $script:TemplatesDir = Join-Path $RepoRoot 'templates'
    $script:TemplateReport = Join-Path $TemplatesDir 'pbir\MyReport.Report'
    $script:NotesPath    = Join-Path $TemplatesDir 'pbir\NOTES.md'

    # 测试在自己的临时目录里生成工程，不污染仓库
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pbiw-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

    function Get-BomStatus {
        param([string]$Path)
        $b = [System.IO.File]::ReadAllBytes($Path)
        if ($b.Length -lt 3) { return 'empty' }
        if ($b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191) { return 'bom' }
        return 'none'
    }

    function Get-AllJsonFiles {
        param([string]$Root)
        Get-ChildItem $Root -Recurse -File -Filter *.json -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\seed-extract\\' }
    }
}

AfterAll {
    if ($script:WorkDir -and (Test-Path $script:WorkDir)) {
        Remove-Item $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ═══════════════════════════════════════════════════════════════
Describe '仓库约定' {

    It '所有 .ps1 都是 UTF-8 带 BOM' {
        # PS 5.1 读 .ps1 按 ANSI(GBK) 解码，不带 BOM 的中文会乱码且报错信息本身也是乱码
        $scripts = Get-ChildItem $ScriptsDir -Filter *.ps1 -ErrorAction SilentlyContinue
        $scripts.Count | Should -BeGreaterThan 0

        $bad = @()
        foreach ($s in $scripts) {
            if ((Get-BomStatus $s.FullName) -ne 'bom') { $bad += $s.Name }
        }
        $bad -join ', ' | Should -Be '' -Because '缺 BOM 的脚本在 PS 5.1 下会因中文乱码而语法报错'
    }

    It '所有 JSON 都是 UTF-8 无 BOM' {
        # Power BI 的 JSON 解析器不认 BOM
        $bad = @()
        foreach ($j in (Get-AllJsonFiles -Root $RepoRoot)) {
            if ((Get-BomStatus $j.FullName) -ne 'none') { $bad += $j.FullName.Replace($RepoRoot, '') }
        }
        $bad -join ', ' | Should -Be ''
    }

    It '真实数据文件没有被 git 跟踪' {
        # 基准导出里含真实业务数据，绝不能进版本库
        $gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
        if (-not $gitExe) {
            # Git for Windows 的标准安装位置，PATH 里没有时兜一下
            foreach ($guess in 'C:\Program Files\Git\cmd\git.exe', 'C:\Program Files (x86)\Git\cmd\git.exe') {
                if (Test-Path $guess) { $gitExe = $guess; break }
            }
        }
        if (-not $gitExe) { Set-ItResult -Skipped -Because '环境里没有 git'; return }

        Push-Location $RepoRoot
        try {
            $tracked = & $gitExe ls-files 2>$null
        } finally {
            Pop-Location
        }
        $leaked = @($tracked | Where-Object { $_ -match 'seed\.pbix|seed-extract/' })
        $leaked -join ', ' | Should -Be '' -Because '基准导出含真实业务数据'
    }
}

# ═══════════════════════════════════════════════════════════════
Describe '模板完整性' {

    It '模板工程必备文件齐全' {
        $required = @(
            'MyReport.pbip',
            'MyReport.Report\definition.pbir',
            'MyReport.Report\definition\version.json',
            'MyReport.Report\definition\report.json',
            'MyReport.Report\definition\pages\pages.json'
        )
        $templateRoot = Join-Path $TemplatesDir 'pbir'
        foreach ($r in $required) {
            (Test-Path (Join-Path $templateRoot $r)) | Should -BeTrue -Because "模板缺 $r 就没法脚手架"
        }
    }

    It '模板里所有 JSON 都能解析' {
        $bad = @()
        foreach ($j in (Get-AllJsonFiles -Root (Join-Path $TemplatesDir 'pbir'))) {
            try { $null = Get-Content $j.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
            catch { $bad += "$($j.Name): $($_.Exception.Message)" }
        }
        $bad -join ' | ' | Should -Be ''
    }

    It '视觉样例包含完整的投影结构（不是空壳）' {
        $example = Get-ChildItem (Join-Path $TemplatesDir 'pbir\examples') -Filter '*.visual.json' -ErrorAction SilentlyContinue | Select-Object -First 1
        $example | Should -Not -BeNullOrEmpty

        $raw = Get-Content $example.FullName -Raw -Encoding UTF8
        # 这几个字段是「照着改」能改对的前提，缺一个样例就没参考价值
        $raw | Should -Match 'visualContainer/'
        $raw | Should -Match '"queryState"'
        $raw | Should -Match '"Entity"'
        $raw | Should -Match '"Property"'
    }

    It 'NOTES.md 记录的 schema 版本与模板文件实际一致（防文档漂移）' {
        # 这条测试的意义：文档写 3.3.0 而文件是 3.4.0 这种漂移，人工发现不了，
        # 但会让每一个照着做的人生成打不开的工程。
        $notes = Get-Content $NotesPath -Raw -Encoding UTF8

        $checks = @(
            @{ File = (Join-Path $TemplateReport 'definition\version.json');      Pattern = 'versionMetadata/([\d.]+)'; DocLabel = 'versionMetadata' },
            @{ File = (Join-Path $TemplateReport 'definition\report.json');       Pattern = 'report/([\d.]+)';          DocLabel = 'report' },
            @{ File = (Join-Path $TemplateReport 'definition\pages\pages.json');  Pattern = 'pagesMetadata/([\d.]+)';   DocLabel = 'pagesMetadata' }
        )

        foreach ($c in $checks) {
            if (-not (Test-Path $c.File)) { continue }
            $schema = (Get-Content $c.File -Raw -Encoding UTF8 | ConvertFrom-Json).'$schema'
            $actual = [regex]::Match($schema, $c.Pattern).Groups[1].Value
            $actual | Should -Not -BeNullOrEmpty -Because "$($c.File) 应该带 $($c.Pattern) 形式的 schema"

            # NOTES.md 里应出现这个版本号
            $notes | Should -Match ([regex]::Escape($actual)) -Because "NOTES.md 里没写 $($c.DocLabel) 的 $actual，文档和模板脱节了"
        }
    }
}

# ═══════════════════════════════════════════════════════════════
Describe 'new-project.ps1 脚手架' {

    BeforeAll {
        $script:NewProj = Join-Path $ScriptsDir 'new-project.ps1'
        $script:ProjName = 'TestDash'
        # 脚手架固定输出到 <repo>\projects\，测完删掉
        $script:ProjectsDir = Join-Path $RepoRoot 'projects'
        $script:ProjPath = Join-Path $ProjectsDir $ProjName
        Remove-Item $ProjPath -Recurse -Force -ErrorAction SilentlyContinue

        & powershell -NoProfile -ExecutionPolicy Bypass -File $NewProj -Name $ProjName *> $null
    }

    AfterAll {
        Remove-Item $ProjPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '生成了工程目录' {
        (Test-Path $ProjPath) | Should -BeTrue
    }

    It '三个组成部分齐全（入口 + 报表 + 语义模型）' {
        (Test-Path (Join-Path $ProjPath "$ProjName.pbip"))            | Should -BeTrue
        (Test-Path (Join-Path $ProjPath "$ProjName.Report"))          | Should -BeTrue
        (Test-Path (Join-Path $ProjPath "$ProjName.SemanticModel"))   | Should -BeTrue
    }

    It '报表侧必备文件齐全' {
        $report = Join-Path $ProjPath "$ProjName.Report"
        foreach ($f in 'definition.pbir', 'definition\version.json', 'definition\report.json', 'definition\pages\pages.json') {
            (Test-Path (Join-Path $report $f)) | Should -BeTrue -Because "$f 缺了 Desktop 打不开"
        }
    }

    It '生成的 JSON 全部可解析且无 BOM' {
        foreach ($j in (Get-ChildItem $ProjPath -Recurse -File -Filter *.json)) {
            { Get-Content $j.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Should -Not -Throw
            (Get-BomStatus $j.FullName) | Should -Be 'none' -Because 'Power BI 不认带 BOM 的 JSON'
        }
    }

    It '../ 相对路径在 .pbip 里指向真实存在的目录' {
        # .pbip 用相对路径引用 Report / SemanticModel，写错了 Desktop 会报找不到
        $pbip = Get-Content (Join-Path $ProjPath "$ProjName.pbip") -Raw -Encoding UTF8 | ConvertFrom-Json
        $paths = @($pbip.artifacts | ForEach-Object { $_.report.path }) + @($pbip.artifacts | ForEach-Object { $_.semanticModel.path })
        $paths = @($paths | Where-Object { $_ })
        $paths.Count | Should -BeGreaterThan 0

        foreach ($rel in $paths) {
            $abs = Join-Path $ProjPath $rel
            (Test-Path $abs) | Should -BeTrue -Because ".pbip 里写的 $rel 必须真实存在"
        }
    }
}

# ═══════════════════════════════════════════════════════════════
Describe 'validate-json.ps1 校验脚本' {

    BeforeAll {
        $script:Validate = Join-Path $ScriptsDir 'validate-json.ps1'
        $script:GoodProj = Join-Path $WorkDir 'GoodProj'
        New-Item -ItemType Directory -Force -Path $script:GoodProj | Out-Null
        '{"a": 1}' | Set-Content (Join-Path $GoodProj 'ok.json') -Encoding UTF8
        @{ name = 'p'; pages = @() } | ConvertTo-Json | Set-Content (Join-Path $GoodProj 'report.json') -Encoding UTF8
    }

    It '合法工程校验通过' {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Validate -Project $GoodProj 2>&1 | Out-String)
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $prev }

        $code | Should -Be 0
        $out | Should -Match 'OK'
    }

    It '坏 JSON 能被检出（负面测试）' {
        # 只测「合法能过」是不够的 —— 校验脚本必须真的会拒绝坏输入
        $badProj = Join-Path $WorkDir 'BadProj'
        New-Item -ItemType Directory -Force -Path $badProj | Out-Null
        '{ 这不是合法 JSON' | Set-Content (Join-Path $badProj 'broken.json') -Encoding UTF8

        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $null = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Validate -Project $badProj 2>&1 | Out-String)
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $prev }

        $code | Should -Not -Be 0 -Because '坏 JSON 必须让校验失败'
    }
}

# ═══════════════════════════════════════════════════════════════
Describe 'setup-from-export.ps1 基准提取' {

    BeforeAll {
        $script:Setup = Join-Path $ScriptsDir 'setup-from-export.ps1'

        # 造一份假模板副本 + 假导出，都在临时目录里，绝不碰真实模板
        $script:FakeTemplate = Join-Path $WorkDir 'templates'
        Copy-Item (Join-Path $TemplatesDir 'pbir') $script:FakeTemplate -Recurse -Force
        Remove-Item (Join-Path $script:FakeTemplate 'pbir\MyReport.Report\StaticResources') -Recurse -Force -ErrorAction SilentlyContinue

        # 造一份假导出，结构照真实 Desktop 导出
        $script:FakeExport = Join-Path $WorkDir 'FakeExport'
        $rep = Join-Path $FakeExport 'Fake.Report'
        New-Item -ItemType Directory -Force -Path (Join-Path $rep 'definition\pages\Page1\visuals\V1') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $rep 'StaticResources\SharedResources\BaseThemes') | Out-Null

        $ver = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/versionMetadata/1.0.0/schema.json'
        @{ '$schema' = $ver; version = '2.0.0' } | ConvertTo-Json | Set-Content (Join-Path $rep 'definition\version.json') -Encoding UTF8
        @{ '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/report/3.3.0/schema.json' } |
            ConvertTo-Json | Set-Content (Join-Path $rep 'definition\report.json') -Encoding UTF8
        @{ '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.1.0/schema.json' } |
            ConvertTo-Json | Set-Content (Join-Path $rep 'definition\pages\pages.json') -Encoding UTF8
        @{ '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json' } |
            ConvertTo-Json | Set-Content (Join-Path $rep 'definition\pages\Page1\page.json') -Encoding UTF8
        @{ '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.12.0/schema.json' } |
            ConvertTo-Json | Set-Content (Join-Path $rep 'definition\pages\Page1\visuals\V1\visual.json') -Encoding UTF8
        '{}' | Set-Content (Join-Path $rep 'StaticResources\SharedResources\BaseThemes\FakeTheme.json') -Encoding UTF8
    }

    It '能识别出五个 schema 版本号' {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Setup -ExportPath $FakeExport -TemplateRoot $script:FakeTemplate 2>&1 | Out-String
        foreach ($v in '1.0.0', '3.3.0', '1.1.0', '2.1.0', '2.12.0') {
            $out | Should -Match ([regex]::Escape($v)) -Because "应该报出 $v"
        }
    }

    It '版本一致时退出码为 0' {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $null = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Setup -ExportPath $FakeExport -TemplateRoot $script:FakeTemplate 2>&1 | Out-String)
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $prev }

        $code | Should -Be 0 -Because '假导出用的就是模板同版本，不该报不一致'
    }

    It '路径不存在时明确报错，而不是静默通过' {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $null = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Setup -ExportPath (Join-Path $WorkDir 'NotExist') -TemplateRoot $script:FakeTemplate 2>&1 | Out-String)
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $prev }

        $code | Should -Not -Be 0
    }
}
