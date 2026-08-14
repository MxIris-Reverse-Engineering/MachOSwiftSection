import Foundation
import Testing

/// Mechanizes the NodeStore migration's headline invariant, which AGENTS.md
/// states in prose: **"Sources now carries zero cached `demangleAsNode(` call
/// sites."**
///
/// A behavioral test cannot enforce this. `SymbolIndexStore.Storage` holds
/// `NodeReference`s into a frozen arena, so materializing one twice yields two
/// distinct trees no matter which demangle entry point the build sweep used —
/// instance identity carries no signal about the sweep. Process-global
/// `NodeCache` counters are no better: every test target shares one process, so
/// concurrently running suites legitimately grow the cache and any delta is
/// racy. Scanning the sources is the only check that actually fails when the
/// invariant is broken, and it is deterministic.
///
/// The rule exists because the pre-migration pipeline interned every leaf and
/// subtree of every symbol into the process-global `NodeCache`, pinning the
/// whole graph for the process lifetime — the exact cost the migration was for.
/// A single reintroduced call site on an unbounded input restores it silently.
@Suite
struct NodeStoreMigrationInvariantTests {
    /// `Sources/`, resolved from this file (`Tests/MachOSymbolsTests/…`).
    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    private func swiftSourceFiles() throws -> [URL] {
        let sourcesDirectory = Self.sourcesDirectory
        let enumerator = try #require(
            FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil)
        )
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// `demangleAsNodeTransient` is the cache-free entry point; the bare
    /// `demangleAsNode` interns into the global `NodeCache`. Comment lines are
    /// skipped so the many places that *name* the banned call while explaining
    /// the rule (this file included, and AGENTS.md's mirrored notes in source
    /// doc comments) do not count as call sites.
    @Test func sourcesCarryNoCachedDemangleCallSites() throws {
        var offendingCallSites: [String] = []

        for sourceFile in try swiftSourceFiles() {
            guard let contents = try? String(contentsOf: sourceFile, encoding: .utf8) else { continue }
            for (lineIndex, line) in contents.components(separatedBy: .newlines).enumerated() {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !trimmedLine.hasPrefix("//") else { continue }
                guard line.contains("demangleAsNode(") else { continue }
                let relativePath = sourceFile.path.components(separatedBy: "/Sources/").last ?? sourceFile.path
                offendingCallSites.append("Sources/\(relativePath):\(lineIndex + 1): \(trimmedLine)")
            }
        }

        #expect(
            offendingCallSites.isEmpty,
            """
            cached `demangleAsNode(` reintroduced — use `demangleAsNodeTransient` for trees that are \
            consumed and dropped, or route batch interning through `InternedNodeReferenceCache`:
            \(offendingCallSites.joined(separator: "\n"))
            """
        )
    }

    /// Guards the scanner itself: a check that cannot fail is worse than no
    /// check, and this one is only as good as its ability to see a call site. A
    /// synthetic source file carrying the banned call must be reported, and its
    /// commented-out twin must not.
    @Test func theScannerActuallyDetectsACallSite() throws {
        let syntheticSource = """
        func real() throws {
            _ = try demangleAsNode(name)
        }
        // _ = try demangleAsNode(name)
        _ = try demangleAsNodeTransient(name)
        """

        var detectedLineNumbers: [Int] = []
        for (lineIndex, line) in syntheticSource.components(separatedBy: .newlines).enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.hasPrefix("//") else { continue }
            guard line.contains("demangleAsNode(") else { continue }
            detectedLineNumbers.append(lineIndex + 1)
        }

        #expect(detectedLineNumbers == [2], "the scanner must see the real call and only the real call")
    }
}
