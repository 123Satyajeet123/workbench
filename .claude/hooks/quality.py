#!/usr/bin/env python3
"""Claude Code quality hooks for this repo.

`edited` (PostToolUse): formats an edited Swift file in the new code, and records which package it belongs to.
`stop` (Stop): builds and tests each package this session edited. On failure it exits 2, so Claude must fix it;
a second stop in a row is let through (no endless loop) and the package stays pending for the next stop.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = {
    "Packages/WorkbenchCore": [["swift", "test"]],
    "Packages/BaseKit": [["swift", "test"]],
    "Packages/GoogleConnector": [["swift", "test"]],
    "Packages/WorkbenchUI": [["swift", "build"], ["swift", "test"]],
}


def package_of(path):
    relative = path.resolve().relative_to(ROOT).as_posix() if path.resolve().is_relative_to(ROOT) else ""
    return next((package for package in PACKAGES if relative.startswith(package + "/")), None)


def pending_file(session):
    return ROOT / ".claude" / f".edited-{session}"


def edited(event):
    path = Path(event.get("tool_input", {}).get("file_path", ""))
    package = package_of(path) if path.suffix == ".swift" else None
    if package is None:
        return 0
    subprocess.run(["xcrun", "swift-format", "format", "--configuration", str(ROOT / ".swift-format"), "-i", str(path)])
    with pending_file(event["session_id"]).open("a") as pending:
        pending.write(package + "\n")
    return 0


def stop(event):
    pending = pending_file(event["session_id"])
    if not pending.exists() or event.get("stop_hook_active"):
        return 0
    for package in sorted(set(pending.read_text().split())):
        for command in PACKAGES[package]:
            result = subprocess.run(command, cwd=ROOT / package, capture_output=True, text=True)
            if result.returncode != 0:
                tail = (result.stdout + result.stderr).strip().splitlines()[-25:]
                print(f"`{' '.join(command)}` failed in {package}. Fix it before you finish:", *tail, sep="\n",
                      file=sys.stderr)
                return 2
    pending.unlink()
    return 0


if __name__ == "__main__":
    sys.exit({"edited": edited, "stop": stop}[sys.argv[1]](json.load(sys.stdin)))
