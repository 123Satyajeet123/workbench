"""Writes the cuts of a verifier into its manifest, after probe P-J1 chose them.

Run it as: python -I set_band.py <model folder> <failBelow> <passFrom>
"""

import json
import sys
from pathlib import Path


def main(folder, fail_below, pass_from):
    path = Path(folder) / "manifest.json"
    manifest = json.loads(path.read_text())
    manifest["band"] = {"failBelow": float(fail_below), "passFrom": float(pass_from)}
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main(*sys.argv[1:])
