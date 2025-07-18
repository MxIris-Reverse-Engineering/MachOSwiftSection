import Foundation
import Testing
import MachOKit
import MachOMacro
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

@Suite(.serialized)
final class XcodeMachOFileDumpTests: XcodeMachOFileTests, DumpableTests {
    
    override class var fileName: XcodeMachOFileName { .sharedFrameworks(.DNTSourceKitSupport) }
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
