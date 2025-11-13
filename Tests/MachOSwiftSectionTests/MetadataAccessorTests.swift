import Foundation
import System
import Testing
import Demangling
import MachOKit
@testable import MachOTestingSupport
@testable import MachOSwiftSection
@testable import SwiftDump
import MachOUtilitiesC

#if canImport(SwiftUI)
import SwiftUI
#endif

final class MetadataAccessorTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUI }

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
        let machO = machOImage
        for typeContextDescriptorWrapper in try machO.swift.typeContextDescriptors {
            guard typeContextDescriptorWrapper.typeContextDescriptor.layout.flags.isGeneric else { continue }
            guard try typeContextDescriptorWrapper.namedContextDescriptor.name(in: machO) == "NSHostingView" else { continue }
            if let metadataAccessor = try typeContextDescriptorWrapper.typeContextDescriptor.metadataAccessor(in: machO) {
                let metadataResponse = metadataAccessor.perform(request: .init(), args: TestView.self)
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

    @Test func machOImageForAddress() async throws {
        guard let ptr = dyld_image_header_containing_address(unsafeBitCast(Image.self, to: UnsafeRawPointer.self)) else { return }
        print(MachOImage(ptr: ptr).path ?? "nil")
    }
}
