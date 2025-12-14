import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport
@testable import SwiftInspection

@Suite(.serialized)
final class MachOFileDumpTests: MachOFileTests, DumpableTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .iOS_18_5_Simulator_SwiftUI }
}

extension MachOFileDumpTests {
    @Test func typesInFile() async throws {
        try await dumpTypes(for: machOFile, isDetail: true)
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
