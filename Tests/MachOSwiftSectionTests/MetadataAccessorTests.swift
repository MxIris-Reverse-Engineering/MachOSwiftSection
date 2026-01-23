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

enum MultiPayloadEnumTests {
    case closure(() -> Void)
    case object(NSObject)
    case tuple(a: Int, b: Double)
    case empty
}

struct GenericStructNonRequirement<A> {
    var field1: Double
    var field2: A
    var field3: Int
}

struct GenericStructLayoutRequirement<A: AnyObject> {
    var field1: Double
    var field2: A
    var field3: Int
}

struct GenericStructSwiftProtocolRequirement<A: Equatable & Collection & Codable> {
    var field1: Double
    var field2: A
    var field3: Int
}

struct GenericStructObjCProtocolRequirement<A: NSTableViewDelegate> {
    var field1: Double
    var field2: A
    var field3: Int
}

struct TestView: View {
    var body: some View {
        EmptyView()
    }
}

final class MetadataAccessorTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUICore }

    override init() async throws {
        try await super.init()
//        _ = GenericStructSwiftProtocolRequirement(field1: 0.0, field2: 0, field3: 0)
    }

    @MainActor
    @Test func test() async throws {
        let machO = machOImage
        for typeContextDescriptorWrapper in try machO.swift.typeContextDescriptors {
            guard !typeContextDescriptorWrapper.typeContextDescriptor.layout.flags.isGeneric else { continue }
            if let metadataAccessor = try typeContextDescriptorWrapper.typeContextDescriptor.metadataAccessorFunction(in: machO) {
                let metadataResponse = try metadataAccessor(request: .init())
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
            if let metadataAccessor = try typeContextDescriptor.metadataAccessorFunction(in: machO) {
                let metadataResponse = try metadataAccessor(request: .init(state: .complete, isBlocking: true))
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
                    print(getEnumTagCounts(payloadSize: typeLayout.size, emptyCases: descriptor.numEmptyCases.cast(), payloadCases: descriptor.numberOfPayloadCases.cast()))
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

    @Test func genericStruct() async throws {
        let machO = MachOImage.current()
        for context in try machO.swift.contextDescriptors {
            guard let type = context.typeContextDescriptorWrapper else { continue }
            switch type {
            case .enum:
                continue
            case .struct(let `struct`):
                let inProcessStruct = `struct`.asPointerWrapper(in: machO)
                let name = try inProcessStruct.name()
                if name == "GenericStructSwiftProtocolRequirement" {
                    try print(
                        inProcessStruct.metadataAccessorFunction()!.callAsFunction(
                            request: .init(),
                            eachMetadatas: Metadata.createInProcess([Int].self),
                            witnessTables: RuntimeFunctions.conformsToProtocol(metadata: [Int].self, existentialTypeMetadata: (any Equatable).self),
                            RuntimeFunctions.conformsToProtocol(metadata: [Int].self, existentialTypeMetadata: (any Collection).self),
                            RuntimeFunctions.conformsToProtocol(metadata: [Int].self, existentialTypeMetadata: (any Decodable).self),
                            RuntimeFunctions.conformsToProtocol(metadata: [Int].self, existentialTypeMetadata: (any Encodable).self)
                        ).value.resolve()
                    )
                } else if name == "GenericStructObjCProtocolRequirement" {
                    let metadata = try inProcessStruct.metadataAccessorFunction()!.callAsFunction(
                        request: .init(),
                        eachMetadatas: Metadata.createInProcess(NSObject.self)
                    ).value.resolve()
                    try print(metadata.struct!.fieldOffsets())
                }
            case .class:
                continue
            }
        }
    }

    @Test func genericSignatures() async throws {
        let machO = machOImage

        for type in try machO.swift.typeContextDescriptors {
            switch type {
            case .enum(let enumDescriptor):
                guard let genericContext = try enumDescriptor.genericContext(in: machO) else { continue }
//                try mangleAsString(ContextDescriptorWrapper.type(.enum(enumDescriptor)).dumpNameNode(in: machO)).print()
                try "\(ContextDescriptorWrapper.type(.enum(enumDescriptor)).dumpName(using: .default, in: machO).string)\(await genericContext.dumpGenericSignature(resolver: .using(options: .default), in: machO, isDumpCurrentLevelRequirements: false).string)".print()
            case .struct(let structDescriptor):
                guard let genericContext = try structDescriptor.genericContext(in: machO) else { continue }
//                try mangleAsString(ContextDescriptorWrapper.type(.struct(structDescriptor)).dumpNameNode(in: machO)).print()
                try "\(ContextDescriptorWrapper.type(.struct(structDescriptor)).dumpName(using: .default, in: machO).string)\(await genericContext.dumpGenericSignature(resolver: .using(options: .default), in: machO, isDumpCurrentLevelRequirements: false).string)".print()
            case .class(let classDescriptor):
                guard let genericContext = try classDescriptor.genericContext(in: machO) else { continue }
//                try mangleAsString(ContextDescriptorWrapper.type(.class(classDescriptor)).dumpNameNode(in: machO)).print()
                try "\(ContextDescriptorWrapper.type(.class(classDescriptor)).dumpName(using: .default, in: machO).string)\(await genericContext.dumpGenericSignature(resolver: .using(options: .default), in: machO, isDumpCurrentLevelRequirements: false).string)".print()
            }
        }
    }
}
