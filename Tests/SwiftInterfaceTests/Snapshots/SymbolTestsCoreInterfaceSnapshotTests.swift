@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
import Foundation
import Testing
import SnapshotTesting
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport
@testable import SwiftInterface

@Suite(.serialized, .snapshots(record: .missing))
final class SymbolTestsCoreInterfaceSnapshotTests: MachOFileTests, SnapshotInterfaceTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    @Test func interfaceSnapshot() async throws {
        // The AccessorFunctionReferences fixture namespace renders kind-9
        // fallbacks whose embedded file offsets shift on every fixture
        // rebuild; normalize them so this whole-module snapshot stays
        // rebuild-stable (see `normalizingAccessorFunctionOffsets`).
        let output = try await collectInterfaceString(in: machOFile)
        assertSnapshot(of: normalizingAccessorFunctionOffsets(output), as: .lines)
    }
}
