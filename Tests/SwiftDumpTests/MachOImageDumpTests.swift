import Foundation
import Testing
import MachOKit
import MachOMacro
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

@Suite(.serialized)
final class MachOImageDumpTests: MachOImageTests, DumpableTests {}

extension MachOImageDumpTests {
    @Test func typesInImage() async throws {
        try await dumpTypes(for: machOImage)
    }

    @Test func protocolsInImage() async throws {
        try await dumpProtocols(for: machOImage)
    }

    @Test func protocolConformancesInImage() async throws {
        try await dumpProtocolConformances(for: machOImage)
    }

    @Test func associatedTypesInImage() async throws {
        try await dumpAssociatedTypes(for: machOImage)
    }
}
