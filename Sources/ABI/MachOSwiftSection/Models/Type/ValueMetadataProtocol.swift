import Foundation
import MachOKit

public protocol ValueMetadataProtocol: MetadataProtocol where Layout: ValueMetadataLayout {}

// MARK: - ReadingContext Support

extension ValueMetadataProtocol {
    public func descriptor(in context: some ReadingContext) throws -> ValueTypeDescriptorWrapper {
        try layout.descriptor.resolve(in: context)
    }
}
