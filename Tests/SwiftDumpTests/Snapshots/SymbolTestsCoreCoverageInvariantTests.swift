import Foundation
import Testing

private extension String {
    /// Returns the string with only the first character lowercased.
    /// Preserves subsequent acronyms / CamelCase (e.g. "VTableEntryVariants"
    /// → "vTableEntryVariants"; "ResultBuilderDSL" → "resultBuilderDSL").
    var lowercasedFirst: String {
        guard let first = first else { return self }
        return String(first).lowercased() + dropFirst()
    }
}

@Suite
struct SymbolTestsCoreCoverageInvariantTests {
    /// `@Test` method names declared on SymbolTestsCoreDumpSnapshotTests that intentionally
    /// have no backing category source file (edge-case shims, if any).
    private static let allowlist: Set<String> = []

    @Test @MainActor func everyCategoryHasASnapshotTest() throws {
        let fixtureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Snapshots/
            .deletingLastPathComponent()   // SwiftDumpTests/
            .deletingLastPathComponent()   // Tests/
            .appendingPathComponent("Projects/SymbolTests/SymbolTestsCore")

        let categories = try FileManager.default
            .contentsOfDirectory(at: fixtureDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()

        let expectedMethods = Set(categories.map { "\($0.lowercasedFirst)Snapshot" })
        let actualMethods = SymbolTestsCoreDumpSnapshotTests.registeredTestMethodNames

        let missing = expectedMethods.subtracting(actualMethods).subtracting(Self.allowlist)
        #expect(missing.isEmpty, "Missing per-category snapshot tests: \(missing.sorted())")

        let extra = actualMethods.subtracting(expectedMethods).subtracting(Self.allowlist)
        #expect(extra.isEmpty, "Registered snapshot tests with no matching SymbolTestsCore source file: \(extra.sorted())")
    }
}
