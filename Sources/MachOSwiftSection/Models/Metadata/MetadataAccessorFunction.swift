import Foundation
import MachOFoundation
import MachOKit
import MachOSwiftSectionC

public struct MetadataAccessorFunction: Resolvable, @unchecked Sendable {
    private let ptr: UnsafeRawPointer

    package init(ptr: UnsafeRawPointer) {
        self.ptr = ptr
    }

    public func callAsFunction(request: MetadataRequest) -> MetadataResponse {
        perform(request: request, args: [] as [UnsafeRawPointer])
    }

    public func callAsFunction(request: MetadataRequest, args: Any.Type...) -> MetadataResponse {
        callAsFunction(request: request, args: args)
    }

    public func callAsFunction(request: MetadataRequest, args: [Any.Type]) -> MetadataResponse {
        perform(request: request, args: args.map { unsafeBitCast($0, to: UnsafeRawPointer.self) })
    }

    public func callAsFunction(request: MetadataRequest, args: (metatype: Any.Type, witnessTable: [ProtocolWitnessTable]?)...) throws -> MetadataResponse {
        try callAsFunction(request: request, args: args)
    }

    public func callAsFunction(request: MetadataRequest, args: [(metatype: Any.Type, witnessTable: [ProtocolWitnessTable]?)]) throws -> MetadataResponse {
        try perform(request: request, args: args.map { try (unsafeBitCast($0.metatype, to: UnsafeRawPointer.self), $0.witnessTable?.map { try $0.asPointer }) })
    }

    public func callAsFunction<each Metadata: MetadataProtocol>(request: MetadataRequest, args: repeat each Metadata, in machO: MachOImage) throws -> MetadataResponse {
        var pointers: [UnsafeRawPointer] = []

        for arg in repeat each args {
            pointers.append(arg.pointer(in: machO))
        }

        return perform(request: request, args: pointers)
    }

    public func callAsFunction<each Metadata: MetadataProtocol>(request: MetadataRequest, args: repeat (metadata: each Metadata, witnessTables: [ProtocolWitnessTable]?), in machO: MachOImage) throws -> MetadataResponse {
        var pointers: [(UnsafeRawPointer, [UnsafeRawPointer]?)] = []

        for (metadata, witnessTable) in repeat each args {
            pointers.append((metadata.pointer(in: machO), witnessTable?.map { $0.pointer(in: machO) }))
        }

        return try perform(request: request, args: pointers)
    }

    public func callAsFunction<each Metadata: MetadataProtocol>(request: MetadataRequest, args: repeat each Metadata) throws -> MetadataResponse {
        var pointers: [UnsafeRawPointer] = []

        for arg in repeat each args {
            try pointers.append(arg.asPointer)
        }

        return perform(request: request, args: pointers)
    }

    public func callAsFunction<each Metadata: MetadataProtocol>(request: MetadataRequest, args: repeat (metadata: each Metadata, witnessTables: [ProtocolWitnessTable]?)) throws -> MetadataResponse {
        var pointers: [(UnsafeRawPointer, [UnsafeRawPointer]?)] = []

        for (metadata, witnessTable) in repeat each args {
            try pointers.append((metadata.asPointer, witnessTable?.map { try $0.asPointer }))
        }

        return try perform(request: request, args: pointers)
    }

    public func callAsFunction<Metadata: MetadataProtocol>(request: MetadataRequest, args: [Metadata]) throws -> MetadataResponse {
        var pointers: [UnsafeRawPointer] = []

        for arg in args {
            try pointers.append(arg.asPointer)
        }

        return perform(request: request, args: pointers)
    }

    public func callAsFunction<Metadata: MetadataProtocol>(request: MetadataRequest, args: [(metadata: Metadata, witnessTables: [ProtocolWitnessTable]?)]) throws -> MetadataResponse {
        var pointers: [(UnsafeRawPointer, [UnsafeRawPointer]?)] = []

        for (metadata, witnessTable) in args {
            try pointers.append((metadata.asPointer, witnessTable?.map { try $0.asPointer }))
        }

        return try perform(request: request, args: pointers)
    }

