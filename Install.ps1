<#
    NmN installer.

    Creates Desktop and Start Menu shortcuts, clears the "downloaded from the
    internet" mark that makes Windows block the scripts, and optionally starts
    NmN with Windows.

    Nothing is copied anywhere -- shortcuts point at this folder, so moving or
    deleting the folder cleanly uninstalls the tool.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root    = $PSScriptRoot
$target  = Join-Path $root 'NmN.bat'
$iconSrc = "$env:SystemRoot\System32\shell32.dll,168"   # a plain check-mark icon

if (-not (Test-Path $target)) {
    Write-Host "ERROR: NmN.bat not found next to this installer." -ForegroundColor Red
    Write-Host "Run Install.bat from inside the folder you unzipped." -ForegroundColor Red
    return
}

Write-Host ''
Write-Host '  NmN - No More No' -ForegroundColor Cyan
Write-Host '  Setting up...'
Write-Host ''

# Files unzipped from a GitHub download carry a zone marker that makes Windows
# refuse to run them. Clearing it here avoids a confusing first-run failure.
try {
    Get-ChildItem -Path $root -Include '*.ps1', '*.bat' -Recurse |
        Unblock-File -ErrorAction SilentlyContinue
    Write-Host '  [ok] cleared Windows download block' -ForegroundColor Green
} catch {
    Write-Host '  [--] could not clear download block (usually harmless)' -ForegroundColor Yellow
}

function New-NmNShortcut {
    param([string]$Path, [string]$Label)
    try {
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($Path)
        $sc.TargetPath       = $target
        $sc.WorkingDirectory = $root
        $sc.IconLocation     = $iconSrc
        $sc.Description      = 'NmN - auto-confirm Claude Code prompts in VS Code'
        $sc.WindowStyle      = 7          # start minimized
        $sc.Save()
        Write-Host "  [ok] $Label" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  [--] could not create $Label" -ForegroundColor Yellow
        return $false
    }
}

$desktop = [Environment]::GetFolderPath('Desktop')
$null = New-NmNShortcut -Path (Join-Path $desktop 'NmN.lnk') -Label 'Desktop shortcut'

$startMenu = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs'
$null = New-NmNShortcut -Path (Join-Path $startMenu 'NmN.lnk') -Label 'Start Menu shortcut'

# Starting with Windows is safe because NmN always starts DISARMED. It only
# ever acts after a deliberate arm, and every arm expires on its own.
Write-Host ''
$startupDir  = [Environment]::GetFolderPath('Startup')
$startupLink = Join-Path $startupDir 'NmN.lnk'

if (Test-Path $startupLink) {
    Write-Host '  NmN already starts with Windows.'
    $answer = Read-Host '  Remove that? (y/N)'
    if ($answer -match '^[Yy]') {
        Remove-Item $startupLink -Force
        Write-Host '  [ok] removed from startup' -ForegroundColor Green
    }
} else {
    Write-Host '  Start NmN with Windows? It always starts OFF, so this just'
    Write-Host '  keeps the tray icon handy.'
    $answer = Read-Host '  (y/N)'
    if ($answer -match '^[Yy]') {
        $null = New-NmNShortcut -Path $startupLink -Label 'startup entry'
    }
}

Write-Host ''
Write-Host '  Done.' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Launch NmN from your Desktop or Start Menu.'
Write-Host '  A GREY dot appears in your tray - NmN is OFF.'
Write-Host '  Double-click the dot (or press Ctrl+Alt+Y) to arm it for 15 minutes.'
Write-Host ''
