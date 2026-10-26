# Runs in PowerShell 5.1+ without network access or a Godot installation.
$ErrorActionPreference = 'Stop'
$Launcher = Join-Path $PSScriptRoot '../whiplash-shift.ps1'
$Fixture = Join-Path ([IO.Path]::GetTempPath()) ('whiplash updater test ' + [Guid]::NewGuid().ToString('N'))
$Installed = Join-Path $Fixture 'installed game'
$Original = Join-Path $Installed 'f3c1b36'
$global:WhiplashTestCalls = @()
$global:WhiplashTestOffline = $false
$global:WhiplashTestImportExit = 0
$global:WhiplashTestImportExits = @()
$global:WhiplashTestSmokeExit = 0
$global:WhiplashTestStyles = @()
$global:WhiplashTestScripts = @()
$global:WhiplashTestWaits = @()
$global:WhiplashTestKills = 0
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
    param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru, $WindowStyle, $RedirectStandardOutput, $RedirectStandardError)
    $global:WhiplashTestCalls += ,@($ArgumentList)
    $global:WhiplashTestStyles += ,$WindowStyle
    if (-not $PassThru) { return }
    $Exit = $global:WhiplashTestImportExit
    $Kind = 'import'
    if ($ArgumentList -contains '--quit-after') {
        $Kind = 'smoke'
        $Exit = $global:WhiplashTestSmokeExit
    } elseif ($global:WhiplashTestImportExits.Count -gt 0) {
        $Exit = $global:WhiplashTestImportExits[0]
        $global:WhiplashTestImportExits = @($global:WhiplashTestImportExits | Select-Object -Skip 1)
    }
    # Optional per-call scripted behaviour: @{ kind; out; err; hang }, consumed in order per kind.
    $Script = $null
    $Match = @($global:WhiplashTestScripts | Where-Object { $_.kind -eq $Kind })
    if ($Match.Count -gt 0) {
        $Script = $Match[0]
        $global:WhiplashTestScripts = @($global:WhiplashTestScripts | Where-Object { -not [object]::ReferenceEquals($_, $Script) })
    }
    if ($Script -and $Script.out -and $RedirectStandardOutput) { Set-Content -LiteralPath $RedirectStandardOutput -Value $Script.out }
    if ($Script -and $Script.err -and $RedirectStandardError) { Set-Content -LiteralPath $RedirectStandardError -Value $Script.err }
    $Hang = [bool]($Script -and $Script.hang)
    # hang: stops responding until Kill is called (termination is delayed, observed by the next wait).
    # stuck: never exits, even after Kill. killfail: Kill throws.
    $Process = [pscustomobject]@{ ExitCode = $Exit; Hang = $Hang; Stuck = [bool]($Script -and $Script.stuck); KillFail = [bool]($Script -and $Script.killfail); Killed = $false; Id = 4242 }
    $Process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
        param($Milliseconds)
        $global:WhiplashTestWaits += ,$Milliseconds
        if ($this.Stuck -or ($this.Hang -and -not $this.Killed)) { return $false }
        return $true
    }
    $Process | Add-Member -MemberType ScriptMethod -Name Kill -Value {
        $global:WhiplashTestKills++
        if ($this.KillFail) { throw 'Access denied' }
        $this.Killed = $true
    }
    return $Process
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
    Add-Type -AssemblyName System.IO.Compression
    # Built explicitly: Windows PowerShell 5.1 CreateFromDirectory writes backslash entry names, unlike GitHub.
    $ZipStream = [IO.File]::Open((Join-Path $Fixture 'source.zip'), [IO.FileMode]::Create)
    $Zip = New-Object IO.Compression.ZipArchive($ZipStream, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($Item in @(@('repository/', ''), @('repository/godot/', ''), @('repository/godot/project.godot', 'updated project'), @('repository/not-game.txt', 'excluded'))) {
            $ZipEntry = $Zip.CreateEntry($Item[0])
            if (-not $Item[0].EndsWith('/')) {
                $Writer = New-Object IO.StreamWriter($ZipEntry.Open())
                $Writer.Write($Item[1] + "`n")
                $Writer.Dispose()
            }
        }
    } finally { $Zip.Dispose(); $ZipStream.Dispose() }

    & $Launcher -NoLaunch -InstallRoot $Installed
    $State = Get-Content -LiteralPath (Join-Path $Installed 'current.json') -Raw | ConvertFrom-Json
    Assert-True ($State.revision -eq $global:WhiplashTestLatest) 'A successful import activates the published revision'
    Assert-True ($global:WhiplashTestReleaseUri -like '*/desktop-preview/*') 'The default shortcut follows the preview manifest rather than main'
    Assert-True ($State.source_branch -eq 'chat/test-feature') 'The active task branch is recorded for diagnostics'
    Assert-True ((Get-Content -LiteralPath (Join-Path $State.project_path 'project.godot')).Trim() -eq 'updated project') 'The project is extracted to a new version'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Split-Path $State.project_path -Parent) 'not-game.txt'))) 'Only game files are extracted'
    Assert-True ((Get-Content -LiteralPath (Join-Path $Original 'Game/godot/project.godot')).Trim() -eq 'original project') 'The original installation is preserved'
    Assert-True ($global:WhiplashTestCalls.Count -eq 2 -and $global:WhiplashTestCalls[0] -contains '--import') 'Asset import runs before activation'
    Assert-True ($global:WhiplashTestCalls[1] -contains '--quit-after') 'A bounded startup check runs after import'
    Assert-True (@($global:WhiplashTestStyles | Where-Object { $_ -eq 'Hidden' }).Count -eq 2) 'Background import and startup check windows are hidden'

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
    $Imports = @($global:WhiplashTestCalls | Where-Object { $_ -contains '--import' })
    Assert-True ($Imports.Count -eq 3 -and @($global:WhiplashTestCalls | Where-Object { $_ -contains '--quit-after' }).Count -eq 0)'A permanently failing import is retried then abandoned without a startup check'
    $Log = Get-Content -LiteralPath (Join-Path $Installed 'launcher.log') -Raw
    Assert-True ($Log -match 'Desired: chat/test-feature at bbbbbbbb' -and $Log -match 'Active: chat/test-feature at aaaaaaaa') 'A failed update logs desired and active revisions'

    $global:WhiplashTestImportExit = 0
    $global:WhiplashTestImportExits = @(-1073741819)
    $global:WhiplashTestCalls = @()
    & $Launcher -NoLaunch -InstallRoot $Installed
    $After = Get-Content -LiteralPath (Join-Path $Installed 'current.json') -Raw | ConvertFrom-Json
    $Staged = @($global:WhiplashTestCalls | Where-Object { $_ -contains '--import' } | ForEach-Object { $_[3] } | Select-Object -Unique)
    Assert-True ($After.revision -eq $global:WhiplashTestLatest) 'A transient import crash is retried and then activates the revision'
    Assert-True (@($global:WhiplashTestCalls | Where-Object { $_ -contains '--import' }).Count -eq 2 -and $Staged.Count -eq 1) 'The retry reuses the same staged project'

    $global:WhiplashTestLatest = 'cccccccccccccccccccccccccccccccccccccccc'
    $global:WhiplashTestSmokeExit = 1
    $global:WhiplashTestCalls = @()
    & $Launcher -NoLaunch -InstallRoot $Installed
    $Kept = Get-Content -LiteralPath (Join-Path $Installed 'current.json') -Raw | ConvertFrom-Json
    Assert-True ($Kept.revision -eq 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb') 'A failed startup check never activates the revision'
    Assert-True (@($global:WhiplashTestCalls | Where-Object { $_ -contains '--quit-after' }).Count -eq 3) 'A failed startup check is retried up to three times'
    $global:WhiplashTestSmokeExit = 0

    # Exit 0 with a fatal marker on stdout during import is retried cleanly in the same staged project.
    $global:WhiplashTestLatest = 'dddddddddddddddddddddddddddddddddddddddd'
    $global:WhiplashTestCalls = @()
    $global:WhiplashTestScripts = @(@{ kind = 'import'; out = "Importing`nSCRIPT ERROR: Parse Error: bad" })
    & $Launcher -NoLaunch -InstallRoot $Installed
    $After = Get-Content -LiteralPath (Join-Path $Installed 'current.json') -Raw | ConvertFrom-Json
    $Staged = @($global:WhiplashTestCalls | Where-Object { $_ -contains '--import' } | ForEach-Object { $_[3] } | Select-Object -Unique)
    Assert-True ($After.revision -eq $global:WhiplashTestLatest -and @($global:WhiplashTestCalls | Where-Object { $_ -contains '--import' }).Count -eq 2 -and $Staged.Count -eq 1) 'Exit 0 with fatal stdout never activates; the retry reuses the staged project'
    Assert-True ($global:WhiplashTestCalls[0] -contains '--quit') 'Headless editor import quits explicitly'

    # Fatal stderr on a successful-exit startup check is retried.
    $global:WhiplashTestLatest = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
    $global:WhiplashTestCalls = @()
    $global:WhiplashTestScripts = @(@{ kind = 'smoke'; err = 'SHADER ERROR: broken' })
    & $Launcher -NoLaunch -InstallRoot $Installed
    $After = Get-Content -LiteralPath (Join-Path $Installed 'current.json') -Raw | ConvertFrom-Json
    Assert-True ($After.revision -eq $global:WhiplashTestLatest -and @($global:WhiplashTestCalls | Where-Object { $_ -contains '--quit-after' }).Count -eq 2) 'Fatal stderr from startup blocks that attempt, then a clean retry activates'

    # Persistent fatal output and hung startup never activate; hung processes are stopped and waits are bounded.
    $global:WhiplashTestLatest = 'ffffffffffffffffffffffffffffffffffffffff'
    $global:WhiplashTestCalls = @()
    $global:WhiplashTestWaits = @()
    $global:WhiplashTestKills = 0
    $global:WhiplashTestScripts = @(@{ kind = 'smoke'; hang = $true }, @{ kind = 'smoke'; hang = $true }, @{ kind = 'smoke'; hang = $true })
    & $Launcher -NoLaunch -InstallRoot $Installed
    $Kept = Get-Content -LiteralPath (Join-Path $Installed 'current.json') -Raw | ConvertFrom-Json
    Assert-True ($Kept.revision -eq 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee') 'A hung startup check never activates the revision'
    Assert-True ($global:WhiplashTestKills -eq 3 -and @($global:WhiplashTestWaits | Where-Object { $_ -eq 60000 }).Count -eq 3 -and @($global:WhiplashTestWaits | Where-Object { $_ -eq 180000 }).Count -eq 3) 'Hung processes are stopped after bounded waits and retried'
    Assert-True (@($global:WhiplashTestWaits | Where-Object { $_ -eq 10000 }).Count -eq 3) 'Delayed termination is confirmed by a bounded wait after each Kill'
    Assert-True (@(Get-ChildItem -LiteralPath $Installed -Filter '.update-*').Count -eq 0) 'Staging is cleaned up after a timeout'
    $global:WhiplashTestScripts = @()

    # Delayed termination is confirmed by a bounded wait; a process that survives Kill or refuses it aborts without retry.
    foreach ($Case in @(@{ Name = 'does not exit after Kill'; Script = @{ kind = 'smoke'; hang = $true; stuck = $true } }, @{ Name = 'cannot be killed'; Script = @{ kind = 'smoke'; hang = $true; killfail = $true } })) {
        $global:WhiplashTestLatest = ('1' * 40)
        $global:WhiplashTestCalls = @()
        $global:WhiplashTestWaits = @()
        $global:WhiplashTestKills = 0
        $global:WhiplashTestScripts = @($Case.Script)
        & $Launcher -NoLaunch -InstallRoot $Installed
        $Kept = Get-Content -LiteralPath (Join-Path $Installed 'current.json') -Raw | ConvertFrom-Json
        Assert-True ($Kept.revision -eq 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee') "A process that $($Case.Name) never activates"
        Assert-True (@($global:WhiplashTestCalls | Where-Object { $_ -contains '--quit-after' }).Count -eq 1 -and @($global:WhiplashTestCalls | Where-Object { $_ -contains '--import' }).Count -eq 1) "A process that $($Case.Name) aborts instead of retrying"
        Assert-True ($global:WhiplashTestKills -eq 1) "Kill is attempted once when the process $($Case.Name)"
        $Preserved = @(Get-ChildItem -LiteralPath $Installed -Filter '.update-*')
        Assert-True ($Preserved.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $Preserved[0].FullName 'Game/godot/project.godot'))) "Staging is preserved, not removed, when the process $($Case.Name)"
        $CaseLog = Get-Content -LiteralPath (Join-Path $Installed 'launcher.log') -Raw
        Assert-True ($CaseLog.Contains('PID 4242') -and $CaseLog.Contains($Preserved[0].FullName)) "The PID and preserved staging path are logged when the process $($Case.Name)"
        Remove-Item -LiteralPath $Preserved[0].FullName -Recurse -Force
    }
    Assert-True (@($global:WhiplashTestWaits | Where-Object { $_ -eq 10000 }).Count -eq 0) 'No post-kill wait is made when Kill itself fails'
    $global:WhiplashTestScripts = @()

    # Native regression: real redirected processes must report real exit codes under Windows PowerShell 5.1.
    $StepAst = [Management.Automation.Language.Parser]::ParseFile((Resolve-Path $Launcher).Path, [ref]$null, [ref]$null)
    $StepText = $StepAst.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-GodotStep' }, $true).Extent.Text
    $WinPs = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $Cmd = Join-Path $env:SystemRoot 'System32/cmd.exe'
    if ((Test-Path -LiteralPath $WinPs) -and (Test-Path -LiteralPath $Cmd)) {
        $NativeDir = Join-Path $Fixture 'native'
        New-Item -ItemType Directory -Path $NativeDir | Out-Null
        $NativeScript = Join-Path $NativeDir 'native.ps1'
        Set-Content -LiteralPath $NativeScript -Value @(
            "`$EnginePath = '$Cmd'", $StepText,
            "foreach (`$Code in 0, 3) { `$R = Invoke-GodotStep @('/c', ('exit ' + `$Code)) '$NativeDir/o.log' '$NativeDir/e.log' 30000; Write-Output ('EXIT=' + `$R.ExitCode + ' TIMEDOUT=' + `$R.TimedOut) }"
        )
        $Native = @(& $WinPs -NoProfile -ExecutionPolicy Bypass -File $NativeScript) -join ' '
        Assert-True ($Native -eq 'EXIT=0 TIMEDOUT=False EXIT=3 TIMEDOUT=False') "Windows PowerShell reports real exit codes 0 and 3 from redirected native processes (got: $Native)"
    } else {
        Write-Host 'SKIP: Windows PowerShell or cmd.exe not found for the native exit-code regression'
    }

    # The path guard refuses anything outside, or equal to, the install root.
    $GuardAst = [Management.Automation.Language.Parser]::ParseFile((Resolve-Path $Launcher).Path, [ref]$null, [ref]$null)
    $GuardText = $GuardAst.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Assert-InsideRoot' }, $true).Extent.Text
    . ([scriptblock]::Create($GuardText))
    function Test-Guard($Path) { try { Assert-InsideRoot $Path $Installed; $true } catch { $false } }
    Assert-True (Test-Guard (Join-Path $Installed 'Versions/x')) 'The guard allows a path inside the install root'
    Assert-True (-not (Test-Guard $Installed)) 'The guard refuses the install root itself'
    Assert-True (-not (Test-Guard (Join-Path $Installed '../elsewhere'))) 'The guard refuses a path that escapes via ..'
    Assert-True (-not (Test-Guard ($Installed + '-sibling/x'))) 'The guard refuses a sibling with a shared prefix'

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
