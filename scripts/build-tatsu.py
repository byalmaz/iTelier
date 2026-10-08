#!/usr/bin/env python3
"""Compile libtatsu amont non modifiée, épinglée, sans installation ni appareil."""
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request

COMMIT = "e7d6ad13ef928aa609d0ccdfc586f7d6e8e049bf"
SHA256 = "c5222d97ae036e9990856bc36a0e1e7644841e3b3475e6e0b4662bc2b574fc91"
URL = "https://codeload.github.com/libimobiledevice/libtatsu/tar.gz/" + COMMIT
runtime = Path(sys.argv[1]).resolve()
if platform.system() != "Darwin" or platform.machine() not in ("arm64", "x86_64"):
    raise SystemExit("Cette compilation requiert macOS arm64 ou x86_64.")
archive_path = runtime / "_sources" / ("libtatsu-" + COMMIT + ".tar.gz")
if not archive_path.is_file() or hashlib.sha256(archive_path.read_bytes()).hexdigest() != SHA256:
    data = urllib.request.urlopen(URL, timeout=60).read()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise RuntimeError("Empreinte des sources libtatsu incorrecte")
    archive_path.write_bytes(data)

work = runtime / "_tatsu-build"
work.mkdir(exist_ok=True)
source = work / ("libtatsu-" + COMMIT)
# Supprimer uniquement le dossier généré du commit pour exclure tout fichier résiduel.
if source.is_symlink():
    raise RuntimeError("Lien symbolique inattendu dans les sources libtatsu")
if source.exists():
    shutil.rmtree(source)
with tarfile.open(archive_path) as archive:
    for member in archive.getmembers():
        if work not in (work / member.name).resolve().parents or member.issym() or member.islnk():
            raise RuntimeError("Entrée d'archive libtatsu non sûre")
    archive.extractall(work)
config = source / "config.h"
config.write_text('''#define PACKAGE_NAME "libtatsu"
#define PACKAGE_VERSION "1.0.5-git-e7d6ad13"
#define VERSION PACKAGE_VERSION
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_PTHREAD_ONCE 1
#define HAVE_PTHREAD_CANCEL 1
#define __LITTLE_ENDIAN 1234
#define __BIG_ENDIAN 4321
#define __BYTE_ORDER 1234
''')
plist_libraries = list(runtime.glob("libplist/*/lib/libplist-2.0.dylib"))
plist_headers = list(runtime.glob("libplist/*/include"))
if len(plist_libraries) != 1 or len(plist_headers) != 1:
    raise RuntimeError("Dépendance libplist manquante ou ambiguë")
origin = runtime / "libtatsu" / COMMIT[:8]
(origin / "lib").mkdir(parents=True, exist_ok=True)
output = origin / "lib" / "libtatsu.0.dylib"
# L'ABI Darwin 0:3:0 de configure.ac garde le nom et la compatibilité du bottle.
command = ["xcrun", "clang", "-O2", "-dynamiclib", "-mmacosx-version-min=14.0",
           "-DHAVE_CONFIG_H", "-fvisibility=hidden", "-fsigned-char",
           "-I" + str(source), "-I" + str(source / "include"),
           "-I" + str(plist_headers[0]), "-Wl,-headerpad_max_install_names",
           "-install_name", str(output), "-compatibility_version", "1.0.0",
           "-current_version", "1.3.0", str(source / "src" / "tss.c"),
           str(source / "src" / "tatsu.c"), str(plist_libraries[0]),
           "-lcurl", "-lpthread", "-o", str(output)]
subprocess.run(command, check=True)
alias = origin / "lib" / "libtatsu.dylib"
alias.unlink(missing_ok=True)
alias.symlink_to(output.name)
shutil.copytree(source / "include", origin / "include", dirs_exist_ok=True)
for name in ("COPYING", "AUTHORS", "README.md"):
    if (source / name).is_file():
        shutil.copy2(source / name, origin / name)
shutil.copy2(config, origin / "config.h")
metadata = {"commit": COMMIT, "url": URL, "sha256": SHA256,
            "binary_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
            "configuration": "Darwin, macOS 14+, system curl, libplist; ABI 0:3:0; see build-tatsu.py"}
(origin / "upstream-build.json").write_text(json.dumps(metadata, indent=2) + "\n")
sources_path = runtime / "_sources" / "sources.json"
sources = [item for item in json.loads(sources_path.read_text()) if item["package"] != "libtatsu"]
sources.append(dict(metadata, package="libtatsu"))
sources_path.write_text(json.dumps(sources, indent=2) + "\n")
shutil.copy2(Path(__file__), runtime / "_sources" / "build-tatsu.py")
shutil.copy2(config, runtime / "_sources" / "libtatsu-config.h")
# Remplacer le bottle seulement après une compilation réussie évite deux dylibs.
for previous in origin.parent.iterdir():
    if previous.is_dir() and previous != origin:
        shutil.rmtree(previous)
print("Sources officielles libtatsu compilées : " + COMMIT[:8])
