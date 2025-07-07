import Foundation
import Testing
import MachOKit
import MachOMacro
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

@Suite(.serialized)
final class MachOFileDumpTests: MachOFileTests, DumpableTests {
    override class var fileName: MachOFileName { .iOS_22E238_Simulator_SwiftUI }
}

extension MachOFileDumpTests {
    @Test func typesInFile() async throws {
        try await dumpTypes(for: machOFile, isDetail: false)
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
