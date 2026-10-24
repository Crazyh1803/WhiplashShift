# Runs in PowerShell 5.1+ without network access or a Godot installation.
$ErrorActionPreference = 'Stop'
$Launcher = Join-Path $PSScriptRoot '../whiplash-shift.ps1'
$Fixture = Join-Path ([IO.Path]::GetTempPath()) ('whiplash updater test ' + [Guid]::NewGuid().ToString('N'))
$Installed = Join-Path $Fixture 'installed game'
$Original = Join-Path $Installed 'f3c1b36'
$global:WhiplashTestCalls = @()
$global:WhiplashTestOffline = $false
$global:WhiplashTestImportExit = 0
$global:WhiplashTestLatest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$global:WhiplashTestReleaseUri = ''

function Invoke-RestMethod {
    param($Uri, $TimeoutSec)
    if ($global:WhiplashTestOffline) { throw 'Offline fixture' }
    $global:WhiplashTestReleaseUri = $Uri
    return @{ source_commit = $global:WhiplashTestLatest; source_branch = 'chat/test-feature' }
}
function Invoke-WebRequest {
    param([switch]$UseBasicParsing, $Uri, $OutFile, $TimeoutSec)
    Copy-Item -LiteralPath (Join-Path $Fixture 'source.zip') -Destination $OutFile
}
function Start-Process {
    param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru, $RedirectStandardOutput, $RedirectStandardError)
    $global:WhiplashTestCalls += ,@($ArgumentList)
    if ($PassThru) { return @{ ExitCode = $global:WhiplashTestImportExit } }
}
function Assert-True([bool]$Condition, [string]$Label) {
    if (-not $Condition) { throw "FAIL: $Label" }
    Write-Host "PASS: $Label"
}

try {
    New-Item -ItemType Directory -Path (Join-Path $Original 'Engine') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Original 'Game/godot') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Original 'Engine/Godot_v4.7.2-stable_win64.exe') -Value 'engine fixture'
    Set-Content -LiteralPath (Join-Path $Original 'Game/godot/project.godot') -Value 'original project'
    $Source = Join-Path $Fixture 'source/repository/godot'
    New-Item -ItemType Directory -Path $Source -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Source 'project.godot') -Value 'updated project'
    Set-Content -LiteralPath (Join-Path $Fixture 'source/repository/not-game.txt') -Value 'excluded'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $Fixture 'source'), (Join-Path $Fixture 'source.zip'))

    & $Launcher -NoLaunch -InstallRoot $Installed
    $State = Get-Content -LiteralPath (Join-Path $Installed 'current.json') -Raw | ConvertFrom-Json
    Assert-True ($State.revision -eq $global:WhiplashTestLatest) 'A successful import activates the published revision'
    Assert-True ($global:WhiplashTestReleaseUri -like '*/desktop-preview/*') 'The default shortcut follows the preview manifest rather than main'
    Assert-True ($State.source_branch -eq 'chat/test-feature') 'The active task branch is recorded for diagnostics'
    Assert-True ((Get-Content -LiteralPath (Join-Path $State.project_path 'project.godot')).Trim() -eq 'updated project') 'The project is extracted to a new version'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Split-Path $State.project_path -Parent) 'not-game.txt'))) 'Only game files are extracted'
    Assert-True ((Get-Content -LiteralPath (Join-Path $Original 'Game/godot/project.godot')).Trim() -eq 'original project') 'The original installation is preserved'
    Assert-True ($global:WhiplashTestCalls.Count -eq 1 -and $global:WhiplashTestCalls[0] -contains '--import') 'Asset import runs before activation'

    $global:WhiplashTestCalls = @()
    & $Launcher -InstallRoot $Installed
    Assert-True ($global:WhiplashTestCalls.Count -eq 1 -and $global:WhiplashTestCalls[0] -notcontains '--import') 'An unchanged release launches without another import'
    Assert-True ($global:WhiplashTestCalls[0][1] -eq ('"{0}"' -f $State.project_path)) 'Paths with spaces are quoted for Godot'

    & $Launcher -NoLaunch -Channel stable -InstallRoot $Installed
    Assert-True ($global:WhiplashTestReleaseUri -like '*/main/*') 'Stable mode follows only merged releases'

    $global:WhiplashTestLatest = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    $global:WhiplashTestImportExit = 1
    & $Launcher -NoLaunch -InstallRoot $Installed
    $After = Get-Content -LiteralPath (Join-Path $Installed 'current.json') -Raw | ConvertFrom-Json
    Assert-True ($After.revision -eq $State.revision) 'A failed import keeps the working version active'
    Assert-True (@(Get-ChildItem -LiteralPath $Installed -Filter '.update-*').Count -eq 0) 'Failed staging files are cleaned up'

    $global:WhiplashTestOffline = $true
    $global:WhiplashTestCalls = @()
    & $Launcher -Editor -InstallRoot $Installed
    Assert-True ($global:WhiplashTestCalls.Count -eq 1 -and $global:WhiplashTestCalls[0] -contains '--editor') 'Offline launches use the working version and preserve editor mode'

    $global:WhiplashTestOffline = $false
    $global:WhiplashTestLatest = '../invalid'
    $global:WhiplashTestCalls = @()
    & $Launcher -InstallRoot $Installed
    Assert-True ($global:WhiplashTestCalls.Count -eq 1) 'An invalid release revision cannot replace the installed game'
} finally {
    Remove-Item -LiteralPath $Fixture -Recurse -Force
}
