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
4. In Workbench: finish the four setup screens, then turn on **Screen** in Settings › Capture. macOS asks for
   Accessibility permission; allow it.

The local signing identity keeps macOS permissions across updates. Without it, macOS asks again after every update.

## Update
```sh
cd ~/Projects/workbench && git pull && scripts/install.sh
```

## Use
- **Mochi** (top of the sidebar): your day, and the timeline of what you worked on. Press *Read this day*, then mark
  each block right or wrong.
- **Pip**: your team's WhatsApp group. Choose the group, read a day, mark the entries. Optional night nudge.
- **Echo**: calls you record from the menu bar.
- **Runs**: every model call, its cost, and how often each helper was right, on all days and on held-out days.

## Code map
- `Packages/WorkbenchCore`: the store (SQLite, schema as append-only steps), consent grants, model runs, the helper
  engine (`Helpers/`: a helper is data — a source, a brief, typed fields, a view), items and marks, the held-out split.
- `Packages/BaseKit`: the claude/codex runner (no tools, no session), local readers (screen, WhatsApp, files, call
  audio), the capture service.
- `Packages/WorkbenchUI`: the app: sidebar, helper pages, settings, menu bar.
- `Packages/GoogleConnector`: Google sign-in, calendar and mail clients (not used yet).

Test: `swift test` in each package. Lint: `xcrun swift-format lint -r --configuration .swift-format Packages`.
