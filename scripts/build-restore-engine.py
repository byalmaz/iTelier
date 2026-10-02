#!/usr/bin/env python3
"""Build pinned, unmodified idevicerestore sources with the macOS SDK and bottled libraries.

The explicit Darwin configuration below mirrors upstream configure.ac. Limera1n
support is omitted: iTelier uses only Apple's standard signed restore process.
No system installation or device operation is performed by this build.
"""
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request

COMMIT = "60192e97f87d1bbab5c493684e0a245b0966363f"
SHA256 = "17baa839a89247263ef558b55a0e42ca40234cd960627aedd2e956c779ce1ade"
URL = "https://codeload.github.com/libimobiledevice/idevicerestore/tar.gz/" + COMMIT
runtime = Path(sys.argv[1]).resolve()
if platform.system() != "Darwin" or platform.machine() not in ("arm64", "x86_64"):
    raise SystemExit("This runtime build supports macOS arm64 and x86_64 only.")
archive_path = runtime / "_sources" / ("idevicerestore-" + COMMIT + ".tar.gz")
if not archive_path.is_file() or hashlib.sha256(archive_path.read_bytes()).hexdigest() != SHA256:
    data = urllib.request.urlopen(URL, timeout=60).read()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise RuntimeError("idevicerestore source checksum mismatch")
    archive_path.write_bytes(data)

work = runtime / "_restore-build"
work.mkdir(exist_ok=True)
with tarfile.open(archive_path) as archive:
    for member in archive.getmembers():
        if work not in (work / member.name).resolve().parents or member.issym() or member.islnk():
            raise RuntimeError("Unsafe source archive member")
    archive.extractall(work)
source = work / ("idevicerestore-" + COMMIT)
config = source / "config.h"
config.write_text('''#define PACKAGE_NAME "idevicerestore"
#define PACKAGE_VERSION "1.1.0-git-60192e97"
#define VERSION PACKAGE_VERSION
#define PACKAGE_URL "https://libimobiledevice.org"
#define PACKAGE_BUGREPORT "https://github.com/libimobiledevice/idevicerestore/issues"
#define HAVE_STRSEP 1
#define HAVE_MKSTEMP 1
#define HAVE_REALPATH 1
#define HAVE_LOCALTIME_R 1
#define HAVE_IDEVICE_E_TIMEOUT 1
#define HAVE_RESTORE_E_RECEIVE_TIMEOUT 1
#define HAVE_ENUM_IDEVICE_CONNECTION_TYPE 1
#define HAVE_REVERSE_PROXY 1
#define _DARWIN_BETTER_REALPATH 1
#define __LITTLE_ENDIAN 1234
#define __BIG_ENDIAN 4321
#define __BYTE_ORDER 1234
''')
origin = runtime / "idevicerestore" / COMMIT[:8]
(origin / "bin").mkdir(parents=True, exist_ok=True)
output = origin / "bin" / "idevicerestore"
libraries = ["irecovery-1.0", "imobiledevice-1.0", "usbmuxd-2.0", "plist-2.0", "imobiledevice-glue-1.0", "tatsu", "zip"]
inputs = []
for name in libraries:
    paths = list(runtime.glob("*/*/lib/lib" + name + ".dylib"))
    if len(paths) != 1:
        raise RuntimeError("Missing or ambiguous dependency: " + name)
    inputs.append(str(paths[0]))
files = [path for path in sorted((source / "src").glob("*.c")) if path.name != "limera1n.c"]
command = ["xcrun", "clang", "-O2", "-mmacosx-version-min=14.0", "-DHAVE_CONFIG_H", "-Wno-multichar",
           "-I" + str(source), "-I" + str(source / "src"), "-Wl,-headerpad_max_install_names"]
command += ["-I" + str(path) for path in sorted(runtime.glob("*/*/include"))]
command += [str(path) for path in files] + inputs + ["-lcurl", "-lz", "-lpthread", "-o", str(output)]
subprocess.run(command, check=True)
for name in ("COPYING", "COPYING.LESSER", "AUTHORS", "README.md"):
    if (source / name).is_file():
        shutil.copy2(source / name, origin / name)
shutil.copy2(config, origin / "config.h")
metadata = {"commit": COMMIT, "url": URL, "sha256": SHA256,
            "configuration": "Darwin, macOS 14+, system curl/zlib, without limera1n; see build-restore-engine.py"}
(origin / "upstream-build.json").write_text(json.dumps(metadata, indent=2) + "\n")
sources_path = runtime / "_sources" / "sources.json"
sources = [item for item in json.loads(sources_path.read_text()) if item["package"] != "idevicerestore"]
sources.append(dict(metadata, package="idevicerestore"))
sources_path.write_text(json.dumps(sources, indent=2) + "\n")
shutil.copy2(Path(__file__), runtime / "_sources" / "build-restore-engine.py")
shutil.copy2(config, runtime / "_sources" / "idevicerestore-config.h")
print("Built official idevicerestore sources at " + COMMIT[:8])
