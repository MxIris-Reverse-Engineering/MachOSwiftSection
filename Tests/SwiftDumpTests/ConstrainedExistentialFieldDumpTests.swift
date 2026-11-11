import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport
import MachOFixtureSupport

/// The dump printed a stored property of a constrained existential type
/// (`any Boxed<Int>`) as the symbolic reference its field record holds —
/// `symbolic existential type (non-unique) 0x0 <Swift.Int>` — which names no
/// protocol (evolution proposal `existential-any`).
@Suite
final class ConstrainedExistentialFieldDumpTests: MachOFileTests, SnapshotDumpableTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @Test func dumpNamesTheProtocolOfAConstrainedExistentialField() async throws {
        let dump = try await collectDumpTypes(for: machOFile, options: [.struct])
        let fieldLines = dump.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let boxed = try #require(fieldLines.first { $0.hasPrefix("var boxed: ") })
        let optionalBoxed = try #require(fieldLines.first { $0.hasPrefix("var optionalBoxed: ") })
        #expect(boxed.hasPrefix("var boxed: any SymbolTestsCore.GenericFieldLayout.Boxed<"), "\(boxed)")
        #expect(boxed.contains("Swift.Int"), "\(boxed)")
        #expect(!boxed.contains("symbolic existential type"), "\(boxed)")
        #expect(optionalBoxed.hasPrefix("var optionalBoxed: (any SymbolTestsCore.GenericFieldLayout.Boxed<"), "\(optionalBoxed)")
        #expect(optionalBoxed.contains("Swift.String"), "\(optionalBoxed)")
    }
}
