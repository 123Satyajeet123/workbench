#!/bin/bash
# Makes the conversion environment: a fresh Python venv inside the models folder, outside the repo.
# Only coremltools, torch (CPU) and transformers are installed, at the pinned versions below.
set -euo pipefail

MODELS_DEV="${MODELS_DEV:-$HOME/Library/Application Support/Workbench/models-dev}"
mkdir -p "$MODELS_DEV"
cd "$MODELS_DEV"

uv venv --python 3.12 venv
uv pip install --python venv/bin/python --index-strategy unsafe-best-match \
    coremltools==9.0 torch==2.7.0 transformers==4.57.1 numpy
