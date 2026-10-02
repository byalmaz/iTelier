"""Paquets Sonoma officiels, épinglés et vérifiés avant extraction."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile
import urllib.request

REGISTRY = "https://ghcr.io/v2/homebrew/core"


def load_bottles(manifest, tag):
    data = json.loads(Path(manifest).read_text())
    if data["schemaVersion"] != 1 or data["source"] != REGISTRY:
        raise RuntimeError("Unsupported runtime bottle manifest")
    if tag not in ("arm64_sonoma", "sonoma"):
        raise RuntimeError("Unsupported runtime platform: " + tag)
    bottles = {}
    for name, platforms in data["packages"].items():
        if not re.fullmatch(r"[a-z0-9][a-z0-9+-]*(?:@[0-9]+)?", name):
            raise RuntimeError("Invalid runtime package name")
        bottle = platforms[tag]
        if not re.fullmatch(r"[0-9a-f]{64}", bottle["sha256"]):
            raise RuntimeError("Invalid runtime bottle checksum: " + name)
        if type(bottle["size"]) is not int or bottle["size"] <= 0:
            raise RuntimeError("Invalid runtime bottle size: " + name)
        if not re.search(r"\." + tag + r"(?:\.[0-9]+)?$", bottle["reference"]):
            raise RuntimeError("Mismatched runtime bottle platform: " + name)
        bottles[name] = bottle
    return bottles


def verified(archive, bottle):
    if not archive.is_file() or archive.stat().st_size != bottle["size"]:
        return False
    digest = hashlib.sha256()
    with archive.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest() == bottle["sha256"]


def retrieve_bottle(name, bottle, cache):
    cache = Path(cache)
    cache.mkdir(parents=True, exist_ok=True)
    destination = cache / (bottle["sha256"] + ".tar.gz")
    if destination.is_symlink():
        raise RuntimeError("Unsafe runtime bottle cache link")
    if verified(destination, bottle):
        return destination
    url = REGISTRY + "/" + name.replace("@", "/") + "/blobs/sha256:" + bottle["sha256"]
    # Même accès public anonyme que Homebrew ; aucun jeton personnel requis.
    request = urllib.request.Request(url, headers={
        "Authorization": "Bearer QQ==", "User-Agent": "iTelier-build"
    })
    with tempfile.NamedTemporaryFile(dir=cache, suffix=".partial", delete=False) as output:
        temporary = Path(output.name)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                shutil.copyfileobj(response, output)
            output.close()
            if not verified(temporary, bottle):
                raise RuntimeError("Bottle checksum or size mismatch: " + name)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
    print("Bottle verified: " + name + " " + bottle["reference"], flush=True)
    return destination
