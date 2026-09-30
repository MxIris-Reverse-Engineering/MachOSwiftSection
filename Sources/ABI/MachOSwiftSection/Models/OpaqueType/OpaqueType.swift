import Foundation
import MachOKit
import MachOBase

public struct OpaqueType: TopLevelType, ContextProtocol {
    public let descriptor: OpaqueTypeDescriptor

    public let genericContext: GenericContext?

    public let underlyingTypeArgumentMangledNames: [MangledName]

    public let invertedProtocols: InvertibleProtocolSet?
}

// MARK: - ReadingContext Support

extension OpaqueType {
    public init(descriptor: OpaqueTypeDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor
        var currentOffset = descriptor.offset + descriptor.layoutSize

        let genericContext = try descriptor.genericContext(in: context)

        if let genericContext {
            currentOffset += genericContext.size
        }
        self.genericContext = genericContext

        if descriptor.numUnderlyingTypeArguments > 0 {
            let underlyingTypeArgumentMangledNamePointers: [RelativeDirectPointer<MangledName>] = try context.readElements(at: try context.addressFromOffset(currentOffset), numberOfElements: descriptor.numUnderlyingTypeArguments)
            var underlyingTypeArgumentMangledNames: [MangledName] = []
            for underlyingTypeArgumentMangledNamePointer in underlyingTypeArgumentMangledNamePointers {
                try underlyingTypeArgumentMangledNames.append(underlyingTypeArgumentMangledNamePointer.resolve(at: try context.addressFromOffset(currentOffset), in: context))
                currentOffset += MemoryLayout<RelativeDirectPointer<MangledName>>.size
            }
            self.underlyingTypeArgumentMangledNames = underlyingTypeArgumentMangledNames
        } else {
            self.underlyingTypeArgumentMangledNames = []
        }

        if descriptor.flags.contains(.hasInvertibleProtocols) {
            self.invertedProtocols = try context.readElement(at: try context.addressFromOffset(currentOffset)) as InvertibleProtocolSet
            currentOffset.offset(of: InvertibleProtocolSet.self)
        } else {
            self.invertedProtocols = nil
        }
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension OpaqueType {
    @available(*, deprecated, message: "Pass a ReadingContext: OpaqueType(descriptor:in: machO.context).")
    public init(descriptor: OpaqueTypeDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try self.init(descriptor: descriptor, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: OpaqueType(descriptor:in: .inProcess).")
    public init(descriptor: OpaqueTypeDescriptor) throws {
        try self.init(descriptor: descriptor, in: InProcessContext.shared)
    }
}
