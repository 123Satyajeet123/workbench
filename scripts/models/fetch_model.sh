#!/bin/bash
# Downloads one verifier from its official Hugging Face repository at the pinned revision, and checks every file against
# models.json. Only safetensors weights are fetched: a pickle file (.bin, .pt, .ckpt) is never downloaded or loaded.
# Usage: fetch_model.sh <factcg|minicheck>
set -euo pipefail

name="$1"
here="$(cd "$(dirname "$0")" && pwd)"
models_dev="${MODELS_DEV:-$HOME/Library/Application Support/Workbench/models-dev}"
target="$models_dev/downloads/$name"
mkdir -p "$target"

repository="$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]['repository'])" "$here/models.json" "$name")"
revision="$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]['revision'])" "$here/models.json" "$name")"
files="$(python3 -I -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))[sys.argv[2]]['files']))" "$here/models.json" "$name")"

for file in $files; do
    curl -sSL --fail -o "$target/$file" "https://huggingface.co/$repository/resolve/$revision/$file"
    expected="$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]['files'][sys.argv[3]]['sha256'])" "$here/models.json" "$name" "$file")"
    found="$(shasum -a 256 "$target/$file" | cut -d' ' -f1)"
    [ "$expected" = "$found" ] || { echo "checksum differs: $file" >&2; exit 1; }
done
echo "$name: every file matches models.json"
