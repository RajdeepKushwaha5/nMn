<#
    NmN (No More No) v0.1
    A temporary auto-approval switch for trusted local coding sessions.

    Confirms Claude Code permission prompts in VS Code via Windows UI Automation.
    It never reads pixels, never uses screen coordinates, and never moves your
    mouse -- it invokes the accessible button directly.

    Safety model (all four must hold before anything is clicked):
      1. NmN is armed, and the arm-timer has not expired
      2. VS Code is the foreground application
      3. The button lives inside the "Claude Code" accessibility subtree
      4. The button is named exactly "Yes" (optionally shortcut-prefixed) and
         is enabled, on-screen, and exposes InvokePattern

    Deliberately NOT auto-confirmed: "Yes, and don't ask again". NmN only ever
    grants one-shot approval, so nothing it does outlives the session.

    Run:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File NmN.ps1
    (Windows PowerShell 5.1 -- it has the .NET Framework UIA assemblies.)
#>

param(
    # Arm immediately instead of starting disarmed. Use sparingly -- starting
    # armed skips the deliberate act that the safety model depends on.
    [switch]$ArmOnStart,

    # Length of one arming window, in minutes.
    [int]$ArmMinutes = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
    PowerShell 7 (pwsh) ships without the .NET Framework UI Automation
    assemblies, so Add-Type below would fail with an error that gives no hint
    about the real cause. Fail loudly and say exactly what to do instead.
#>
if ($PSVersionTable.PSEdition -eq 'Core') {
    $msg = @"
NmN must run on Windows PowerShell 5.1, not PowerShell $($PSVersionTable.PSVersion).

PowerShell 7 (pwsh) does not ship the UI Automation assemblies NmN needs.

Run it with the bundled launcher instead:

    NmN.bat

or explicitly:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File NmN.ps1
"@
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show($msg, 'NmN - wrong PowerShell') | Out-Null
    } catch { }
    Write-Error $msg
    exit 1
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------- config ----
$script:ArmMinutes   = $ArmMinutes
$script:PollMs       = 600      # how often to look for a prompt
$script:LogPath      = Join-Path $PSScriptRoot 'nmn.log'
$script:PanelName    = 'Claude Code'

# Ctrl+Alt+N is taken by Code Runner ("Run Code"), so NmN uses Ctrl+Alt+Y.
$script:HotkeyVk     = 0x59     # 'Y'
$script:HotkeyLabel  = 'Ctrl+Alt+Y'

# ----------------------------------------------------------------- state ----
$script:Armed        = $false
$script:ArmedUntil   = [datetime]::MinValue
$script:ClickCount   = 0
$script:LastClickAt  = [datetime]::MinValue
$script:HotkeyDown   = $false

# --------------------------------------------------------------- win32 ------
Add-Type -Namespace NmN -Name Native -MemberDefinition @'
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
'@

function Write-NmNLog {
    param([string]$Message)
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $script:LogPath -Value $line -Encoding UTF8 } catch { }
}

# Returns the foreground window handle if it belongs to VS Code, else zero.
function Get-ForegroundVsCodeWindow {
    $hwnd = [NmN.Native]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { return [IntPtr]::Zero }

    # Not $pid -- that is a read-only PowerShell automatic variable.
    $procId = 0
    [void][NmN.Native]::GetWindowThreadProcessId($hwnd, [ref]$procId)
    if ($procId -eq 0) { return [IntPtr]::Zero }

    try {
        $proc = Get-Process -Id $procId -ErrorAction Stop
        if ($proc.ProcessName -eq 'Code') { return $hwnd }
    } catch { }

    return [IntPtr]::Zero
}

<#
    Chromium builds its accessibility tree lazily: the first UIA query only
    wakes it up and returns a near-empty tree. Everything real appears on the
    next query. NmN primes once at startup so the first prompt is not missed.
#>
function Initialize-AccessibilityTree {
    try {
        $p = Get-Process -Name Code -ErrorAction SilentlyContinue |
             Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if (-not $p) { return $false }

        $root = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
        $cond = New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::Button)
        $null = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        return $true
    } catch {
        return $false
    }
}

