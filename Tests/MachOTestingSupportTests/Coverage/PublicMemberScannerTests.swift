import Foundation
import Testing
@testable import MachOTestingSupport

@Suite
struct PublicMemberScannerTests {
    private var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Coverage/
            .appendingPathComponent("Fixtures")
    }

    /// Scanner reads `.swift` files in the directory. We renamed our test source to
    /// `.swift.txt` to avoid build inclusion, then rename a tmp copy to `.swift` for the scan.
    private func makeScanRoot() throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let source = try String(contentsOf: fixtureRoot.appendingPathComponent("SampleSource.swift.txt"))
        let dest = tempDir.appendingPathComponent("SampleSource.swift")
        try source.write(to: dest, atomically: true, encoding: .utf8)
        return tempDir
    }

    @Test func collectsPublicMembers() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let result = try scanner.scan()

        #expect(result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "name")))
        #expect(result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "nameOptional")))
        #expect(result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "init(custom:)")))
        #expect(result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "sectionedFoo")))
    }

    @Test func skipsInternalAndPrivate() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let result = try scanner.scan()

        #expect(!result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "internalHelper")))
        #expect(!result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "hidden")))
    }

    @Test func skipsSPI() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let result = try scanner.scan()

        #expect(!result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "spiHidden")))
    }

    @Test func skipsMemberwiseInit() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let result = try scanner.scan()

        // The 2-arg `init(layout:offset:)` should be filtered as MemberwiseInit synthesized.
        #expect(!result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "init(layout:offset:)")))
    }

    @Test func skipsLayoutTypes() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let result = try scanner.scan()

        // Scanner skips members of types named exactly `Layout` (the nested
        // record struct convention), but does NOT skip top-level types whose
        // name merely ends with `Layout` (e.g., real public API like TypeLayout).
        #expect(!result.contains(MethodKey(typeName: "Layout", memberName: "offset")))
    }

    @Test func appliesAllowlist() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let allowlist: Set<MethodKey> = [MethodKey(typeName: "SampleDescriptor", memberName: "name")]
        let result = try scanner.scan(applyingAllowlist: allowlist)
        #expect(!result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "name")))
    }

    @Test func collectsPublicSubscript() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let result = try scanner.scan()

        #expect(result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "subscript(dynamicMember:)")))
    }
}
