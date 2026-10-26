param(
    [switch]$Install,
    [switch]$NoLaunch,
    [switch]$Editor,
    [ValidateSet('preview', 'stable')]
    [string]$Channel = 'preview',
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'WhiplashShift')
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$Repository = 'Crazyh1803/WhiplashShift'
$StatePath = Join-Path $InstallRoot 'current.json'
$LogPath = Join-Path $InstallRoot 'launcher.log'
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

function Write-LauncherLog([string]$Message) {
    Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format s) $Message"
    Write-Host $Message
}

# Throws unless Path resolves strictly inside Root (never Root itself).
function Assert-InsideRoot([string]$Path, [string]$Root) {
    $FullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $FullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $Prefixes = @(($FullRoot + [IO.Path]::DirectorySeparatorChar), ($FullRoot + [IO.Path]::AltDirectorySeparatorChar))
    $Inside = $false
    foreach ($Prefix in $Prefixes) {
        if ($FullPath.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) { $Inside = $true }
    }
    if (-not $Inside) { throw "Refusing to touch a path outside the install folder: $FullPath" }
}

# Runs Godot without -Wait so a hung process can be stopped after TimeoutMs.
function Invoke-GodotStep([string[]]$Arguments, [string]$OutLog, [string]$ErrLog, [int]$TimeoutMs) {
    $Process = Start-Process -FilePath $EnginePath -ArgumentList $Arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog
    # Windows PowerShell 5.1: with redirected output, ExitCode can read null after WaitForExit unless the handle was opened right after start.
    $null = $Process.Handle
    $ProcessId = $Process.Id
    if (-not $Process.WaitForExit($TimeoutMs)) {
        # Kill is asynchronous: confirm the process is gone before anyone retries in the same project.
        $KillFailed = $false
        try { $Process.Kill() } catch { $KillFailed = $true }
        $Gone = $false
        if (-not $KillFailed) { $Gone = $Process.WaitForExit(10000) }
        return @{ TimedOut = $true; ExitCode = $null; Unkillable = (-not $Gone); ProcessId = $ProcessId }
    }
    return @{ TimedOut = $false; ExitCode = $Process.ExitCode; Unkillable = $false; ProcessId = $ProcessId }
}

# True when any existing log holds a fatal marker, even if the process exited 0.
function Test-FatalLog([string[]]$Paths) {
    foreach ($Path in $Paths) {
        if (-not (Test-Path -LiteralPath $Path)) { continue }
        $Text = Get-Content -LiteralPath $Path -Raw
        if ($Text -and $Text -match '(?m)^\s*(SCRIPT ERROR|SHADER ERROR|Parse Error|ERROR:)') { return $true }
    }
    return $false
}

# Reuse the engine from the existing Windows installation.
$EnginePath = Join-Path $InstallRoot 'f3c1b36/Engine/Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $EnginePath)) {
    $Engines = @(Get-ChildItem -LiteralPath $InstallRoot -Directory | ForEach-Object {
        Get-ChildItem -Path (Join-Path $_.FullName 'Engine/*_win64.exe') -File -ErrorAction SilentlyContinue
    })
    if ($Engines.Count -eq 0) { throw 'No installed Godot engine found in WhiplashShift.' }
    $EnginePath = $Engines[0].FullName
}
$OriginalVersion = Split-Path (Split-Path $EnginePath -Parent) -Parent
$ProjectPath = Join-Path $OriginalVersion 'Game/godot'
$Revision = ''
$ActiveBranch = 'unknown'
$Latest = ''
$SourceBranch = ''
if (Test-Path -LiteralPath $StatePath) {
    $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    if (Test-Path -LiteralPath (Join-Path $State.project_path 'project.godot')) {
        $ProjectPath = $State.project_path
        $Revision = $State.revision
        if ($State.source_branch) { $ActiveBranch = [string]$State.source_branch }
    }
}

