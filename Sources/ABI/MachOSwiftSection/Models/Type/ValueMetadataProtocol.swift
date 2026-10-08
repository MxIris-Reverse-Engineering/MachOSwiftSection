import Foundation
import MachOKit

public protocol ValueMetadataProtocol: MetadataProtocol where Layout: ValueMetadataLayout {}

// MARK: - ReadingContext Support

extension ValueMetadataProtocol {
    public func descriptor(in context: some ReadingContext) throws -> ValueTypeDescriptorWrapper {
        try layout.descriptor.resolve(in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension ValueMetadataProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: descriptor(in: machO.context).")
    public func descriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ValueTypeDescriptorWrapper {
        try descriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: descriptor(in: .inProcess).")
    public func descriptor() throws -> ValueTypeDescriptorWrapper {
        try descriptor(in: InProcessContext.shared)
    }
}
