"""Builds a model folder the app can load, from a converted package and a tokenizer file.

Run it as: python -I make_manifest.py <name> <factcg|minicheck> <sequence length> <package> <tokenizer.json> <folder>

The folder gets model.mlpackage (moved), tokenizer.json (copied) and manifest.json. The manifest holds the digest of
the package: the SHA-256 of one line per file, "relative path<TAB>file SHA-256", sorted. The app computes the same
digest before it loads the model (FolderDigest in WorkbenchCore).
"""

import hashlib
import json
import shutil
import sys
from pathlib import Path


def file_digest(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 22), b""):
            digest.update(chunk)
    return digest.hexdigest()


def folder_digest(folder):
    lines = sorted(
        f"{path.relative_to(folder).as_posix()}\t{file_digest(path)}\n"
        for path in folder.rglob("*")
        if path.is_file()
    )
    return hashlib.sha256("".join(lines).encode()).hexdigest()


def main(name, recipe, sequence_length, package, tokenizer, folder):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / "model.mlpackage"
    shutil.move(package, target)
    shutil.copy(tokenizer, folder / "tokenizer.json")
    manifest = {
        "name": name,
        "recipe": recipe,
        "packageDigest": folder_digest(target),
        "sequenceLength": int(sequence_length),
    }
    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True))
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main(*sys.argv[1:])
