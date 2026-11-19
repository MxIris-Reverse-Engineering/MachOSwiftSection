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
