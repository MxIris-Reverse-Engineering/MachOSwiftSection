import Foundation
import MachOKit
import MachOFoundation
import Demangling

public struct OpaqueType: TopLevelType, ContextProtocol {
    public let descriptor: OpaqueTypeDescriptor

    public let genericContext: GenericContext?

    public let underlyingTypeArgumentMangledNames: [MangledName]

    public let invertedProtocols: InvertibleProtocolSet?

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: OpaqueTypeDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor
        var currentOffset = descriptor.offset + descriptor.layoutSize

        let genericContext = try descriptor.genericContext(in: machO)

        if let genericContext {
            currentOffset += genericContext.size
        }
        self.genericContext = genericContext

        if descriptor.numUnderlyingTypeArugments > 0 {
            let underlyingTypeArgumentMangledNamePointers: [RelativeDirectPointer<MangledName>] = try machO.readElements(offset: currentOffset, numberOfElements: descriptor.numUnderlyingTypeArugments)
            var underlyingTypeArgumentMangledNames: [MangledName] = []
            for underlyingTypeArgumentMangledNamePointer in underlyingTypeArgumentMangledNamePointers {
                try underlyingTypeArgumentMangledNames.append(underlyingTypeArgumentMangledNamePointer.resolve(from: currentOffset, in: machO))
                currentOffset += MemoryLayout<RelativeDirectPointer<MangledName>>.size
            }
            self.underlyingTypeArgumentMangledNames = underlyingTypeArgumentMangledNames
        } else {
            self.underlyingTypeArgumentMangledNames = []
        }

        if descriptor.flags.contains(.hasInvertibleProtocols) {
            self.invertedProtocols = try machO.readElement(offset: currentOffset) as InvertibleProtocolSet
            currentOffset.offset(of: InvertibleProtocolSet.self)
        } else {
            self.invertedProtocols = nil
        }
    }

    public init(descriptor: OpaqueTypeDescriptor) throws {
        self.descriptor = descriptor

        var currentOffset = try descriptor.asPointer.advanced(by: descriptor.layoutSize)

        let genericContext = try descriptor.genericContext()

        if let genericContext {
            currentOffset += genericContext.size
        }
        self.genericContext = genericContext

        if descriptor.numUnderlyingTypeArugments > 0 {
            let underlyingTypeArgumentMangledNamePointers: [RelativeDirectPointer<MangledName>] = try currentOffset.readElements(numberOfElements: descriptor.numUnderlyingTypeArugments)
            var underlyingTypeArgumentMangledNames: [MangledName] = []
            for underlyingTypeArgumentMangledNamePointer in underlyingTypeArgumentMangledNamePointers {
                try underlyingTypeArgumentMangledNames.append(underlyingTypeArgumentMangledNamePointer.resolve(from: currentOffset))
                currentOffset += MemoryLayout<RelativeDirectPointer<MangledName>>.size
            }
            self.underlyingTypeArgumentMangledNames = underlyingTypeArgumentMangledNames
        } else {
            self.underlyingTypeArgumentMangledNames = []
        }

        if descriptor.flags.contains(.hasInvertibleProtocols) {
            self.invertedProtocols = try currentOffset.readElement() as InvertibleProtocolSet
            currentOffset.offset(of: InvertibleProtocolSet.self)
        } else {
            self.invertedProtocols = nil
        }
    }
}
