import Foundation

private let harnessLock = NSLock()
var passed = 0
var failed = 0

func expect(
    _ label: String,
    _ condition: Bool,
    detail: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    harnessLock.lock()
    defer { harnessLock.unlock() }

    if condition {
        print("  ✓ \(label)")
        passed += 1
    } else {
        let fileName = URL(fileURLWithPath: "\(file)").lastPathComponent
        let suffix = detail.isEmpty ? "" : " — \(detail)"
        print("  ✗ [\(fileName):\(line)] \(label)\(suffix)")
        failed += 1
    }
}

func section(_ title: String) {
    print("\n\(title)")
}

func expectEqual<T: Equatable>(
    _ label: String,
    _ actual: T,
    _ expected: T,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let detailMessage = "got '\(actual)', expected '\(expected)'"
    expect(label, actual == expected, detail: detailMessage, file: file, line: line)
}

func expectTrue(
    _ label: String,
    _ condition: Bool,
    detail: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    expect(label, condition, detail: detail, file: file, line: line)
}

func expectFalse(
    _ label: String,
    _ condition: Bool,
    detail: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let detailMsg = detail.isEmpty ? "expected false but got true" : detail
    expect(label, !condition, detail: detailMsg, file: file, line: line)
}

func expectNil<T>(
    _ label: String,
    _ value: T?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let detailMessage = value != nil ? "expected nil but got '\(value!)'" : ""
    expect(label, value == nil, detail: detailMessage, file: file, line: line)
}

func expectNotNil<T>(
    _ label: String,
    _ value: T?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let detailMessage = value == nil ? "expected non-nil value but got nil" : ""
    expect(label, value != nil, detail: detailMessage, file: file, line: line)
}

func expectContains<S: Sequence>(
    _ label: String,
    _ sequence: S,
    _ element: S.Element,
    file: StaticString = #filePath,
    line: UInt = #line
) where S.Element: Equatable {
    let contains = sequence.contains(element)
    let detailMessage = contains ? "" : "element '\(element)' not found in sequence"
    expect(label, contains, detail: detailMessage, file: file, line: line)
}

func expectThrows<E: Error>(
    _ label: String,
    expectedErrorType: E.Type,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ block: () throws -> Void
) {
    do {
        try block()
        expect(label, false, detail: "expected error of type \(E.self) to be thrown, but block succeeded", file: file, line: line)
    } catch is E {
        expect(label, true, file: file, line: line)
    } catch {
        expect(label, false, detail: "expected error of type \(E.self) but caught '\(error)'", file: file, line: line)
    }
}

func expectAsyncThrows<E: Error>(
    _ label: String,
    expectedErrorType: E.Type,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ block: () async throws -> Void
) async {
    do {
        _ = try await block()
        expect(label, false, detail: "expected error of type \(E.self) to be thrown, but async block succeeded", file: file, line: line)
    } catch is E {
        expect(label, true, file: file, line: line)
    } catch {
        expect(label, false, detail: "expected error of type \(E.self) but caught '\(error)'", file: file, line: line)
    }
}

func finishTests() {
    print("\n────────────────────────────────────────")
    harnessLock.lock()
    let total = passed + failed
    let currentPassed = passed
    let currentFailed = failed
    harnessLock.unlock()

    print("Results: \(currentPassed)/\(total) passed", currentFailed > 0 ? "(\(currentFailed) FAILED)" : "")
    if currentFailed > 0 { exit(1) }
}

