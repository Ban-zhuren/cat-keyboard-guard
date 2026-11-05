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

$buildBase = $env:TEMP
if ($buildBase -match '[^\x00-\x7F]') {
    $buildBase = Join-Path $env:WINDIR 'Temp'
}
$buildDirectory = Join-Path $buildBase ('CatKeyboardGuard-' + [Guid]::NewGuid().ToString('N'))
$buildSource = Join-Path $buildDirectory 'CatKeyboardGuard.cs'
$buildIcon = Join-Path $buildDirectory 'cat-head.ico'
$buildOutput = Join-Path $buildDirectory 'CatKeyboardGuard.exe'

New-Item -ItemType Directory -Path $buildDirectory | Out-Null
try {
    Copy-Item -LiteralPath $sourcePath -Destination $buildSource
    Copy-Item -LiteralPath $iconPath -Destination $buildIcon

    $compilerArguments = @(
        '/nologo',
        '/target:winexe',
        '/platform:anycpu',
        '/optimize+',
        ('/win32icon:' + $buildIcon),
        ('/out:' + $buildOutput),
        ('/reference:' + $automationAssembly),
        $buildSource
    )

    & $compilerPath $compilerArguments
    if ($LASTEXITCODE -ne 0) { throw "编译失败，退出码：$LASTEXITCODE" }

    try {
        Copy-Item -LiteralPath $buildOutput -Destination $outputPath -Force
    }
    catch [System.IO.IOException] {
        throw '无法替换 CatKeyboardGuard.exe。请先从系统托盘退出正在运行的程序，然后重新构建。'
    }
}
finally {
    Remove-Item -LiteralPath $buildDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output $outputPath
