#Requires -Version 5.1
<#
.SYNOPSIS
    跑全部测试。

.DESCRIPTION
    需要 Pester 5 或更高。没有就自动装到当前用户范围（不需要管理员）。

.PARAMETER Output
    Pester 的输出级别：None / Normal / Detailed / Diagnostic。默认 Normal。

.EXAMPLE
    .\tests\run-tests.ps1
.EXAMPLE
    .\tests\run-tests.ps1 -Output Detailed
#>
[CmdletBinding()]
param(
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Normal'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- 确保有 Pester
$pester = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version.Major -ge 5 } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pester) {
    Write-Host '没找到 Pester 5+，正在安装到当前用户范围...'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
        Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
    } catch {
        Write-Error "装 Pester 失败：$($_.Exception.Message)`n可以手动装：Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0"
        exit 1
    }
    $pester = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version.Major -ge 5 } |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

Import-Module $pester.Path -Force
Write-Host "Pester $($pester.Version)" -ForegroundColor DarkGray
Write-Host ''

# ---------------------------------------------------------------- 跑
$config = New-PesterConfiguration
$config.Run.Path        = $PSScriptRoot
$config.Run.Exit        = $false
$config.Output.Verbosity = $Output
$config.Run.PassThru    = $true

$result = Invoke-Pester -Configuration $config

Write-Host ''
if ($result.FailedCount -gt 0) {
    Write-Host "失败 $($result.FailedCount) 个，通过 $($result.PassedCount) 个。" -ForegroundColor Red
    exit 1
}
Write-Host "全部通过：$($result.PassedCount) 个。" -ForegroundColor Green
exit 0