# Finds the "Claude Code" document subtree. Scoping to it is what keeps NmN
# from ever matching unrelated UI such as the status bar's "No Problems".
function Get-ClaudePanel {
    param([System.Windows.Automation.AutomationElement]$Root)

    $cond = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Document)),
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty,
            $script:PanelName))
    )

    try {
        return $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    } catch {
        return $null
    }
}

<#
    The confirm button is named "1 Yes" -- the leading digit is its keyboard
    shortcut, so a bare "Yes" comparison matches nothing. The trailing anchor
    is what excludes "Yes, and don't ask again", which NmN must never click.
#>
function Test-IsConfirmButton {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return $Name -match "^\s*(\d+[\.\)]?\s+)?Yes\s*$"
}

function Find-ConfirmButton {
    param([System.Windows.Automation.AutomationElement]$Panel)

    $cond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::Button)

    try {
        $buttons = $Panel.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    } catch {
        return $null
    }

    foreach ($b in $buttons) {
        try {
            $c = $b.Current
            if (-not (Test-IsConfirmButton $c.Name)) { continue }
            if (-not $c.IsEnabled) { continue }
            if ($c.IsOffscreen)    { continue }

            # Scrolled-out buttons still report real-looking rects with a
            # negative origin; treat those as not present.
            $r = $c.BoundingRectangle
            if ($r.Width -le 0 -or $r.Height -le 0) { continue }
            if ($r.Y -lt 0) { continue }

            $null = $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            return $b
        } catch {
            continue
        }
    }
    return $null
}

function Invoke-ConfirmButton {
    param([System.Windows.Automation.AutomationElement]$Button)
    try {
        $pattern = $Button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $pattern.Invoke()
        return $true
    } catch {
        return $false
    }
}

# ------------------------------------------------------------ tray icon -----
function New-StateIcon {
    param([bool]$On)

    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    if ($On) { $fill = [System.Drawing.Color]::FromArgb(46, 204, 113) }
    else     { $fill = [System.Drawing.Color]::FromArgb(120, 120, 120) }

    $brush = New-Object System.Drawing.SolidBrush $fill
    $g.FillEllipse($brush, 1, 1, 14, 14)
    $brush.Dispose()
    $g.Dispose()

    $hicon = $bmp.GetHicon()
    $icon  = [System.Drawing.Icon]::FromHandle($hicon)
    $bmp.Dispose()
    return $icon
}

# Built once and reused. Update-Ui runs on every poll tick, so creating icons
# there would leak a GDI handle roughly twice a second.
$script:IconOn  = New-StateIcon $true
$script:IconOff = New-StateIcon $false

$script:Tray = New-Object System.Windows.Forms.NotifyIcon
$script:Tray.Icon    = $script:IconOff
$script:Tray.Visible = $true

$menu        = New-Object System.Windows.Forms.ContextMenuStrip
$miToggle    = $menu.Items.Add("Arm for $script:ArmMinutes minutes")
$miStatus    = $menu.Items.Add('Status: OFF')
$null        = $menu.Items.Add('-')
$miLog       = $menu.Items.Add('Open activity log')
$miExit      = $menu.Items.Add('Exit')
$miStatus.Enabled = $false
$script:Tray.ContextMenuStrip = $menu

function Update-Ui {
    if ($script:Armed) {
        $left = [int][math]::Ceiling(($script:ArmedUntil - (Get-Date)).TotalMinutes)
        $script:Tray.Icon = $script:IconOn
        $script:Tray.Text = "NmN: ON ({0} min left, {1} confirmed)" -f $left, $script:ClickCount
        $miToggle.Text    = 'Disarm now'
        $miStatus.Text    = "Status: ON - $left min left"
    } else {
        $script:Tray.Icon = $script:IconOff
        $script:Tray.Text = 'NmN: OFF'
        $miToggle.Text    = "Arm for $script:ArmMinutes minutes"
        $miStatus.Text    = 'Status: OFF'
    }
}

