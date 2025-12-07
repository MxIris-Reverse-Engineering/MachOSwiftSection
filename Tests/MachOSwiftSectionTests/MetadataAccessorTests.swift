import Foundation
import System
import Testing
import Demangling
import MachOKit
@testable import MachOTestingSupport
@testable import MachOSwiftSection
@testable import SwiftDump
import DyldPrivate

#if canImport(SwiftUI)
import SwiftUI
#endif

public enum MultiPayloadEnumTests {
    case closure(() -> Void)
    case object(NSObject)
    case tuple(a: Int, b: Double)
    case empty
}

final class MetadataAccessorTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUICore }

    struct TestView: View {
        var body: some View {
            EmptyView()
        }
    }

    struct TestScene: Scene {
        var body: some Scene {
            WindowGroup {
                EmptyView()
            }
        }
    }

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

    @Test func metadata() async throws {
//        let machO = MachOImage.current()
        let machO = machOImage
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let typeContextDescriptor = contextDescriptor.typeContextDescriptor else { continue }
            guard !typeContextDescriptor.layout.flags.isGeneric else { continue }
            if let metadataAccessor = try typeContextDescriptor.metadataAccessor(in: machO) {
                let metadataResponse = metadataAccessor.perform(request: .init(state: .complete, isBlocking: true))
                let metadata = try metadataResponse.value.resolve(in: machO)
                switch metadata {
//                case .class(let classMetadata):
//                    try print(classMetadata.fieldOffsets(in: machO))
//                case .struct(let structMetadata):
//                    try print(structMetadata.fieldOffsets(in: machO))
                case .enum(let enumMetadata):
//                    guard try enumMetadata.descriptor.resolve(in: machO).name(in: machO) == "MultiPayloadEnumTests" else { continue }
                    let descriptor = try enumMetadata.enumDescriptor(in: machO)
                    try await Enum(descriptor: descriptor, in: machO).dump(using: .demangleOptions(.default), in: machO).string.print()
                    let typeLayout = try enumMetadata.valueWitnesses(in: machO).typeLayout
                    print(typeLayout)
                    try print("PayloadSize", enumMetadata.payloadSize(in: machO) ?? 0)
                    print(getEnumTagCounts(payloadSize: typeLayout.size, emptyCases: descriptor.numEmptyCases, payloadCases: descriptor.numberOfPayloadCases))
//                case .optional(let enumMetadata):
//                    try print(enumMetadata.payloadSize(in: machO) ?? 0)
                default:
                    continue
                }
            }
        }
    }

    @Test func machOImageForAddress() async throws {
        guard let ptr = dyld_image_header_containing_address(unsafeBitCast(Image.self, to: UnsafeRawPointer.self)) else { return }
        print(MachOImage(ptr: ptr).path ?? "nil")
    }

    @Test func metadataCreate() async throws {
        let (machO, metadata) = try #require(try StructMetadata.createInMachO(Image.self))
        print(machO.ptr, metadata.offset)
    }
}
