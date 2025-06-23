import Foundation
import Testing
import MachOKit
import MachOMacro
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

@Suite(.serialized)
struct MachOFileDumpTests: DumpableTest {
    let machOFile: MachOFile

    init() async throws {
        let file = try loadFromFile(named: .Finder)
        switch file {
        case .fat(let fatFile):
            self.machOFile = try #require(fatFile.machOFiles().first(where: { $0.header.cpu.subtype == .arm64(.arm64e) }))
        case .machO(let machO):
            self.machOFile = machO
        @unknown default:
            fatalError()
        }
    }
}

extension MachOFileDumpTests {
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
