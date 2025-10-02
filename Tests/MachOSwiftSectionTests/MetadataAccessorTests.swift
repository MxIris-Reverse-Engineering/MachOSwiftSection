import Foundation
import Testing
import Demangle
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
                let metadataResponse = metadataAccessor.perform(request: .init(state: .complete, isBlocking: false))
                print(metadataResponse.state)
                switch try metadataResponse.value.resolve(in: machO).kind {
                case .struct:
                    print("Struct")
                    let structMetadata = try metadataAccessor.perform(request: .init(state: .complete, isBlocking: false)).value.resolveAny(in: machO) as StructMetadata
                    print(try structMetadata.fieldOffsets(in: machO))
                case .class:
                    print("Class")
                    let classMetadata = try metadataAccessor.perform(request: .init(state: .complete, isBlocking: false)).value.resolveAny(in: machO) as ClassMetadataObjCInterop
                    print(try classMetadata.fieldOffsets(in: machO))
                default:
                    continue
                }
            }
        }
    }
}
