#!/usr/bin/env python3
"""Empêche la réapparition de l'ancienne marque dans les fichiers livrés."""
import argparse
from pathlib import Path
import subprocess
import sys

# Fixture historique en octets, pour ne pas réintroduire son texte dans le dépôt.
RETIRED_NAME = bytes([82, 101, 83, 99, 111, 112, 101]).lower()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.bundle:
        bundle = args.bundle.resolve()
        if not bundle.is_dir():
            parser.error("Bundle iTelier introuvable")
        paths = [bundle, *bundle.rglob("*")]
        relative_to = bundle.parent
    else:
        output = subprocess.check_output(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root
        )
        paths = [root / entry.decode("utf-8") for entry in output.split(b"\0") if entry]
        # Les réservations privées et les rendus vidéo ne sont pas distribués.
        paths = [p for p in paths if p.exists() and p.relative_to(root).parts[0] not in {".agents", "video"}]
        relative_to = root
    failures = []
    checked = 0
    for path in sorted(set(paths)):
        name = str(path.relative_to(relative_to))
        if RETIRED_NAME in name.encode("utf-8").lower():
            failures.append(name + " : nom")
        if path.is_file() and not path.is_symlink():
            checked += 1
            if RETIRED_NAME in path.read_bytes().lower():
                failures.append(name + " : contenu")
    if failures:
        print("Marque historique détectée dans les fichiers suivants :", file=sys.stderr)
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"Marque iTelier vérifiée dans {checked} fichiers.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
