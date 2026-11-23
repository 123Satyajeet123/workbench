#!/bin/bash
# Puts a converted verifier where the app looks for it: Application Support/Workbench/models/grounding. The copy is an
# APFS clone, so it takes no extra space. The app checks the package against manifest.json before it loads it.
# Usage: install_model.sh <folder made by make_manifest.py>
set -euo pipefail

source_folder="$1"
target="$HOME/Library/Application Support/Workbench/models/grounding"
mkdir -p "$(dirname "$target")"
rm -rf "$target"
cp -c -R "$source_folder" "$target"
echo "installed $(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['name'])" "$target/manifest.json") in $target"
