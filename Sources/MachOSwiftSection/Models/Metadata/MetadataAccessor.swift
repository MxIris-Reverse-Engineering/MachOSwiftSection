import Foundation
import MachOFoundation
import MachOKit

public struct MetadataAccessor: Resolvable, @unchecked Sendable {
    private var raw: UnsafeRawPointer

    package init(raw: UnsafeRawPointer) {
        self.raw = raw
    }

    public func perform(request: MetadataRequest) -> MetadataResponse {
        return perform0(request: request)
    }

    public func perform<each Metadata: MetadataProtocol>(request: MetadataRequest, args: repeat each Metadata, in machO: MachOImage) -> MetadataResponse {
        var pointers: [UnsafeRawPointer] = []
        
        for arg in repeat each args {
            pointers.append(arg.pointer(in: machO))
        }
        
        switch pointers.count {
        case 0:
            return perform0(request: request)
        case 1:
            return perform1(request: request, arg0: pointers[0])
        case 2:
            return perform2(request: request, arg0: pointers[0], arg1: pointers[1])
        case 3:
            return perform3(request: request, arg0: pointers[0], arg1: pointers[1], arg2: pointers[2])
        default:
            return applyMany(request: request, args: pointers)
        }
    }

    public func perform(request: MetadataRequest, args: Any.Type...) -> MetadataResponse {
        let pointers = args.map { unsafeBitCast($0, to: UnsafeRawPointer.self) }

        switch pointers.count {
        case 0:
            return perform0(request: request)
        case 1:
            return perform1(request: request, arg0: pointers[0])
        case 2:
            return perform2(request: request, arg0: pointers[0], arg1: pointers[1])
        case 3:
            return perform3(request: request, arg0: pointers[0], arg1: pointers[1], arg2: pointers[2])
        default:
            return applyMany(request: request, args: pointers)
        }
    }

    private func perform0(request: MetadataRequest) -> MetadataResponse {
        #if _ptrauth(_arm64e)
        typealias Fn = @convention(c) (Int) -> UnsafeRawPointer
        #if USING_SWIFT_BUILTIN_MODULE
        let signedPtr = _PtrAuth.sign(pointer: raw, key: .processIndependentCode, discriminator: _PtrAuth.discriminator(for: Fn.self))
        #else
        let signedPtr = PtrAuth.sign(pointer: raw, key: .processIndependentCode, discriminator: 0)
        #endif
        let function = unsafeBitCast(signedPtr, to: Fn.self)
        return MetadataResponse(value: .init(address: function(request.rawValue).uint.uint64))
        #else
        typealias Fn = @convention(thin) (Int) -> MetadataResponse
        let function = unsafeBitCast(raw, to: Fn.self)
        return function(request.rawValue)
        #endif
    }

    private func perform1(request: MetadataRequest, arg0: UnsafeRawPointer) -> MetadataResponse {
        typealias Fn = @convention(thin) (Int, UnsafeRawPointer) -> MetadataResponse
        let function = unsafeBitCast(raw, to: Fn.self)
        return function(request.rawValue, arg0)
    }

    private func perform2(request: MetadataRequest, arg0: UnsafeRawPointer, arg1: UnsafeRawPointer) -> MetadataResponse {
        typealias Fn = @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> MetadataResponse
        let function = unsafeBitCast(raw, to: Fn.self)
        return function(request.rawValue, arg0, arg1)
    }

    private func perform3(request: MetadataRequest, arg0: UnsafeRawPointer, arg1: UnsafeRawPointer, arg2: UnsafeRawPointer) -> MetadataResponse {
        typealias Fn = @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer, UnsafeRawPointer) -> MetadataResponse
        let function = unsafeBitCast(raw, to: Fn.self)
        return function(request.rawValue, arg0, arg1, arg2)
    }

    private func applyMany(request: MetadataRequest, args: [UnsafeRawPointer]) -> MetadataResponse {
        typealias Fn = @convention(thin) (Int, UnsafePointer<UnsafeRawPointer>) -> MetadataResponse
        let function = unsafeBitCast(raw, to: Fn.self)

        return args.withUnsafeBufferPointer { buffer in
            return function(request.rawValue, buffer.baseAddress!)
        }
    }
}