try {
    $ReleaseRef = if ($Channel -eq 'preview') { 'desktop-preview' } else { 'main' }
    $Release = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/$Repository/$ReleaseRef/tools/launcher/windows-release.json" -TimeoutSec 15
    $Latest = [string]$Release.source_commit
    if ($Latest -notmatch '^[0-9a-f]{40}$') { throw 'Invalid release revision.' }
    $SourceBranch = if ($Release.source_branch) { [string]$Release.source_branch } else { 'main' }
    Write-LauncherLog "$Channel channel: $SourceBranch at $($Latest.Substring(0, 8))."
    if ($Latest -ne $Revision) {
        Write-LauncherLog 'Downloading the latest published game. The first update may take a few minutes.'
        $PreserveStaging = $false
        $Staging = Join-Path $InstallRoot ('.update-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $Staging | Out-Null
        try {
            $ArchivePath = Join-Path $Staging 'source.zip'
            Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/$Repository/zip/$Latest" -OutFile $ArchivePath -TimeoutSec 600
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $GameRoot = Join-Path $Staging 'Game'
            New-Item -ItemType Directory -Path $GameRoot | Out-Null
            $Archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
            try {
                foreach ($Entry in $Archive.Entries) {
                    $Slash = $Entry.FullName.IndexOf('/')
                    if ($Slash -lt 0) { continue }
                    $Relative = $Entry.FullName.Substring($Slash + 1)
                    if (-not $Relative.StartsWith('godot/') -or $Entry.FullName.EndsWith('/')) { continue }
                    $Destination = [IO.Path]::GetFullPath((Join-Path $GameRoot $Relative))
                    if (-not $Destination.StartsWith($GameRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                        throw 'Invalid archive path.'
                    }
                    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Destination, $false)
                }
            } finally { $Archive.Dispose() }
            $ImportedProject = Join-Path $GameRoot 'godot'
            if (-not (Test-Path -LiteralPath (Join-Path $ImportedProject 'project.godot'))) {
                throw 'The download does not contain the Godot project.'
            }
            # A cold first import can crash at shutdown; retry in the same staged project so the import cache is kept.
            $MaxAttempts = 3
            $Validated = $false
            $Failure = ''
            for ($Attempt = 1; $Attempt -le $MaxAttempts -and -not $Validated; $Attempt++) {
                Write-LauncherLog "Importing game assets with your installed Godot engine (attempt $Attempt of $MaxAttempts)..."
                $ImportOut = Join-Path $Staging "import-$Attempt.log"
                $ImportErr = Join-Path $Staging "import-errors-$Attempt.log"
                $Import = Invoke-GodotStep @('--headless', '--editor', '--path', ('"{0}"' -f $ImportedProject), '--import', '--quit') $ImportOut $ImportErr 180000
                if ($Import.Unkillable) {
                    $PreserveStaging = $true
                    throw "Godot (PID $($Import.ProcessId)) did not stop after the import timed out. Aborting without retry; staging kept at $Staging."
                }
                if ($Import.TimedOut) {
                    $Failure = 'Asset import timed out.'
                } elseif ($Import.ExitCode -ne 0) {
                    $Failure = "Asset import failed (exit $($Import.ExitCode))."
                } elseif (Test-FatalLog @($ImportOut, $ImportErr)) {
                    $Failure = 'Asset import reported fatal errors.'
                } else {
                    Write-LauncherLog 'Import finished. Checking that the imported game starts...'
                    $SmokeOut = Join-Path $Staging "smoke-$Attempt.log"
                    $SmokeErr = Join-Path $Staging "smoke-errors-$Attempt.log"
                    $Smoke = Invoke-GodotStep @('--headless', '--path', ('"{0}"' -f $ImportedProject), '--quit-after', '120') $SmokeOut $SmokeErr 60000
                    if ($Smoke.Unkillable) {
                        $PreserveStaging = $true
                        throw "Godot (PID $($Smoke.ProcessId)) did not stop after the startup check timed out. Aborting without retry; staging kept at $Staging."
                    }
                    if ($Smoke.TimedOut) {
                        $Failure = 'Startup check timed out.'
                    } elseif ($Smoke.ExitCode -ne 0) {
                        $Failure = "Startup check failed (exit $($Smoke.ExitCode))."
                    } elseif (Test-FatalLog @($SmokeOut, $SmokeErr)) {
                        $Failure = 'Startup check reported fatal errors.'
                    } else {
                        $Validated = $true
                        continue
                    }
                }
                Write-LauncherLog "$Failure Attempt $Attempt of $MaxAttempts."
            }
            if (-not $Validated) { throw "$Failure Gave up after $MaxAttempts attempts." }
            # Activate only a complete, imported and validated version. Existing versions stay intact.
            $VersionPath = Join-Path $InstallRoot ('Versions/' + $Latest + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path (Split-Path $VersionPath -Parent) -Force | Out-Null
            Assert-InsideRoot $GameRoot $InstallRoot
            Assert-InsideRoot $VersionPath $InstallRoot
            Move-Item -LiteralPath $GameRoot -Destination $VersionPath
            $NewProject = Join-Path $VersionPath 'godot'
            $NewState = @{ revision = $Latest; project_path = $NewProject; channel = $Channel; source_branch = $SourceBranch }
            $NewState | ConvertTo-Json | Set-Content -LiteralPath ($StatePath + '.tmp') -Encoding UTF8
            Move-Item -LiteralPath ($StatePath + '.tmp') -Destination $StatePath -Force
            $ProjectPath = $NewProject
            $Revision = $Latest
            $ActiveBranch = $SourceBranch
            Write-LauncherLog "Updated to $SourceBranch at $($Latest.Substring(0, 8))."
        } finally {
            # A process that survived Kill may still hold files here; leave them for manual cleanup.
            if (-not $PreserveStaging -and (Test-Path -LiteralPath $Staging)) {
                Assert-InsideRoot $Staging $InstallRoot
                Remove-Item -LiteralPath $Staging -Recurse -Force
            }
        }
    }
} catch {
    $ActiveText = if ($Revision) { "$ActiveBranch at $($Revision.Substring(0, [Math]::Min(8, $Revision.Length)))" } else { 'the original installation' }
    $DesiredText = if ($Latest) { "$SourceBranch at $($Latest.Substring(0, [Math]::Min(8, $Latest.Length)))" } else { 'unknown' }
    Write-LauncherLog "Update unavailable: $($_.Exception.Message) Desired: $DesiredText. Active: $ActiveText. Launching the fallback, not the latest."
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'project.godot'))) {
    throw "No working game found. See $LogPath"
}

