# Workbench

A local-first Mac workbench. Helpers read sources you allow (screen windows, one WhatsApp group, calls you record),
propose items with the exact words they came from, and learn from your right/wrong marks. Every model call is logged
with its cost. Your data stays on your Mac; only a day you ask a helper to read goes to the model you chose.
Based on Sentient OS (AGPL-3.0); see LICENSE.

## Set up a new Mac (once)
1. macOS 15 or later. Install **Xcode** from the App Store and open it once.
2. Install **Claude Code** (`claude`) or **Codex** (`codex`) and sign in. Workbench reads through one of them, on your
   own plan.
3. Get the code and run the setup:
   ```sh
   git clone https://github.com/123Satyajeet123/workbench.git ~/Projects/workbench
   cd ~/Projects/workbench
   scripts/setup.sh      # checks the tools, makes a local signing identity; macOS asks for your password once
   scripts/install.sh    # builds, installs ~/Applications/Workbench.app, opens it
   ```
4. In Workbench: finish the setup screens (your name, your team), then turn on **Screen** and **Screen text** in
   Settings › Capture. macOS asks for Accessibility permission; allow it.
5. System Settings › Privacy & Security › **Full Disk Access** › **+** › `~/Applications/Workbench.app`, on.
   Without it, macOS asks "Workbench would like to access data from other apps" whenever a machine reads WhatsApp.
6. Browser pages (mail, LinkedIn, X), for Scout and the VC machines: run `scripts/install-browser.sh`, then in
   `brave://extensions` (or `chrome://extensions`) turn on Developer mode, *Load unpacked*, choose `Extension/`.
   Reload open tabs once.
7. WhatsApp machines need **WhatsApp Desktop** installed and signed in on this Mac.
8. The first time you turn on a nudge or hourly reading, allow notifications when macOS asks.

The local signing identity keeps macOS permissions across updates. Without it, macOS asks again after every update.

## Update
```sh
cd ~/Projects/workbench && git pull && scripts/install.sh
```

## Use
- **Mochi** (top of the sidebar): your day and its timeline. After 3 work days it proposes machines for jobs that
  repeat; build, skip or never each one.
- **Review**: every machine's unmarked items in one queue. Keys: Y right, N wrong, J/K move, U undo.
- **Crew**: your machines. **+** makes one from a template: Pip (a WhatsApp group), Timeline (your screen), Scout
  (pages you saw on sites you name), and a VC pack: Deal intake (rated hot, warm or cold by your criteria), Founder
  check, Company signals. Right-click to rename, edit the brief (try it on past days first), pause, share
  or delete. Each machine page has a view switch, a share-this-day button and, on each item, *Draft a message* and
  *Add to Reminders*.
- **Team**: your team's shared days and machines. A day goes only to teammates who can already read its source.
- **Echo**: calls you record from the menu bar. **Runs**: every model call, its cost, and how often each machine
  was right.
- ⌘+ / ⌘− zoom.

### Browser pages (for Scout)
Brave and Chrome do not show page text to Accessibility, so a small extension sends the text you see.
1. `scripts/install-browser.sh` installs the local host and registers it for Brave and Chrome.
2. In `brave://extensions` (or `chrome://extensions`): turn on Developer mode, *Load unpacked*, choose `Extension/`.
3. Turn on **Screen text** in Settings › Capture. Text is kept only for sites that are not private or blocked, never
   in private windows, and never what you type.

## Code map
- `Packages/WorkbenchCore`: the store (SQLite, schema as append-only steps), consent grants, model runs, the helper
  engine (`Helpers/`: a helper is data — a source, a brief, typed fields, a view), items and marks, the held-out split.
- `Packages/BaseKit`: the claude/codex runner (no tools, no session), local readers (screen, WhatsApp, call
  audio), the capture service.
- `Packages/WorkbenchUI`: the app: sidebar, helper pages, settings, menu bar.
- `Testing/`: code that is not shipped: the offline eval tools (`claim-eval`, `outbound-eval`, `transcribe-bakeoff`) and
  what they use. No shipped target depends on it.
- `Extension/`: the browser extension (visible page text, Gmail threads and allowed WhatsApp Web chats to the `workbench-pages` host in WorkbenchCore, which passes them to the running app over a local socket; only the app writes the store).

Test: `swift test` in each package. Tests guard product promises, not code details: a test stays only if it guards a
promise (consent, privacy, quotes, marks and trust, deletion, upgrades, the main flows) or a bug that happened.
`scripts/promises.sh` plants one bug behind each promise and shows which tests catch it; run it before deleting tests.
Lint: `xcrun swift-format lint -r --configuration .swift-format Packages Testing`.
