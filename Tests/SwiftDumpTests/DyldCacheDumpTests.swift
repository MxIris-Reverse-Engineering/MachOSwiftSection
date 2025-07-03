import Foundation
import Testing
import MachOKit
import MachOMacro
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

@Suite(.serialized)
final class DyldCacheDumpTests: DyldCacheTests, DumpableTests {
//    override class var cacheImageName: MachOImageName { .SwiftUI }
}

extension DyldCacheDumpTests {
    @Test func typesInCacheFile() async throws {
        try await dumpTypes(for: machOFileInCache)
    }

    @Test func typesInMainCacheFile() async throws {
        try await dumpTypes(for: machOFileInMainCache)
    }

    @Test func typesInSubCacheFile() async throws {
        try await dumpTypes(for: machOFileInSubCache)
    }

    @Test func protocolsInCacheFile() async throws {
        try await dumpProtocols(for: machOFileInCache)
    }

    @Test func protocolsInMainCacheFile() async throws {
        try await dumpProtocols(for: machOFileInMainCache)
    }

    @Test func protocolsInSubCacheFile() async throws {
        try await dumpProtocols(for: machOFileInSubCache)
    }

    @Test func protocolConformancesInCacheFile() async throws {
        try await dumpProtocolConformances(for: machOFileInCache)
    }

    @Test func protocolConformancesInMainCacheFile() async throws {
        try await dumpProtocolConformances(for: machOFileInMainCache)
    }

    @Test func protocolConformancesInSubCacheFile() async throws {
        try await dumpProtocolConformances(for: machOFileInSubCache)
    }

    @Test func associatedTypesInCacheFile() async throws {
        try await dumpAssociatedTypes(for: machOFileInCache)
    }

    @Test func associatedTypesInCacheMainFile() async throws {
        try await dumpAssociatedTypes(for: machOFileInMainCache)
    }

    @Test func associatedTypesInSubCacheFile() async throws {
        try await dumpAssociatedTypes(for: machOFileInSubCache)
    }

    @Test func builtinTypesInCacheFile() async throws {
        try await dumpBuiltinTypes(for: machOFileInCache)
    }

    @Test func builtinTypesInMainCacheFile() async throws {
        try await dumpBuiltinTypes(for: machOFileInMainCache)
    }

    @Test func builtinTypesInSubCacheFile() async throws {
        try await dumpBuiltinTypes(for: machOFileInSubCache)
    }
}
