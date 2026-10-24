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
if (Test-Path -LiteralPath $StatePath) {
    $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    if (Test-Path -LiteralPath (Join-Path $State.project_path 'project.godot')) {
        $ProjectPath = $State.project_path
        $Revision = $State.revision
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
            Write-LauncherLog 'Importing game assets with your installed Godot engine...'
            $ImportProcess = Start-Process -FilePath $EnginePath -ArgumentList @('--headless', '--editor', '--path', ('"{0}"' -f $ImportedProject), '--import') -Wait -PassThru -RedirectStandardOutput (Join-Path $Staging 'import.log') -RedirectStandardError (Join-Path $Staging 'import-errors.log')
            if ($ImportProcess.ExitCode -ne 0) { throw "Asset import failed (exit $($ImportProcess.ExitCode))." }
            # Activate only a complete, imported version. Existing versions stay intact.
            $VersionPath = Join-Path $InstallRoot ('Versions/' + $Latest + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path (Split-Path $VersionPath -Parent) -Force | Out-Null
            Move-Item -LiteralPath $GameRoot -Destination $VersionPath
            $NewProject = Join-Path $VersionPath 'godot'
            $NewState = @{ revision = $Latest; project_path = $NewProject; channel = $Channel; source_branch = $SourceBranch }
            $NewState | ConvertTo-Json | Set-Content -LiteralPath ($StatePath + '.tmp') -Encoding UTF8
            Move-Item -LiteralPath ($StatePath + '.tmp') -Destination $StatePath -Force
            $ProjectPath = $NewProject
            Write-LauncherLog "Updated to $($Latest.Substring(0, 8))."
        } finally {
            if (Test-Path -LiteralPath $Staging) { Remove-Item -LiteralPath $Staging -Recurse -Force }
        }
    }
} catch {
    Write-LauncherLog "Update unavailable: $($_.Exception.Message) Using the installed version."
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
    $LaunchArgs = @('--path', ('"{0}"' -f $ProjectPath))
    if ($Editor) { $LaunchArgs += '--editor' }
    Start-Process -FilePath $EnginePath -ArgumentList $LaunchArgs
}
