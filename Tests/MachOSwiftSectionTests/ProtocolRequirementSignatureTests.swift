import Foundation
import Testing
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

final class ProtocolRequirementSignatureTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @Test func protocols() async throws {
        let machO = machOFile
        let protocolDescriptors = try machO.swift.protocolDescriptors
        for protocolDescriptor in protocolDescriptors {
            let proto = try Protocol(descriptor: protocolDescriptor, in: machO)
            for requirement in proto.requirements {
                print(requirement.flags.kind)
            }
            print("-------------------------------")
        }
    }
}
