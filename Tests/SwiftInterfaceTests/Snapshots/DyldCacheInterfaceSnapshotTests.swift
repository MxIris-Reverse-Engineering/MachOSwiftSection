import Foundation
import Testing
import SnapshotTesting
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftInterface
@_spi(Internals) @testable import MachOSymbols
@_spi(Internals) @testable import MachOCaches

@Suite(.serialized, .snapshots(record: .missing))
final class DyldCacheInterfaceSnapshotTests: DyldCacheTests, SnapshotInterfaceTests, @unchecked Sendable {
    override class var cachePath: DyldSharedCachePath { .macOS_15_5 }

    override class var cacheImageName: MachOImageName { .Sharing }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    @Test func interfaceSnapshot() async throws {
        let output = try await collectInterfaceString(in: machOFileInCache)
        assertSnapshot(of: output, as: .lines)
    }
}
