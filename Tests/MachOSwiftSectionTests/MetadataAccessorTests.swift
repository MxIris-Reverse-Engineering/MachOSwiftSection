import Foundation
import Testing
import Demangling
@testable import MachOTestingSupport
@testable import MachOSwiftSection
@testable import SwiftDump

final class MetadataAccessorTests: MachOImageTests {
    override class var imageName: MachOImageName { .SwiftUI }

    @MainActor
    @Test func test() async throws {
        let machO = machOImage
        for typeContextDescriptorWrapper in try machO.swift.typeContextDescriptors {
            guard !typeContextDescriptorWrapper.typeContextDescriptor.layout.flags.isGeneric else { continue }
            if let metadataAccessor = try typeContextDescriptorWrapper.typeContextDescriptor.metadataAccessor(in: machO) {
                let metadataResponse = metadataAccessor.perform(request: .init())
                print(metadataResponse.state)
                let metadata = try metadataResponse.value.resolve(in: machO)
                switch metadata {
                case .class(let classMetadata):
                    try print(classMetadata.fieldOffsets(in: machO))
                case .struct(let structMetadata):
                    try print(structMetadata.fieldOffsets(in: machO))
                case .enum(let enumMetadata):
                    try print(enumMetadata.payloadSize(in: machO) ?? 0)
                case .optional(let enumMetadata):
                    try print(enumMetadata.payloadSize(in: machO) ?? 0)
                default:
                    continue
                }
            }
        }
    }
}
