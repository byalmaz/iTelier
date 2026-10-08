#!/usr/bin/env python3
"""Embed USB tools and their complete non-system dylib dependency closure."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("runtime", type=Path)
parser.add_argument("bundle", type=Path, nargs="?")
parser.add_argument("--check-runtime", action="store_true")
args = parser.parse_args()
runtime = args.runtime.resolve()

# Refuser les anciens moteurs même lorsque le cache possède déjà sources.json.
required_revisions = {
    "idevicerestore": ("4b3e847e1d9a1210049a9e3f1d1caa38650c6617",
                       "f2ea8a6aefe5f4de5b5163eb128265949c2b2a211d5aaa62372b7845fd8935b0",
                       "bin/idevicerestore"),
    "libtatsu": ("e7d6ad13ef928aa609d0ccdfc586f7d6e8e049bf",
                 "c5222d97ae036e9990856bc36a0e1e7644841e3b3475e6e0b4662bc2b574fc91",
                 "lib/libtatsu.0.dylib"),
}
source_manifest = runtime / "_sources" / "sources.json"
if not source_manifest.is_file():
    raise RuntimeError("Missing corresponding sources. Run scripts/prepare-runtime.py first.")
source_entries = json.loads(source_manifest.read_text())
for package, (commit, digest, binary_name) in required_revisions.items():
    origin = runtime / package / commit[:8]
    binaries = list(runtime.glob(package + "/*/" + binary_name))
    metadata_path = origin / "upstream-build.json"
    if binaries != [origin / binary_name] or not metadata_path.is_file():
        raise RuntimeError("Outdated or ambiguous " + package + ". Run scripts/prepare-runtime.py first.")
    metadata = json.loads(metadata_path.read_text())
    url = "https://codeload.github.com/libimobiledevice/" + package + "/tar.gz/" + commit
    entries = [entry for entry in source_entries if entry.get("package") == package]
    if len(entries) != 1 or any(metadata.get(key) != value or entries[0].get(key) != value
                                for key, value in (("commit", commit), ("sha256", digest), ("url", url))):
        raise RuntimeError("Unverified " + package + " revision. Run scripts/prepare-runtime.py first.")
    archive = runtime / "_sources" / (package + "-" + commit + ".tar.gz")
    binary = binaries[0]
    if (not archive.is_file() or hashlib.sha256(archive.read_bytes()).hexdigest() != digest
            or runtime not in binary.resolve().parents
            or hashlib.sha256(binary.read_bytes()).hexdigest() != metadata.get("binary_sha256")):
        raise RuntimeError("Modified " + package + " runtime or sources. Run scripts/prepare-runtime.py first.")
if args.check_runtime:
    print("Verified restoration runtime: idevicerestore 4b3e847e, libtatsu e7d6ad13.")
    raise SystemExit(0)
if args.bundle is None:
    parser.error("bundle is required unless --check-runtime is used")
contents = args.bundle.resolve() / "Contents"
helpers = contents / "Helpers"
frameworks = contents / "Frameworks"
notices = contents / "Resources" / "ThirdParty"
for directory in (helpers, frameworks, notices):
    directory.mkdir(parents=True, exist_ok=True)

def libraries(path):
    result = subprocess.check_output(["/usr/bin/otool", "-L", str(path)], text=True)
    return [line.strip().split(" (compatibility version", 1)[0]
            for line in result.splitlines()[1:]]

def system_library(path):
    return path.startswith(("/usr/lib/", "/System/Library/"))

available = {}
for path in runtime.glob("*/*/lib/*.dylib"):
    resolved = path.resolve()
    if runtime not in resolved.parents:
        raise RuntimeError("Runtime library points outside its source directory")
    previous = available.get(path.name)
    if previous is not None and previous != resolved:
        raise RuntimeError("Ambiguous library: " + path.name)
    available[path.name] = resolved

copied = {}
origins = set()
pending = []
required = ("idevice_id", "ideviceinfo", "idevicediagnostics", "irecovery", "idevicerestore", "idevicebackup2")
for name in required:
    candidates = list(runtime.glob("*/*/bin/" + name))
    if len(candidates) != 1:
        raise RuntimeError("Missing or ambiguous USB tool: " + name)
    source = candidates[0]
    target = helpers / name
    shutil.copy2(source, target)
    target.chmod(0o755)
    pending.append((source, target, True))
    origins.add(source.parent.parent)

# Rebase direct and transitive dependencies; the destination Mac needs no Homebrew.
while pending:
    source, target, executable = pending.pop()
    for dependency in libraries(source):
        if system_library(dependency):
            continue
        name = Path(dependency).name
        if name not in available:
            raise RuntimeError("Unresolved dependency: " + dependency)
        original = available[name]
        if name not in copied:
            destination = frameworks / name
            shutil.copy2(original, destination)
            destination.chmod(0o755)
            copied[name] = destination
            origins.add(original.parent.parent)
            pending.append((original, destination, False))
        replacement = ("@loader_path/../Frameworks/" if executable else "@loader_path/") + name
        subprocess.run(["/usr/bin/install_name_tool", "-change", dependency, replacement, str(target)], check=True)
    if not executable:
        subprocess.run(["/usr/bin/install_name_tool", "-id", "@loader_path/" + target.name, str(target)], check=True)

manifest = []
for origin in sorted(origins):
    notice_dir = notices / (origin.parent.name + "-" + origin.name)
    notice_dir.mkdir(parents=True, exist_ok=True)
    for file in origin.iterdir():
        if file.is_file() and file.name.upper().startswith(("COPYING", "LICENSE", "NOTICE", "AUTHORS")):
            shutil.copy2(file, notice_dir / file.name)
    if (origin / ".brew").exists():
        shutil.copytree(origin / ".brew", notice_dir / "homebrew-formula", dirs_exist_ok=True)
    upstream = origin / "upstream-build.json"
    if upstream.exists():
        shutil.copy2(upstream, notice_dir / upstream.name)
    manifest.append({"package": origin.parent.name, "version": origin.name,
                     "origin": "Official upstream source" if upstream.exists() else "Official Homebrew bottle",
                     "changes": "Mach-O library paths relocated; ad hoc signature"})

sources = runtime / "_sources"
if not sources.is_dir():
    raise RuntimeError("Missing corresponding sources. Run scripts/prepare-runtime.py first.")
shutil.copytree(sources, notices / "sources", dirs_exist_ok=True)
(notices / "runtime.json").write_text(json.dumps(manifest, indent=2) + "\n")

for target in list(frameworks.iterdir()) + list(helpers.iterdir()):
    for dependency in libraries(target):
        if not system_library(dependency) and not dependency.startswith("@loader_path/"):
            raise RuntimeError("Nonportable library reference: " + dependency)
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(target)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
print("Bundled %d USB tools and %d libraries, with licenses and source archives." % (len(required), len(copied)))
