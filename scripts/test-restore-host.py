#!/usr/bin/env python3
"""No USB access: test the durable worker against an inert temporary shell engine."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="rescope-host-test-") as work:
    root = Path(work)
    source = root / "HostTest.swift"
    source.write_text(r'''
import Foundation
import Darwin
@main struct HostTest {
    static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 3 && ["--parent", "--crash-parent"].contains(args[1]) {
            try RestoreHost.detach(executable: URL(fileURLWithPath: args[0]), directory: URL(fileURLWithPath: args[2]))
            if args[1] == "--crash-parent" { try await Task.sleep(nanoseconds: 30_000_000_000) }
            // The launching UI/process exits immediately; its worker must continue independently.
            exit(0)
        }
        guard args.count == 2 else { exit(2) }
        let directory = URL(fileURLWithPath: args[1])
        let root = directory.deletingLastPathComponent()
        exit(await RestoreHost.runWorker(sessionPath: directory.path, root: root,
            engine: root.appendingPathComponent("inert-engine")))
    }
}
''')
    binary = root / "HostTest"
    subprocess.run(["swiftc", "-module-cache-path", str(root / "ModuleCache"), "-swift-version", "5", "-parse-as-library",
                    *map(str, sorted((repo / "Sources/ReScopeCore").glob("*.swift"))), str(source), "-o", str(binary)], check=True)
    engine = root / "inert-engine"
    engine.write_text("#!/bin/sh\nprintf 'progress: 4 0.2\\n'\nprintf 'inert-started\\n'\nsleep 2\nprintf 'Status: Restore Finished\\n'\nprintf 'inert-finished\\n'\nexit 0\n")
    engine.chmod(0o700)
    firmware = root / "fixture.ipsw"
    firmware.write_bytes(b"inert test fixture, never an iOS image")

    def session(digest=None):
        directory = root / str(uuid.uuid4())
        directory.mkdir(mode=0o700)
        (directory / "request.json").write_text(json.dumps({
            "arguments": ["--variant", "Customer Upgrade Install (IPSW)", "-y", "-P", "-i", "4660", str(firmware)],
            "firmwareSHA256": digest or hashlib.sha256(firmware.read_bytes()).hexdigest()
        }))
        return directory

    def state(directory):
        try:
            return json.loads((directory / "state.json").read_text())
        except FileNotFoundError:
            return None

    def until(predicate, seconds=10):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            result = predicate()
            if result:
                return result
            time.sleep(0.05)
        raise AssertionError("Timed out waiting for the inert worker")

    first = session()
    parent = subprocess.run([str(binary), "--parent", str(first)], check=True)
    try:
        until(lambda: (s if (s := state(first)) and not s["finished"] else None))
    except AssertionError:
        print("Worker state:", state(first), flush=True)
        raise
    assert parent.returncode == 0
    concurrent = session()
    assert subprocess.run([str(binary), str(concurrent)]).returncode == 4, "Concurrent worker was not blocked"
    finished = until(lambda: (s if (s := state(first)) and s["finished"] else None))
    assert finished["exitCode"] == 0
    assert "inert-finished" in finished["log"], "Worker stopped when its parent exited"
    assert subprocess.run([str(binary), str(first)]).returncode == 3, "Completed request was replayed"
    crashed = session()
    parent = subprocess.Popen([str(binary), "--crash-parent", str(crashed)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        until(lambda: (s if (s := state(crashed)) and not s["finished"] else None))
        parent.kill()
        assert parent.wait(timeout=5) == -9
        survived = until(lambda: (s if (s := state(crashed)) and s["finished"] else None))
        assert survived["exitCode"] == 0 and "inert-finished" in survived["log"], "Parent crash stopped the worker"
    finally:
        if parent.poll() is None:
            parent.kill()
            parent.wait(timeout=5)
    altered = session(digest="0" * 64)
    assert subprocess.run([str(binary), str(altered)]).returncode == 1
    assert "inert-started" not in state(altered)["log"], "Changed IPSW reached the engine"
    engine.write_text("#!/bin/sh\nprintf 'Unable to fetch Yonkers ticket\\nUnable to successfully restore device\\nDONE\\nprogress: 4 1\\n'\nexit 0\n")
    false_success = session()
    assert subprocess.run([str(binary), str(false_success)]).returncode == 1
    rejected = state(false_success)
    assert rejected["engineCompletion"] == "failed" and rejected["exitCode"] == 1
    assert rejected.get("progress") is None, "Failed install retained 100% progress"
    engine.write_text("#!/bin/sh\nprintf 'DONE\\nprogress: 4 1\\n'\nexit 0\n")
    unconfirmed = session()
    assert subprocess.run([str(binary), str(unconfirmed)]).returncode == 2
    assert state(unconfirmed)["engineCompletion"] == "unconfirmed"
    engine.write_text("#!/bin/sh\nprintf 'Status: Restore Finished\\n'\ni=0\nwhile [ \"$i\" -lt 170 ]; do printf 'subsequent log output\\n'; i=$((i+1)); done\nprintf 'DONE\\n'\nexit 0\n")
    trimmed = session()
    assert subprocess.run([str(binary), str(trimmed)]).returncode == 0
    confirmed = state(trimmed)
    assert confirmed["engineCompletion"] == "confirmed" and confirmed["exitCode"] == 0
    assert "Status: Restore Finished" not in confirmed["log"], "Fixture did not exercise trimmed final status"
    print("PASS: worker survives parent exit and SIGKILL, concurrent writes/replay/changed IPSW blocked; false exit-0 success rejected, final status preserved. No USB tool executed.")
