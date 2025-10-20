import Foundation
import MachOFoundation
import MachOKit

public struct MetadataAccessor: Resolvable, @unchecked Sendable {
    private var raw: UnsafeRawPointer
    
    package init(raw: UnsafeRawPointer) {
        self.raw = raw
    }
    
    public func perform(request: MetadataRequest) -> MetadataResponse {
        unsafeBitCast(raw, to: (@convention(thin) (Int) -> MetadataResponse).self)(request.rawValue)
    }
    
    public func perform(request: MetadataRequest, arg1: Metadata, in machO: MachOImage) -> MetadataResponse {
        unsafeBitCast(raw, to: (@convention(thin) (Int, UnsafeRawPointer) -> MetadataResponse).self)(request.rawValue, arg1.pointer(in: machO))
    }
    
    public func perform(request: MetadataRequest, arg1: Metadata, arg2: Metadata, in machO: MachOImage) -> MetadataResponse {
        unsafeBitCast(raw, to: (@convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> MetadataResponse).self)(request.rawValue, arg1.pointer(in: machO), arg2.pointer(in: machO))
    }
    
    public func perform(request: MetadataRequest, arg1: Metadata, arg2: Metadata, arg3: Metadata, in machO: MachOImage) -> MetadataResponse {
        unsafeBitCast(raw, to: (@convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer, UnsafeRawPointer) -> MetadataResponse).self)(request.rawValue, arg1.pointer(in: machO), arg2.pointer(in: machO), arg3.pointer(in: machO))
    }
}
