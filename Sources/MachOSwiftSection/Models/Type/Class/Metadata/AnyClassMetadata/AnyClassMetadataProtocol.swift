import Foundation
import MachOKit
import MachOFoundation

public protocol AnyClassMetadataProtocol: HeapMetadataProtocol where Layout: AnyClassMetadataLayout {}

extension AnyClassMetadataProtocol {
    public func asFinalClassMetadata<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> AnyClassMetadata {
        try .resolve(from: offset, in: machO)
    }
    
    public func asFinalClassMetadata() throws -> AnyClassMetadata {
        try .resolve(from: asPointer)
    }
}
