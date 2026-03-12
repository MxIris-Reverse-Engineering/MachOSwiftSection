import Foundation
import Testing
import SnapshotTesting
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

@Suite(.serialized, .snapshots(record: .missing))
final class DyldCacheDumpSnapshotTests: DyldCacheTests, SnapshotDumpableTests, @unchecked Sendable {
    override class var cachePath: DyldSharedCachePath { .macOS_15_5 }

    override class var cacheImageName: MachOImageName { .Sharing }

    @Test func typesSnapshot() async throws {
        let output = try await collectDumpTypes(for: machOFileInCache)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func protocolsSnapshot() async throws {
        let output = try await collectDumpProtocols(for: machOFileInCache)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func protocolConformancesSnapshot() async throws {
        let output = try await collectDumpProtocolConformances(for: machOFileInCache)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func associatedTypesSnapshot() async throws {
        let output = try await collectDumpAssociatedTypes(for: machOFileInCache)
        assertSnapshot(of: output, as: .lines)
    }
}
