import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

final class ProtocolRequirementSignatureTests: DyldCacheTests, @unchecked Sendable {
    
    @Test func protocols() async throws {
        let machO = machOFileInMainCache
        let protocolDescriptors = try machO.swift.protocolDescriptors
        for protocolDescriptor in protocolDescriptors {
            let proto = try Protocol(descriptor: protocolDescriptor, in: machO)
            for requirementInSignature in proto.requirementInSignatures {
                let node = try MetadataReader.demangleType(for: requirementInSignature.paramManagledName, in: machO)
                node.print(using: .default).print()
                print(node)
                print("")
                print(requirementInSignature.flags.kind)
            }
            print("-------------------------------")
        }
    }
}
