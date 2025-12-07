import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport
@testable import SwiftInspection

@Suite(.serialized)
final class XcodeMachOFileDumpTests: XcodeMachOFileTests, DumpableTests, @unchecked Sendable {
    override class var fileName: XcodeMachOFileName { .sharedFrameworks(.SourceKitSupport) }
}

extension XcodeMachOFileDumpTests {
    @Test func typesInFile() async throws {
        try await dumpTypes(for: machOFile)
    }

    @Test func protocolsInFile() async throws {
        try await dumpProtocols(for: machOFile)
    }

    @Test func protocolConformancesInFile() async throws {
        try await dumpProtocolConformances(for: machOFile)
    }

    @Test func associatedTypesInFile() async throws {
        try await dumpAssociatedTypes(for: machOFile)
    }
}
