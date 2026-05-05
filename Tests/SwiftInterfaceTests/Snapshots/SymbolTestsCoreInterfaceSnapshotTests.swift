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
        let output = try await collectInterfaceString(in: machOFile)
        assertSnapshot(of: output, as: .lines)
    }
}
