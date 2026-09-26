import Foundation
import MachOKit
import MachOBase

public protocol AnyClassMetadataProtocol: HeapMetadataProtocol where Layout: AnyClassMetadataLayout {}

extension AnyClassMetadataProtocol {
    public func asFinalClassMetadata(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> AnyClassMetadata {
        try .resolve(from: offset, in: machO)
    }

    public func asFinalClassMetadata() throws -> AnyClassMetadata {
        try .resolve(from: asPointer)
    }
}

// MARK: - ReadingContext Support

extension AnyClassMetadataProtocol {
    public func asFinalClassMetadata(in context: some ReadingContext) throws -> AnyClassMetadata {
        try .resolve(at: try context.addressFromOffset(offset), in: context)
    }
}
