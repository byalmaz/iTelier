#!/usr/bin/env bash
# Run the existing XCTest test bodies on a Mac whose Command Line Tools omit XCTest.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/rescope-core-tests.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

command -v swiftc >/dev/null || { printf '%s\n' 'Swift 6 or newer is required.' >&2; exit 1; }
command -v python3 >/dev/null || { printf '%s\n' 'Python 3 is required to generate the temporary test entry point.' >&2; exit 1; }

python3 - "$work_dir" "$repo_dir"/Tests/ReScopeCoreTests/*.swift <<'PY'
from pathlib import Path
import re
import sys

work = Path(sys.argv[1])
suites = []
# Each test file compiles as its own source file, so file-private helpers of
# different files cannot collide. One XCTestCase class per file.
for index, path in enumerate(sorted(Path(p) for p in sys.argv[2:])):
    source = path.read_text(encoding="utf-8")
    # Keep the test methods and their assertions verbatim. They compile with the same core files.
    source = source.replace("import XCTest\n", "import Foundation\n").replace("@testable import ReScopeCore\n", "")
    classes = re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", source)
    if len(classes) != 1:
        raise SystemExit(path.name + " must declare exactly one XCTestCase class.")
    methods = re.findall(r"\bfunc\s+(test\w+)\s*\(\)\s*([^\{]*)\{", source)
    declared = re.findall(r"\bfunc\s+(test\w+)\s*\(", source)
    if not methods or len(methods) != len(declared):
        raise SystemExit("Cannot enumerate every XCTest method in " + path.name + "; update this runner before adding parameterized tests.")
    if len(set(name for name, _ in methods)) != len(methods):
        raise SystemExit("Duplicate test names are not supported: " + path.name)
    for name, signature in methods:
        if signature.split() not in ([], ["throws"], ["async"], ["async", "throws"]):
            raise SystemExit("Unsupported test signature: " + name + signature)
    (work / ("Tests%d_%s" % (index, path.name))).write_text(source, encoding="utf-8")
    suites.append((classes[0], methods))

helpers = r'''
// Minimal XCTest-compatible assertions used only by this temporary executable.
// A failed assertion records a failure and the runner exits nonzero.
var testFailures = 0
// Comme XCTestCase, hériter de NSObject pour détecter les conflits de propriétés.
class XCTestCase: NSObject {}
func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    testFailures += 1
    print("FAIL \(file):\(line): \(message)")
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { XCTFail(message, file: file, line: line) } }
    catch { XCTFail(String(describing: error), file: file, line: line) }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() { XCTFail(message, file: file, line: line) } }
    catch { XCTFail(String(describing: error), file: file, line: line) }
}
func XCTAssertEqual<T: Equatable>(_ actual: @autoclosure () throws -> T, _ expected: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let a = try actual(); let b = try expected()
        if a != b { XCTFail("\(a) != \(b). " + message, file: file, line: line) }
    } catch { XCTFail(String(describing: error), file: file, line: line) }
}
func XCTAssertGreaterThan<T: Comparable>(_ actual: @autoclosure () throws -> T, _ expected: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try actual() <= expected() { XCTFail(message, file: file, line: line) } }
    catch { XCTFail(String(describing: error), file: file, line: line) }
}
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() != nil { XCTFail(message, file: file, line: line) } }
    catch { XCTFail(String(describing: error), file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); XCTFail("Expected throw. " + message, file: file, line: line) }
    catch {}
}
'''

runner = "import Foundation\n@main struct StandaloneTests { static func main() async {\n"
count = 0
for index, (suite_name, methods) in enumerate(suites):
    runner += "let suite%d = %s()\n" % (index, suite_name)
    for name, signature in methods:
        count += 1
        runner += "let failuresBefore%d = testFailures\n" % count
        call = ("try " if "throws" in signature else "") + ("await " if "async" in signature else "") + "suite%d.%s()" % (index, name)
        if "throws" in signature:
            runner += 'do { ' + call + ' } catch { XCTFail("' + name + ': \\(error)") }\n'
        else:
            runner += call + "\n"
        runner += 'print("\\(testFailures == failuresBefore%d ? "PASS" : "FAIL") %s.%s")\n' % (count, suite_name, name)
runner += 'print("Executed ' + str(count) + ' core tests, \\(testFailures) failures")\n'
runner += "if testFailures > 0 { exit(1) }\n} }\n"
(work / "XCTestShim.swift").write_text("import Foundation\n" + helpers, encoding="utf-8")
(work / "TestMain.swift").write_text(runner, encoding="utf-8")
print("Running", count, "existing XCTest test bodies from", len(suites), "files with the standalone core runner.")
PY

swiftc -module-cache-path "$work_dir/ModuleCache" -swift-version 5 -parse-as-library \
    "$repo_dir"/Sources/ReScopeCore/*.swift "$work_dir"/*.swift -o "$work_dir/CoreTests"
"$work_dir/CoreTests"
