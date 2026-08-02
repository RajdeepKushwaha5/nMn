# NmN — No More No

A temporary auto-approval switch for trusted local coding sessions.

NmN confirms Claude Code permission prompts in VS Code so a long agent run
doesn't stall waiting on you. It is **off by default**, arms for **15 minutes at
a time**, and only acts while VS Code is the window you're actually looking at.

It is not a screen scraper. It never reads pixels, never uses screen
coordinates, and never moves your mouse.

---

## Read this first

For Claude Code specifically, **NmN is the second-best answer.** Claude Code has
a native permission system that decides from the *actual tool call* — the real
command, the real file path — instead of from a button caption:

| Want | Native equivalent |
| --- | --- |
| Stop prompting for edits | `"defaultMode": "acceptEdits"` |
| Stop prompting, with safety checks | `"defaultMode": "auto"` |
| Never prompt for `npm`/`git` | `"permissions": { "allow": ["Bash(npm *)"] }` |
| *Always* prompt for pushes | `"permissions": { "deny": ["Bash(git push *)"] }` |

Configure it in `.claude/settings.json` or with `/permissions`. A rule engine can
tell `npm test` from `rm -rf`. **NmN cannot** — it sees a button named `Yes`.

NmN earns its place where rules can't reach: other AI extensions, prompts that
aren't tool calls, and sessions where you want a blunt time-boxed "just go".

---

## Quick start

1. **[Download the ZIP](https://github.com/RajdeepKushwaha5/nMn/archive/refs/heads/main.zip)** and unzip it anywhere.
2. Double-click **`Install.bat`**.
3. Launch **NmN** from your Desktop.
4. A **grey dot** appears in your tray. Double-click it to arm — it turns green.

That's it. No runtime to install, no dependencies, no admin rights.

The installer only creates shortcuts pointing at the folder you unzipped, so
moving or deleting that folder uninstalls NmN completely.

## Requirements

Windows, VS Code, and Windows PowerShell 5.1 — which ships with every Windows
install, so there is nothing to download.

> **PowerShell 7 (`pwsh`) does not work.** It lacks the .NET Framework UI
> Automation assemblies. NmN detects this and tells you, rather than failing
> with a confusing error. The `.bat` launchers always pick the right one.

## Run manually

Double-click `NmN.bat`, or:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File NmN.ps1
```

A grey dot appears in your tray. NmN is **off**.

## Use

1. **Double-click the tray icon** (or press `Ctrl+Alt+Y`) to arm it. Dot turns green.
2. Work normally. Confirmation prompts get answered `Yes` for 15 minutes.
3. Press `Ctrl+Alt+Y` again to stop instantly. It also disarms on its own when
   the timer runs out.

Right-click the tray icon for status, the activity log, and exit.

### Options

```text
NmN.ps1 [-ArmOnStart] [-ArmMinutes <n>]
```

- `-ArmMinutes <n>` — length of one arming window. Default 15.
- `-ArmOnStart` — start armed instead of off. Handy for testing, but it skips
  the deliberate act the safety model rests on, so don't put it in a shortcut
  you launch every day.

Verified end to end: armed → 5 prompts auto-confirmed → disarmed on schedule at
exactly the 3:00 mark, with no handle growth.

> `Ctrl+Alt+N` is deliberately **not** the hotkey — the Code Runner extension
> already binds it to "Run Code".

## What it will and won't click

**Will:** a button named exactly `Yes` (or `1 Yes` — Claude Code prefixes the
keyboard shortcut), inside the Claude Code panel, enabled and on screen.

**Won't:**

- `Yes, and don't ask again` — NmN only ever grants **one-shot** approval, so
  nothing it does outlives the session. This is the single most important rule
  in the tool.
- Anything while VS Code is in the background.
- Anything outside the Claude Code accessibility subtree. (Without this scope,
  a naive `Yes`/`No` match hits the status bar's **"No Problems"**.)
- Anything scrolled out of view.

Every confirmation is timestamped in `nmn.log` next to the script.

## Known behavior

- **First-query priming.** Chromium builds its accessibility tree lazily — the
  first UIA query only wakes it up and returns a near-empty tree. NmN primes it
  once at startup. Without this, the first prompt of a session is missed.
- **Polling, not events.** NmN checks every 600ms, so confirmation is
  near-instant but not literally instant.
- **Button names are the contract.** Matching is on accessible *name* only,
  never on CSS class — VS Code's classes are webpack-hashed (`button_qlaBag`)
  and change on every release. If a future release renames the button, NmN
  stops clicking. It fails closed: you get a normal prompt.

## Safety

NmN clicks a button labelled `Yes`. It has no idea what it is agreeing to.

That is acceptable because arming is deliberate, visible, and expires.

The installer can start NmN with Windows, and that is safe for one reason only:
**NmN always starts disarmed.** It never arms itself, there is no way to arm it
indefinitely, and every arming window ends on its own. The thing that must stay
deliberate is the arming — not the launching.

Don't arm it while working in a repository you don't trust.

## Roadmap

- Port to C# / .NET 8 as a single-file `.exe` (needs the .NET SDK, not currently installed)
- Detect Claude Code's native permission mode and suggest it instead of arming
- Support other AI extensions by adding their panel names
