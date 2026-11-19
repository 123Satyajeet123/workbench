#!/usr/bin/env python3
"""Claude Code quality hooks for this repo.

`edited` (PostToolUse): formats a Swift file the editor tools changed.
`stop` (Stop): asks git which Swift files differ from the last commit, whatever tool changed them; formats and lints
them, then builds and tests each package they belong to. On a failure it exits 2, so Claude must fix it before it
finishes. A second stop in a row is let through, so a failure it cannot fix never loops; while scripts/promises.sh
plants bugs, it waits.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = {
    "Packages/WorkbenchCore": [["swift", "test"]],
    "Packages/BaseKit": [["swift", "test"]],
    "Packages/WorkbenchUI": [["swift", "build"], ["swift", "test"]],
}
FORMAT = ["xcrun", "swift-format", "format", "--configuration", str(ROOT / ".swift-format"), "-i"]
LINT = ["xcrun", "swift-format", "lint", "--configuration", str(ROOT / ".swift-format")]


def package_of(relative):
    return next((package for package in PACKAGES if relative.startswith(package + "/")), None)


def changed_swift_files():
    status = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True).stdout
    paths = [line[3:].split(" -> ")[-1] for line in status.splitlines() if not line.startswith(" D")]
    return [path for path in paths if path.endswith(".swift") and (ROOT / path).exists()]


def edited(event):
    path = Path(event.get("tool_input", {}).get("file_path", ""))
    if path.suffix == ".swift" and path.exists():
        subprocess.run(FORMAT + [str(path)])
    return 0


def fail(what, output):
    lines = output.strip().splitlines()
    tail = [line for line in lines if "✘" in line or "error:" in line][:25] or lines[-25:]
    print(f"{what} failed. Fix it before you finish:", *tail, sep="\n", file=sys.stderr)
    return 2


def stop(event):
    if event.get("stop_hook_active") or (ROOT / ".promises-running").exists():
        return 0
    files = changed_swift_files()
    if not files:
        return 0
    subprocess.run(FORMAT + files, cwd=ROOT)
    lint = subprocess.run(LINT + files, cwd=ROOT, capture_output=True, text=True)
    if lint.returncode != 0 or lint.stderr.strip():
        return fail("swift-format lint", lint.stdout + lint.stderr)
    for package in sorted({package for path in files if (package := package_of(path))}):
        for command in PACKAGES[package]:
            result = subprocess.run(command, cwd=ROOT / package, capture_output=True, text=True)
            if result.returncode != 0:
                return fail(f"`{' '.join(command)}` in {package}", result.stdout + result.stderr)
    return 0


if __name__ == "__main__":
    sys.exit({"edited": edited, "stop": stop}[sys.argv[1]](json.load(sys.stdin)))
