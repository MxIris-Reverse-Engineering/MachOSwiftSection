import Foundation
import MachOKit

public protocol ValueMetadataProtocol: MetadataProtocol where Layout: ValueMetadataLayout {}

extension ValueMetadataProtocol {
    public func descriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ValueTypeDescriptorWrapper {
        try layout.descriptor.resolve(in: machO)
    }

    public func descriptor() throws -> ValueTypeDescriptorWrapper {
        try layout.descriptor.resolve()
    }
}
