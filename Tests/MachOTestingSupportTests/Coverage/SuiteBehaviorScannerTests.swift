import Foundation
import Testing
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
struct SuiteBehaviorScannerTests {
    private var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    private func makeScanRoot() throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let source = try String(contentsOf: fixtureRoot.appendingPathComponent("SuiteSampleSource.swift.txt"))
        let dest = tempDir.appendingPathComponent("SuiteSampleSource.swift")
        try source.write(to: dest, atomically: true, encoding: .utf8)
        return tempDir
    }

    @Test func detectsAcrossAllReaders() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = SuiteBehaviorScanner(suiteRoot: root)
        let result = try scanner.scan()
        let key = MethodKey(typeName: "CrossReaderType", memberName: "liveMethod")
        #expect(result[key] == .acrossAllReaders)
    }

    @Test func detectsInProcessOnly() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = SuiteBehaviorScanner(suiteRoot: root)
        let result = try scanner.scan()
        let key = MethodKey(typeName: "RuntimeOnlyType", memberName: "kind")
        #expect(result[key] == .inProcessOnly)
    }

    @Test func detectsSentinel() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = SuiteBehaviorScanner(suiteRoot: root)
        let result = try scanner.scan()
        let key = MethodKey(typeName: "RegistrationOnlyType", memberName: "registrationOnly")
        #expect(result[key] == .sentinel)
    }

    @Test func detectsDirectReaderAsAcrossAllReaders() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = SuiteBehaviorScanner(suiteRoot: root)
        let result = try scanner.scan()
        let key = MethodKey(typeName: "DirectReaderType", memberName: "readerMethod")
        #expect(result[key] == .acrossAllReaders)
    }

    @Test func detectsDirectContextAsAcrossAllReaders() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = SuiteBehaviorScanner(suiteRoot: root)
        let result = try scanner.scan()
        let key = MethodKey(typeName: "DirectReaderType", memberName: "contextMethod")
        #expect(result[key] == .acrossAllReaders)
    }
}
