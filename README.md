# Workbench

A local-first Mac workbench. Helpers read sources you allow (screen windows, browser pages, one WhatsApp group, one Gmail label, calls you record),
propose items with the exact words they came from, and learn from your right/wrong marks. Every model call is logged
with its cost. Your data stays on your Mac; only a day you ask a helper to read goes to the model you chose.
Based on Sentient OS (AGPL-3.0); see LICENSE.

## Set up a new Mac (once)
1. macOS 15 or later. Install **Xcode** from the App Store and open it once.
2. Get the code and build the app:
   ```sh
   git clone https://github.com/123Satyajeet123/workbench.git ~/Projects/workbench
   cd ~/Projects/workbench
   scripts/setup.sh      # checks the tools, makes a local signing identity; macOS asks for your password once
   scripts/install.sh    # builds, installs ~/Applications/Workbench.app, opens it
   ```
   The build puts the browser host (`workbench-pages`) and the browser extension inside the app. Nothing else is
   installed.
3. Open Workbench and follow the setup screens. They run in this order: your name, your team (a template), then
   **Connect**. Connect has one row for each thing your team reads:
   - **Reader**: Workbench reads through Claude Code (`claude`) or Codex (`codex`), signed in on your own plan. If it
     is missing, install it and sign in, then press *Check again*.
   - **Screen** and **Screen text**: turn them on. macOS asks for Accessibility permission; allow it.
   - **WhatsApp**: needs WhatsApp Desktop, signed in. Turn on Workbench in System Settings › Privacy & Security ›
     **Full Disk Access**, then choose the group.
   - **Browser**, one row for each Chromium browser on this Mac: see below.
4. The first time you turn on a nudge or hourly reading, allow notifications when macOS asks.

The local signing identity keeps macOS permissions across updates. Without it, macOS asks again after every update.

### The browser row
Chromium browsers do not show page text to Accessibility, so a small extension sends
the text you see. The Connect row for each browser shows where it stands:
- **Not installed**: no Chromium browser was found. Install one and open it once, then press *Check again*.
- **Off**: press *Turn on*. Workbench then writes the native host manifest for that browser. Pressing it off again
  removes the manifest. Workbench refreshes the manifest at every launch, so moving the app keeps it working.
- **Waiting for the extension**: load the extension once. Press *Open extensions page*: it opens the browser's
  extensions page and shows the Extension folder in Finder. Turn on Developer mode, choose *Load unpacked*, and pick that
  folder (`Workbench.app/Contents/Resources/Extension`).
- **Ready**: the extension has talked to Workbench through the host. The row turns green by itself.

Text is kept only for sites that are not private or blocked, never in private windows, and never what you type. A
browser you did not turn on is ignored. Install from the Chrome Web Store, with one browser prompt, comes when the
listing exists.

## Update
```sh
cd ~/Projects/workbench && git pull && scripts/install.sh
```

## Use
- **Mochi** (top of the sidebar): your day and its timeline. After 3 work days it proposes machines for jobs that
  repeat; build, skip or never each one.
- **Review**: every machine's unmarked items in one queue. Keys: Y right, N wrong, J/K move, U undo.
- **Crew**: your machines. **+** makes one from a template. Teams start from a template: **Fund** (deal intake rated
  hot, warm or cold by your criteria, founder check, company signals), **Startup team** (plans, blockers and projects)
  or **Blank**. Right-click a machine to rename it, edit the brief (try it on past days first), pause, share or delete.
  Each machine page has a view switch, a share-this-day button and, on each item, *Draft a message* and *Add to
  Reminders*.
- **Team**: your team's shared days and machines. A day goes only to teammates who can already read its source.
- **Echo**: calls you record from the menu bar. **Runs**: every model call, its cost, and how often each machine
  was right.
- ⌘+ / ⌘− zoom.

## Code map
- `Packages/WorkbenchCore`: the store (SQLite, schema as append-only steps), consent grants, model runs, the helper
  engine (`Helpers/`: a helper is data — a source, a brief, typed fields, a view), items and marks, the held-out split.
- `Packages/BaseKit`: the claude/codex runner (no tools, no session), local readers (screen, WhatsApp, call
  audio), the capture service.
- `Packages/WorkbenchUI`: the app: sidebar, helper pages, settings, menu bar.
- `Testing/`: code that is not shipped: the offline eval tools (`claim-eval`, `outbound-eval`, `transcribe-bakeoff`) and
  what they use. No shipped target depends on it.
- `Extension/`: the browser extension (visible page text and Gmail threads to the `workbench-pages` host in WorkbenchCore, which passes them to the running app over a local socket; only the app writes the store). The app build copies both into `Workbench.app`.

Test: `swift test` in each package. Tests guard product promises, not code details: a test stays only if it guards a
promise (consent, privacy, quotes, marks and trust, deletion, upgrades, the main flows) or a bug that happened.
`scripts/promises.sh` plants one bug behind each promise and shows which tests catch it; run it before deleting tests.
Lint: `xcrun swift-format lint -r --strict --configuration .swift-format Packages Testing Workbench`.