    private func perform(request: MetadataRequest, args: [UnsafeRawPointer]) -> MetadataResponse {
        var response = MachOSwiftSectionC.MetadataResponse()

        switch args.count {
        case 0:
            response = swift_section_callAccessor0(ptr, request.rawValue)
        case 1:
            let arg0 = args[0]
            response = swift_section_callAccessor1(ptr, request.rawValue, arg0)
        case 2:
            let arg0 = args[0]
            let arg1 = args[1]
            response = swift_section_callAccessor2(ptr, request.rawValue, arg0, arg1)
        case 3:
            let arg0 = args[0]
            let arg1 = args[1]
            let arg2 = args[2]
            response = swift_section_callAccessor3(ptr, request.rawValue, arg0, arg1, arg2)
        default:
            args.withUnsafeBytes {
                response = swift_section_callAccessor(ptr, request.rawValue, $0.baseAddress!)
            }
        }

        return unsafeBitCast(response, to: MetadataResponse.self)
    }

    private func perform(request: MetadataRequest, args: [(metadata: UnsafeRawPointer, witnessTables: [UnsafeRawPointer]?)]) throws -> MetadataResponse {
        var response = MachOSwiftSectionC.MetadataResponse()

        let totalWitnessCount = args.reduce(0) { $0 + ($1.witnessTables?.count ?? 0) }

        switch args.count {
        case 0:
            response = swift_section_callAccessor0(ptr, request.rawValue)

        case 1:
            let arg0 = args[0].metadata
            let wts = args[0].witnessTables ?? []

            switch wts.count {
            case 0:
                response = swift_section_callAccessor1(ptr, request.rawValue, arg0)
            case 1:
                response = swift_section_callAccessor2(ptr, request.rawValue, arg0, wts[0])
            case 2:
                response = swift_section_callAccessor3(ptr, request.rawValue, arg0, wts[0], wts[1])
            default:
                let buffer = try createMetadataAccessBuffer(for: args)
                defer { buffer.deallocate() }
                response = swift_section_callAccessor(ptr, request.rawValue, buffer)
            }

        case 2:
            let arg0 = args[0].metadata
            let arg1 = args[1].metadata

            if totalWitnessCount == 0 {
                response = swift_section_callAccessor2(ptr, request.rawValue, arg0, arg1)
            } else if totalWitnessCount == 1 {
                let wt = (args[0].witnessTables?.first) ?? (args[1].witnessTables?.first)!
                response = swift_section_callAccessor3(ptr, request.rawValue, arg0, arg1, wt)
            } else {
                let buffer = try createMetadataAccessBuffer(for: args)
                defer { buffer.deallocate() }
                response = swift_section_callAccessor(ptr, request.rawValue, buffer)
            }

        case 3:
            let arg0 = args[0].metadata
            let arg1 = args[1].metadata
            let arg2 = args[2].metadata

            if totalWitnessCount == 0 {
                response = swift_section_callAccessor3(ptr, request.rawValue, arg0, arg1, arg2)
            } else {
                let buffer = try createMetadataAccessBuffer(for: args)
                defer { buffer.deallocate() }
                response = swift_section_callAccessor(ptr, request.rawValue, buffer)
            }

        default:
            let buffer = try createMetadataAccessBuffer(for: args)
            defer { buffer.deallocate() }
            response = swift_section_callAccessor(ptr, request.rawValue, buffer)
        }

        return unsafeBitCast(response, to: MetadataResponse.self)
    }
}

private func createMetadataAccessBuffer(
    for args: [(metadata: UnsafeRawPointer, witnessTables: [UnsafeRawPointer]?)]
) throws -> UnsafeMutableRawPointer {
    let ptrSize = MemoryLayout<UnsafeRawPointer>.size

    let metadataCount = args.count
    let witnessCount = args.reduce(0) { $0 + ($1.witnessTables?.count ?? 0) }
    let totalCount = metadataCount + witnessCount

    let buffer = UnsafeMutableRawPointer.allocate(
        byteCount: ptrSize * totalCount,
        alignment: MemoryLayout<UnsafeRawPointer>.alignment
    )

    for i in 0 ..< args.count {
        buffer.storeBytes(
            of: args[i].metadata,
            toByteOffset: ptrSize * i,
            as: UnsafeRawPointer.self
        )
    }

    var currentByteOffset = ptrSize * args.count

    for arg in args {
        if let tables = arg.witnessTables {
            for tablePtr in tables {
                buffer.storeBytes(
                    of: tablePtr,
                    toByteOffset: currentByteOffset,
                    as: UnsafeRawPointer.self
                )
                currentByteOffset += ptrSize
            }
        }
    }

    return buffer
}