if ($Install) {
    $LauncherPath = Join-Path $InstallRoot 'Launch-WhiplashShift.ps1'
    if ([IO.Path]::GetFullPath($PSCommandPath) -ne [IO.Path]::GetFullPath($LauncherPath)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $LauncherPath -Force
    }
    $Shell = New-Object -ComObject WScript.Shell
    $Desktop = [Environment]::GetFolderPath('DesktopDirectory')
    $StartMenu = [Environment]::GetFolderPath('StartMenu')
    $Shortcuts = @{}
    foreach ($Folder in @($Desktop, $StartMenu)) {
        if (-not $Folder -or -not (Test-Path -LiteralPath $Folder)) { continue }
        foreach ($File in Get-ChildItem -LiteralPath $Folder -Filter '*.lnk' -Recurse -File) {
            $Link = $Shell.CreateShortcut($File.FullName)
            if ($Link.TargetPath.StartsWith($InstallRoot, [StringComparison]::OrdinalIgnoreCase) -or
                $Link.Arguments.Contains('Launch-WhiplashShift.ps1')) {
                $Shortcuts[$File.FullName] = $true
            }
        }
    }
    $Shortcuts[(Join-Path $Desktop 'Whiplash Shift.lnk')] = $true
    foreach ($ShortcutPath in $Shortcuts.Keys) {
        $Link = $Shell.CreateShortcut($ShortcutPath)
        $Link.TargetPath = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $Link.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Channel {1}' -f $LauncherPath, $Channel
        $Link.WorkingDirectory = $InstallRoot
        $Link.IconLocation = $EnginePath + ',0'
        $Link.Save()
    }
    Write-LauncherLog 'Shortcut installed. Use Whiplash Shift on your desktop for future updates.'
}

if (-not $NoLaunch) {
    $LaunchRevision = if ($Revision) { $Revision.Substring(0, [Math]::Min(8, $Revision.Length)) } else { 'original' }
    Write-LauncherLog "Launching $ActiveBranch at $LaunchRevision."
    $LaunchArgs = @('--path', ('"{0}"' -f $ProjectPath))
    if ($Editor) { $LaunchArgs += '--editor' }
    Start-Process -FilePath $EnginePath -ArgumentList $LaunchArgs
}
