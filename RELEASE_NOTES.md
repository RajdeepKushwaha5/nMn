# NmN v0.1.0

First release. A temporary auto-approval switch for trusted local coding
sessions — it answers Claude Code permission prompts in VS Code so a long agent
run doesn't stall waiting on you.

## Install

1. Download `Source code (zip)` below and unzip it anywhere.
2. Double-click **`Install.bat`**.
3. Launch **NmN** from your Desktop. A grey dot appears in your tray.
4. Double-click the dot (or press `Ctrl+Alt+Y`) to arm it for 15 minutes.

Windows 10/11. No runtime to install, no dependencies, no admin rights.

## How it works

NmN reads the Windows UI Automation accessibility tree. It never reads pixels,
never uses screen coordinates, and never moves your mouse — it activates the
button through `InvokePattern`.

Four gates must all hold before anything is clicked:

1. NmN is armed and the arm timer hasn't expired
2. VS Code is the foreground window
3. The button is inside the `Claude Code` accessibility subtree
4. The button is named exactly `Yes`, and is enabled, on-screen, and invokable

**`Yes, and don't ask again` is never clicked.** NmN only ever grants one-shot
approval, so nothing it does outlives the session.

## Verified

Armed → 5 prompts auto-confirmed → disarmed on schedule at exactly the 3:00
mark, with no handle growth. Every confirmation is timestamped in `nmn.log`.

## Known limits

- **Windows only.** UI Automation is a Windows API.
- **Windows PowerShell 5.1 only.** PowerShell 7 lacks the required assemblies;
  NmN detects this and tells you instead of failing cryptically.
- **Button names are the contract.** Matching is on accessible name, never CSS
  class — VS Code's classes are webpack-hashed and change every release. If a
  future Claude Code release renames the button, NmN stops clicking. It fails
  closed, so you simply get normal prompts back.
- **Unsigned.** Windows SmartScreen may warn on first run. Click *More info →
  Run anyway*, or inspect the source first — it's ~400 lines of PowerShell.

## A note on scope

For Claude Code specifically, NmN is the second-best answer. Claude Code's
native permission system decides from the *actual tool call* rather than a
button caption, so it can tell `npm test` from `rm -rf`. NmN cannot.

Set `"defaultMode": "acceptEdits"` or `"auto"` in `.claude/settings.json` first.
NmN is for what's left over — other AI extensions, and time-boxed "just go"
sessions.
