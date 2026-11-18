import Foundation
import Testing
@testable import CrossReferenceAnalysis

/// The renamed re-exports are read from every image's export trie, and a
/// process may load an image whose trie is malformed: its sizes and offsets
/// are read as they stand, so none of them may carry the walk past the
/// trie or trap on its arithmetic.
@Suite
struct MalformedExportTrieTests {
    /// The root node's terminal size is a ULEB128 of `Int.max`, so where its
    /// children start lies past every address — an overflow, were it added to
    /// the cursor as it stands. Read in a child process: a trap ends the
    /// process, not the test run.
    @Test func aTerminalSizePastTheTrieEndsTheNodeWithoutTrapping() async {
        await #expect(processExitsWith: .success) {
            let trie: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F]
            let entries = trie.withUnsafeBufferPointer { buffer -> [RenamedReexportIndex.TrieEntry]? in
                guard let base = buffer.baseAddress else { return nil }
                return RenamedReexportIndex.renamedReexports(inTrieAt: base, size: buffer.count)
            }
            // Nothing in it is a re-export.
            guard let entries, entries.isEmpty else { exit(EXIT_FAILURE) }
        }
    }
}
