#!/usr/bin/env python3
"""Teste le vrai moteur embarqué avec des données synthétiques, sans réseau ni USB."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tempfile
import unittest
import urllib.parse

PROJECT = Path(__file__).resolve().parent.parent
PINS = {
    "idevicerestore": ("4b3e847e1d9a1210049a9e3f1d1caa38650c6617",
                       "f2ea8a6aefe5f4de5b5163eb128265949c2b2a211d5aaa62372b7845fd8935b0"),
    "libtatsu": ("e7d6ad13ef928aa609d0ccdfc586f7d6e8e049bf",
                 "c5222d97ae036e9990856bc36a0e1e7644841e3b3475e6e0b4662bc2b574fc91"),
}
parser = argparse.ArgumentParser(description=__doc__)
target = parser.add_mutually_exclusive_group(required=True)
target.add_argument("--bundle", type=Path)
target.add_argument("--runtime", type=Path)
options = parser.parse_args()
if platform.system() != "Darwin":
    raise SystemExit("Les tests du moteur Mach-O requièrent macOS.")
if options.bundle:
    root = options.bundle.resolve() / "Contents"
    notices = root / "Resources" / "ThirdParty"
    sources = notices / "sources"
    library_directory = root / "Frameworks"
    available = {path.name: path for path in library_directory.glob("*.dylib")}
    manifest = json.loads((notices / "runtime.json").read_text())
else:
    root = options.runtime.resolve()
    sources = root / "_sources"
    available = {path.name: path.resolve() for path in root.glob("*/*/lib/*.dylib")}
    manifest = None
source_manifest = json.loads((sources / "sources.json").read_text())


def source_archive(package):
    entries = [item for item in source_manifest if item["package"] == package]
    if len(entries) != 1:
        raise RuntimeError("Source manquante ou ambiguë : " + package)
    entry = entries[0]
    name = (package + "-" + entry["commit"] + ".tar.gz" if "commit" in entry
            else Path(urllib.parse.urlparse(entry["url"]).path).name)
    archive = sources / name
    if hashlib.sha256(archive.read_bytes()).hexdigest() != entry["sha256"]:
        raise RuntimeError("Source modifiée : " + package)
    return archive


def extract_headers(package, destination):
    # Lire uniquement les en-têtes nécessaires, jamais extraire une archive entière.
    with tarfile.open(source_archive(package)) as archive:
        for member in archive.getmembers():
            relative = Path(*Path(member.name).parts[1:])
            if member.isfile() and not member.islnk() and relative.parts[:1] == ("include",):
                target = destination / Path(*relative.parts[1:])
                if destination not in target.resolve().parents:
                    raise RuntimeError("En-tête d'archive non sûr")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile(member).read())


def dependencies(path):
    output = subprocess.check_output(["/usr/bin/otool", "-L", str(path)], text=True)
    return [line.strip().split(" (compatibility version", 1)[0]
            for line in output.splitlines()[1:]]


def isolated_libraries(destination):
    # La fixture doit charger les octets du bundle testé, jamais une lib Homebrew locale.
    copied = {}
    pending = ["libtatsu.0.dylib", "libplist-2.0.4.dylib"]
    while pending:
        name = pending.pop()
        if name in copied:
            continue
        original = available.get(name)
        if original is None:
            raise RuntimeError("Dylib manquante : " + name)
        output = destination / name
        shutil.copy2(original, output)
        output.chmod(0o755)
        copied[name] = output
        subprocess.run(["/usr/bin/install_name_tool", "-id", "@rpath/" + name, str(output)], check=True)
        for dependency in dependencies(original):
            if dependency.startswith(("/usr/lib/", "/System/Library/")):
                continue
            child = Path(dependency).name
            if child == name:
                continue
            subprocess.run(["/usr/bin/install_name_tool", "-change", dependency,
                            "@loader_path/" + child, str(output)], check=True)
            pending.append(child)
    for path in copied.values():
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(path)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    return copied


def upstream_ir1_fixture():
    with tarfile.open(source_archive("idevicerestore")) as archive:
        members = [member for member in archive.getmembers() if member.name.endswith("/src/restore.c")]
        if len(members) != 1:
            raise RuntimeError("Source restore.c manquante ou ambiguë")
        source = archive.extractfile(members[0]).read().decode()
    start = source.index('} else if (strcmp(s_updater_name, "Savage") == 0) {',
                         source.index("static int restore_send_firmware_updater_data("))
    end = source.index('} else if (strcmp(s_updater_name, "Rose") == 0) {', start)
    # Compiler le bloc amont réel avec des handlers inertes : aucun protocole simulé.
    block = source[start:end].removeprefix("} else ") + "}\n"
    return r'''
#include <plist/plist.h>
#include <stdio.h>
#define LL_ERROR 0
#define logger(...) ((void)0)
#include <string.h>
static int selected, bad_info;
static plist_t expected_info;
static plist_t record(int value, plist_t info) {
    selected = value;
    bad_info = info != expected_info;
    return plist_new_dict();
}
static plist_t restore_get_yonkers_firmware_data(void *client, plist_t info, plist_t args) {
    return record(2, info);
}
static plist_t restore_get_generic_firmware_data(void *client, plist_t info, plist_t args) {
    return record(3, info);
}
static plist_t restore_get_savage_firmware_data(void *client, plist_t info, plist_t args) {
    return record(1, info);
}
static int route(plist_t p_info, plist_t expected) {
    void *client = NULL;
    plist_t arguments = NULL, fwdict = NULL;
    const char *s_updater_name = "Savage";
    selected = bad_info = 0;
    expected_info = expected;
''' + block + r'''
    plist_free(fwdict);
    return bad_info ? -2 : selected;
error_out:
    plist_free(fwdict);
    return -1;
}
int main(void) {
    const char *keys[] = {"YonkersDeviceInfo", "JasmineIR1DeviceInfo", "YonkersIR1,DeviceInfo",
                          "YonkersIR1,DeviceInfo", NULL};
    int expected[] = {2, 3, 3, 1, 1};
    int failures = 0;
    for (int i = 0; i < 5; i++) {
        plist_t info = plist_new_dict(), child = NULL;
        if (keys[i]) {
            child = i == 3 ? plist_new_string("invalid") : plist_new_dict();
            plist_dict_set_item(info, keys[i], child);
        }
        int result = route(info, i < 3 ? child : info);
        if (result != expected[i]) {
            fprintf(stderr, "routage %s: handler %d, attendu %d\n",
                    keys[i] ? keys[i] : "Savage", result, expected[i]);
            failures++;
        }
        plist_free(info);
    }
    if (failures) return 1;
    puts("5 routages FirmwareUpdater vérifiés depuis le vrai bloc amont.");
    return 0;
}
'''


class RestoreRuntimeTests(unittest.TestCase):
    def test_required_corrections_are_embedded(self):
        for package, (commit, digest) in PINS.items():
            with self.subTest(package=package):
                entry = next(item for item in source_manifest if item["package"] == package)
                self.assertEqual(entry.get("commit"), commit)
                self.assertEqual(entry["sha256"], digest)
                source_archive(package)
                origin = (notices / (package + "-" + commit[:8]) if options.bundle
                          else root / package / commit[:8])
                metadata = json.loads((origin / "upstream-build.json").read_text())
                self.assertEqual(metadata["commit"], commit)
                self.assertEqual(metadata["sha256"], digest)
                if manifest is not None:
                    entries = [item for item in manifest if item["package"] == package]
                    self.assertEqual(len(entries), 1)
                    self.assertEqual(entries[0]["version"], commit[:8])
        if options.runtime:
            subprocess.run(["python3", str(PROJECT / "scripts/bundle-runtime.py"), str(root),
                            "--check-runtime"], check=True)

    def compile_and_run(self, fixture, library_names):
        with tempfile.TemporaryDirectory(prefix="itelier-restore-runtime-test-") as directory:
            work = Path(directory).resolve()
            headers = work / "include"
            headers.mkdir()
            extract_headers("libplist", headers)
            extract_headers("libtatsu", headers)
            libs = work / "lib"
            libs.mkdir()
            copied = isolated_libraries(libs)
            source = work / "fixture.c"
            source.write_text(fixture)
            executable = work / "fixture"
            command = ["xcrun", "clang", "-mmacosx-version-min=14.0", "-I" + str(headers), str(source)]
            command += [str(copied[name]) for name in library_names]
            command += ["-Wl,-rpath," + str(libs), "-o", str(executable)]
            subprocess.run(command, check=True)
            result = subprocess.run([str(executable)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            print(result.stdout.strip())

    def test_real_yonkers_component_selection(self):
        fixture = (PROJECT / "scripts/fixtures/tatsu-yonkers.c").read_text()
        self.compile_and_run(fixture, ["libtatsu.0.dylib", "libplist-2.0.4.dylib"])

    def test_real_upstream_yonkers_ir1_routing(self):
        self.compile_and_run(upstream_ir1_fixture(), ["libplist-2.0.4.dylib"])


if __name__ == "__main__":
    unittest.main(argv=[__file__], verbosity=2)
