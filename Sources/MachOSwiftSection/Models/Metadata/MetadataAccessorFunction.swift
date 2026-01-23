import Foundation
import MachOFoundation
import MachOKit
import MachOSwiftSectionC

public struct MetadataAccessorFunction: Resolvable, @unchecked Sendable {
    private let ptr: UnsafeRawPointer

    package init(ptr: UnsafeRawPointer) {
        self.ptr = ptr
    }

    public func callAsFunction(request: MetadataRequest) throws -> MetadataResponse {
        try perform(request: request, metadatas: [], witnessTables: [])
    }

    public func callAsFunction(request: MetadataRequest, metatypes: Any.Type..., witnessTables: ProtocolWitnessTable...) throws -> MetadataResponse {
        return try perform(request: request, metadatas: metatypes.map { autoBitCast($0) }, witnessTables: witnessTables.map { try $0.asPointer })
    }

    public func callAsFunction(request: MetadataRequest, metadatas: [Metadata], witnessTables: [ProtocolWitnessTable] = [], in machO: MachOImage) throws -> MetadataResponse {
        return try perform(request: request, metadatas: metadatas.map { $0.pointer(in: machO) }, witnessTables: witnessTables.map { $0.pointer(in: machO) })
    }

    public func callAsFunction<each Metadata: MetadataProtocol>(request: MetadataRequest, metadatas: repeat each Metadata, witnessTables: ProtocolWitnessTable..., in machO: MachOImage) throws -> MetadataResponse {
        var metadataPointers: [UnsafeRawPointer] = []

        for metadata in repeat each metadatas {
            metadataPointers.append(metadata.pointer(in: machO))
        }

        return try perform(request: request, metadatas: metadataPointers, witnessTables: witnessTables.map { $0.pointer(in: machO) })
    }

    public func callAsFunction(request: MetadataRequest, metadatas: [Metadata], witnessTables: [ProtocolWitnessTable] = []) throws -> MetadataResponse {
        return try perform(request: request, metadatas: metadatas.map { try $0.asPointer }, witnessTables: witnessTables.map { try $0.asPointer })
    }

    public func callAsFunction<each Metadata: MetadataProtocol>(request: MetadataRequest, metadatas: repeat each Metadata, witnessTables: ProtocolWitnessTable...) throws -> MetadataResponse {
        var metadataPointers: [UnsafeRawPointer] = []

        for metadata in repeat each metadatas {
            try metadataPointers.append(metadata.asPointer)
        }

        return try perform(request: request, metadatas: metadataPointers, witnessTables: witnessTables.map { try $0.asPointer })
    }

    private func perform(request: MetadataRequest, metadatas: [UnsafeRawPointer], witnessTables: [UnsafeRawPointer]) throws -> MetadataResponse {
        var response = MachOSwiftSectionC.MetadataResponse()

        let totalCount = metadatas.count + witnessTables.count

        func getArg(_ index: Int) -> UnsafeRawPointer {
            if index < metadatas.count {
                return metadatas[index]
            } else {
                return witnessTables[index - metadatas.count]
            }
        }

        switch totalCount {
        case 0:
            response = swift_section_callAccessor0(ptr, request.rawValue)
        case 1:
            response = swift_section_callAccessor1(ptr, request.rawValue, getArg(0))
        case 2:
            response = swift_section_callAccessor2(ptr, request.rawValue, getArg(0), getArg(1))
        case 3:
            response = swift_section_callAccessor3(ptr, request.rawValue, getArg(0), getArg(1), getArg(2))
        default:
            let buffer = createMetadataAccessBuffer(metadatas: metadatas, witnessTables: witnessTables)
            defer { buffer.deallocate() }
            response = swift_section_callAccessor(ptr, request.rawValue, buffer)
        }

        return unsafeBitCast(response, to: MetadataResponse.self)
    }
}

// MARK: - Buffer Helper

private func createMetadataAccessBuffer(
    metadatas: [UnsafeRawPointer],
    witnessTables: [UnsafeRawPointer]
) -> UnsafeMutableRawPointer {
    let ptrSize = MemoryLayout<UnsafeRawPointer>.size
    let totalCount = metadatas.count + witnessTables.count

    let buffer = UnsafeMutableRawPointer.allocate(
        byteCount: ptrSize * totalCount,
        alignment: MemoryLayout<UnsafeRawPointer>.alignment
    )

    // 1. Store Types (Metadata) at the beginning
    for (i, ptr) in metadatas.enumerated() {
        buffer.storeBytes(
            of: ptr,
            toByteOffset: ptrSize * i,
            as: UnsafeRawPointer.self
        )
    }

    // 2. Store Witness Tables immediately after Types
    // Offset starts from where types ended
    for (i, ptr) in witnessTables.enumerated() {
        let offset = ptrSize * (metadatas.count + i)
        buffer.storeBytes(
            of: ptr,
            toByteOffset: offset,
            as: UnsafeRawPointer.self
        )
    }

    return buffer
}
