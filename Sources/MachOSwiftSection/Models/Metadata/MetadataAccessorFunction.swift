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

    public func callAsFunction(request: MetadataRequest, args: (metatype: Any.Type, witnessTable: ProtocolWitnessTable?)...) throws -> MetadataResponse {
        try callAsFunction(request: request, args: args)
    }

    public func callAsFunction(request: MetadataRequest, args: [(metatype: Any.Type, witnessTable: ProtocolWitnessTable?)]) throws -> MetadataResponse {
        try perform(request: request, args: args.map { try (unsafeBitCast($0.metatype, to: UnsafeRawPointer.self), $0.witnessTable?.asPointer) })
    }

    public func callAsFunction<each Metadata: MetadataProtocol>(request: MetadataRequest, args: repeat each Metadata, in machO: MachOImage) -> MetadataResponse {
        var pointers: [UnsafeRawPointer] = []

        for arg in repeat each args {
            pointers.append(arg.pointer(in: machO))
        }

        return perform(request: request, args: pointers)
    }

    public func callAsFunction<each Metadata: MetadataProtocol>(request: MetadataRequest, args: repeat (each Metadata, ProtocolWitnessTable?), in machO: MachOImage) throws -> MetadataResponse {
        var pointers: [(UnsafeRawPointer, UnsafeRawPointer?)] = []

        for (metadata, witnessTable) in repeat each args {
            pointers.append((metadata.pointer(in: machO), witnessTable?.pointer(in: machO)))
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

    private func perform(request: MetadataRequest, args: [(metadata: UnsafeRawPointer, witnessTable: UnsafeRawPointer?)]) throws -> MetadataResponse {
        var response = MachOSwiftSectionC.MetadataResponse()

        switch args.count {
        case 0:
            // Easy case: No key arguments and no witness tables.
            response = swift_section_callAccessor0(ptr, request.rawValue)

        case 1:
            // If we don't have a witness table, then it's just the key parameter
            // argument.
            guard let witnessTable = args[0].witnessTable else {
                let arg0 = args[0].metadata
                response = swift_section_callAccessor1(ptr, request.rawValue, arg0)
                break
            }

            // Otherwise we have arg0 being the key argument and arg1 being the
            // witness table.
            let arg0 = args[0].metadata
            let arg1 = witnessTable
            response = swift_section_callAccessor2(ptr, request.rawValue, arg0, arg1)

        case 2:
            switch (args[0].witnessTable, args[1].witnessTable) {
            // In this case there were no witness tables passed, so it's a simple
            // 2 key argument call.
            case (nil, nil):
                let arg0 = args[0].metadata
                let arg1 = args[1].metadata
                response = swift_section_callAccessor2(ptr, request.rawValue, arg0, arg1)

            // In this case, only the first key argument has a witness table, so this
            // is a 3 argument call where the witness table is the last parameter.
            case (let witnessTable0?, nil):
                let arg0 = args[0].metadata
                let arg1 = args[1].metadata
                let arg2 = witnessTable0
                response = swift_section_callAccessor3(ptr, request.rawValue, arg0, arg1, arg2)

            // In this case, only the second key argument has a witness table, so this
            // is a 3 argument call where the witness table is the last parameter.
            case (nil, let witnessTable1?):
                let arg0 = args[0].metadata
                let arg1 = args[1].metadata
                let arg2 = witnessTable1
                response = swift_section_callAccessor3(ptr, request.rawValue, arg0, arg1, arg2)

            // Finally, we have the case where both of our key arguments have witness
            // tables associated with them. This is a 4 argument call, thus requiring
            // an array pointer pointing to the key arguments followed by the witness
            // tables.
            case (_?, _?):
                let buffer = try createMetadataAccessBuffer(for: args)

                defer {
                    buffer.deallocate()
                }

                response = swift_section_callAccessor(ptr, request.rawValue, buffer)
            }

        case 3:
            switch (args[0].witnessTable, args[1].witnessTable, args[2].witnessTable) {
            // Simple case where we don't have any witness tables which just uses
            // the 3 argument accessor.
            case (nil, nil, nil):
                let arg0 = args[0].metadata
                let arg1 = args[1].metadata
                let arg2 = args[2].metadata
                response = swift_section_callAccessor3(ptr, request.rawValue, arg0, arg1, arg2)

            // Any other witness table requires us to use the buffer accessor.
            default:
                let buffer = try createMetadataAccessBuffer(for: args)

                defer {
                    buffer.deallocate()
                }

                response = swift_section_callAccessor(ptr, request.rawValue, buffer)
            }

        // Anything more than 4 args requires us to create a buffer even if there
        // are no witness tables (those should use the other callAsFunction...).
        default:
            let buffer = try createMetadataAccessBuffer(for: args)

            defer {
                buffer.deallocate()
            }

            response = swift_section_callAccessor(ptr, request.rawValue, buffer)
        }

        return unsafeBitCast(response, to: MetadataResponse.self)
    }
}

// NOTE: It is up to the caller to deallocate the returned pointer here.
private func createMetadataAccessBuffer(
    for args: [(metadata: UnsafeRawPointer, witnessTable: UnsafeRawPointer?)]
) throws -> UnsafeMutableRawPointer {
    // Allocate at LEAST enough space to hold arg.count key arguments * 2 (one
    // for the key argument and one for the witness table). It is understood that
    // not all witness tables are required.
    let ptrSize = MemoryLayout<UnsafeRawPointer>.size
    let buffer = UnsafeMutableRawPointer.allocate(
        byteCount: ptrSize * args.count * 2,
        alignment: MemoryLayout<UnsafeRawPointer>.alignment
    )

    // First loop is inserting the key arguments at the front of the buffer.
    for i in 0 ..< args.count {
        buffer.storeBytes(
            of: args[0].metadata,
            toByteOffset: ptrSize * i,
            as: UnsafeRawPointer.self
        )
    }

    // Second loop is for appending the witness tables behind the key arguments.
    var nextLoc = 0
    for i in 0 ..< args.count {
        if args[i].witnessTable != nil {
            let offset = ptrSize * args.count
            let addr = ptrSize * nextLoc + offset
            buffer.storeBytes(
                of: args[i].witnessTable!,
                toByteOffset: addr,
                as: UnsafeRawPointer.self
            )

            nextLoc += 1
        }
    }

    return buffer
}
