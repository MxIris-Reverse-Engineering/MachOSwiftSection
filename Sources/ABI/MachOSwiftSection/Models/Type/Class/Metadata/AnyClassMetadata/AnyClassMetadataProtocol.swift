import Foundation
import MachOKit
import MachOBase

public protocol AnyClassMetadataProtocol: HeapMetadataProtocol where Layout: AnyClassMetadataLayout {}

// MARK: - ReadingContext Support

extension AnyClassMetadataProtocol {
    public func asFinalClassMetadata(in context: some ReadingContext) throws -> AnyClassMetadata {
        try .resolve(at: try context.addressFromOffset(offset), in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension AnyClassMetadataProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: asFinalClassMetadata(in: machO.context).")
    public func asFinalClassMetadata(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> AnyClassMetadata {
        try asFinalClassMetadata(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: asFinalClassMetadata(in: .inProcess).")
    public func asFinalClassMetadata() throws -> AnyClassMetadata {
        try asFinalClassMetadata(in: InProcessContext.shared)
    }
}
