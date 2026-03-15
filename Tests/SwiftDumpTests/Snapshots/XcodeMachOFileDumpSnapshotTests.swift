import Foundation
import Testing
import SnapshotTesting
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

@Suite(.serialized, .snapshots(record: .missing))
final class XcodeMachOFileDumpSnapshotTests: XcodeMachOFileTests, SnapshotDumpableTests, @unchecked Sendable {
    override class var fileName: XcodeMachOFileName { .sharedFrameworks(.SourceKitSupport) }

    @Test func typesSnapshot() async throws {
        let output = try await collectDumpTypes(for: machOFile)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func protocolsSnapshot() async throws {
        let output = try await collectDumpProtocols(for: machOFile)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func protocolConformancesSnapshot() async throws {
        let output = try await collectDumpProtocolConformances(for: machOFile)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func associatedTypesSnapshot() async throws {
        let output = try await collectDumpAssociatedTypes(for: machOFile)
        assertSnapshot(of: output, as: .lines)
    }
}