function Set-Armed {
    param([bool]$On, [string]$Reason)

    $script:Armed = $On
    if ($On) {
        $script:ArmedUntil = (Get-Date).AddMinutes($script:ArmMinutes)
        $script:ClickCount = 0
        Write-NmNLog "ARMED for $script:ArmMinutes min ($Reason)"
        $script:Tray.ShowBalloonTip(2000, 'NmN armed',
            "Auto-confirming for $script:ArmMinutes minutes. $script:HotkeyLabel to stop.",
            [System.Windows.Forms.ToolTipIcon]::Info)
    } else {
        Write-NmNLog "DISARMED ($Reason) after $script:ClickCount confirmation(s)"
    }
    Update-Ui
}

$miToggle.Add_Click({
    if ($script:Armed) { Set-Armed $false 'tray menu' }
    else               { Set-Armed $true  'tray menu' }
})

$miLog.Add_Click({
    if (Test-Path $script:LogPath) { Start-Process notepad.exe $script:LogPath }
    else { [System.Windows.Forms.MessageBox]::Show('No activity logged yet.', 'NmN') | Out-Null }
})

$script:Tray.Add_DoubleClick({
    if ($script:Armed) { Set-Armed $false 'tray double-click' }
    else               { Set-Armed $true  'tray double-click' }
})

# ---------------------------------------------------------------- loop ------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $script:PollMs

$timer.Add_Tick({
    # Global kill switch, edge-triggered so holding the keys toggles once.
    $ctrl = ([NmN.Native]::GetAsyncKeyState(0x11) -band 0x8000) -ne 0
    $alt  = ([NmN.Native]::GetAsyncKeyState(0x12) -band 0x8000) -ne 0
    $key  = ([NmN.Native]::GetAsyncKeyState($script:HotkeyVk) -band 0x8000) -ne 0

    if ($ctrl -and $alt -and $key) {
        if (-not $script:HotkeyDown) {
            $script:HotkeyDown = $true
            if ($script:Armed) { Set-Armed $false 'hotkey' } else { Set-Armed $true 'hotkey' }
        }
    } else {
        $script:HotkeyDown = $false
    }

    if (-not $script:Armed) { return }

    # Gate 1: the arming window has to still be open.
    if ((Get-Date) -ge $script:ArmedUntil) {
        Set-Armed $false 'timer expired'
        return
    }

    # Gate 2: VS Code has to be what you are actually looking at.
    $hwnd = Get-ForegroundVsCodeWindow
    if ($hwnd -eq [IntPtr]::Zero) { Update-Ui; return }

    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
        if (-not $root) { return }

        # Gate 3: only ever look inside the Claude Code subtree.
        $panel = Get-ClaudePanel -Root $root
        if (-not $panel) { Update-Ui; return }

        # Gate 4: an enabled, on-screen, invokable button named exactly "Yes".
        $btn = Find-ConfirmButton -Panel $panel
        if (-not $btn) { Update-Ui; return }

        # Debounce so one prompt cannot be invoked twice while the UI settles.
        if (((Get-Date) - $script:LastClickAt).TotalMilliseconds -lt 1500) { return }

        $name = $btn.Current.Name
        if (Invoke-ConfirmButton -Button $btn) {
            $script:LastClickAt = Get-Date
            $script:ClickCount++
            Write-NmNLog "CONFIRMED button [$name]"
        } else {
            Write-NmNLog "FAILED to invoke button [$name]"
        }
    } catch {
        # A tree that changes mid-walk throws; next tick re-reads it.
    }

    Update-Ui
})

# --------------------------------------------------------------- startup ----
Write-NmNLog '--- NmN started ---'
if (-not (Initialize-AccessibilityTree)) {
    Write-NmNLog 'WARN: no VS Code window found at startup; tree not primed'
}

Update-Ui
if ($ArmOnStart) {
    Set-Armed $true 'command line (-ArmOnStart)'
} else {
    $script:Tray.ShowBalloonTip(2500, 'NmN running',
        "OFF. Double-click the tray icon or press $script:HotkeyLabel to arm.",
        [System.Windows.Forms.ToolTipIcon]::Info)
}

$timer.Start()

$ctx = New-Object System.Windows.Forms.ApplicationContext
$miExit.Add_Click({
    $timer.Stop()
    Write-NmNLog '--- NmN exited ---'
    $script:Tray.Visible = $false
    $script:Tray.Dispose()
    $ctx.ExitThread()
})

[System.Windows.Forms.Application]::Run($ctx)
