#!/usr/bin/env python3
"""Download verified official Homebrew bottles and matching upstream sources."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
import urllib.parse
import urllib.request
from runtime_bottles import load_bottles, retrieve_bottle

project = Path(__file__).resolve().parent.parent
if platform.system() != "Darwin" or platform.machine() not in ("arm64", "x86_64"):
    raise SystemExit("Runtime preparation requires an Apple Silicon or Intel Mac.")
tag = "arm64_sonoma" if platform.machine() == "arm64" else "sonoma"
runtime = project / ".runtime" / tag
bottles = load_bottles(project / "scripts/runtime-bottles.json", tag)
runtime.mkdir(parents=True, exist_ok=True)
for name, bottle in bottles.items():
    archive_path = retrieve_bottle(name, bottle, project / ".runtime/_bottles")
    # Bottles contain read-only files. Replace this generated package directory
    # instead of extracting over an earlier preparation or a partial extraction.
    if (runtime / name).exists():
        shutil.rmtree(runtime / name)
    # L'empreinte et la taille épinglées sont vérifiées avant toute extraction.
    with tarfile.open(archive_path) as archive:
        members = archive.getmembers()
        for member in members:
            target = (runtime / member.name).resolve()
            if runtime not in target.parents:
                raise RuntimeError("Unsafe archive member")
            if member.issym():
                linked = (target.parent / member.linkname).resolve()
                if runtime not in linked.parents:
                    raise RuntimeError("Unsafe archive symbolic link")
            if member.islnk():
                linked = (runtime / member.linkname).resolve()
                if runtime not in linked.parents:
                    raise RuntimeError("Unsafe archive hard link")
        archive.extractall(runtime)

source_directory = runtime / "_sources"
source_directory.mkdir(exist_ok=True)
sources = []
for formula in sorted(runtime.glob("*/*/.brew/*.rb")):
    text = formula.read_text()
    url = re.search(r'^  url "([^"]+)"', text, re.MULTILINE)
    digest = re.search(r'^  sha256 "([0-9a-f]{64})"', text, re.MULTILINE)
    if not url or not digest or not url.group(1).startswith("https://"):
        raise RuntimeError("Cannot identify corresponding source for " + formula.name)
    sources.append({"package": formula.stem, "url": url.group(1), "sha256": digest.group(1)})

def retrieve_source(source):
    name = Path(urllib.parse.urlparse(source["url"]).path).name
    destination = source_directory / name
    if destination.is_file() and hashlib.sha256(destination.read_bytes()).hexdigest() == source["sha256"]:
        return
    temporary = destination.with_suffix(destination.suffix + ".partial")
    try:
        request = urllib.request.Request(source["url"], headers={"User-Agent": "iTelier-build"})
        with urllib.request.urlopen(request, timeout=60) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != source["sha256"]:
            raise RuntimeError("Source checksum mismatch: " + name)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
    print("Source verified: " + name, flush=True)

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
    list(executor.map(retrieve_source, sources))
(source_directory / "sources.json").write_text(json.dumps(sources, indent=2) + "\n")
subprocess.run(["python3", str(project / "scripts/build-restore-engine.py"), str(runtime)], check=True)
print("USB and restoration runtime ready at " + str(runtime))
