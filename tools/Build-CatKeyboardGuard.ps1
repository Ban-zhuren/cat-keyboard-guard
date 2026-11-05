param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$projectDir = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectDir 'CatKeyboardGuard.cs'
$outputPath = Join-Path $projectDir 'CatKeyboardGuard.exe'
$iconPath = Join-Path $projectDir 'assets\cat-head.ico'

$frameworkRoots = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319')
)
$compilerPath = $frameworkRoots |
    ForEach-Object { Join-Path $_ 'csc.exe' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

$automationAssembly = Get-ChildItem (
    Join-Path $env:WINDIR 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation'
) -Filter 'System.Management.Automation.dll' -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $compilerPath) { throw '找不到 .NET Framework C# 编译器。' }
if (-not $automationAssembly) { throw '找不到 Windows PowerShell 运行库。' }
if (-not (Test-Path -LiteralPath $sourcePath)) { throw "找不到源码：$sourcePath" }
if (-not (Test-Path -LiteralPath $iconPath)) { throw "找不到图标：$iconPath" }

$compilerArguments = @(
    '/nologo',
    '/target:winexe',
    '/platform:anycpu',
    '/optimize+',
    ('/win32icon:' + $iconPath),
    ('/out:' + $outputPath),
    ('/reference:' + $automationAssembly),
    $sourcePath
)

& $compilerPath $compilerArguments
if ($LASTEXITCODE -ne 0) { throw "编译失败，退出码：$LASTEXITCODE" }

Write-Output $outputPath
