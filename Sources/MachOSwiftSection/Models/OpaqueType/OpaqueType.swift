import Foundation
import MachOKit

public struct OpaqueType {
    public let descriptor: OpaqueTypeDescriptor

    public let genericContext: GenericContext?
    
    public let underlyingTypeArgumentMangledNames: [MangledName]

    public let invertedProtocols: InvertibleProtocolSet?

    public init(descriptor: OpaqueTypeDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor
        var currentOffset = descriptor.offset + descriptor.layoutSize
        
        let genericContext = try descriptor.genericContext(in: machOFile)
        
        if let genericContext {
            currentOffset += genericContext.size
        }
        self.genericContext = genericContext
        
        if descriptor.numUnderlyingTypeArugments > 0 {
            let underlyingTypeArgumentMangledNamePointers: [RelativeDirectPointer<MangledName>] = try machOFile.readElements(offset: currentOffset, numberOfElements: descriptor.numUnderlyingTypeArugments)
            var underlyingTypeArgumentMangledNames: [MangledName] = []
            for underlyingTypeArgumentMangledNamePointer in underlyingTypeArgumentMangledNamePointers {
                try underlyingTypeArgumentMangledNames.append(underlyingTypeArgumentMangledNamePointer.resolve(from: currentOffset, in: machOFile))
                currentOffset += MemoryLayout<RelativeDirectPointer<MangledName>>.size
            }
            self.underlyingTypeArgumentMangledNames = underlyingTypeArgumentMangledNames
        } else {
            self.underlyingTypeArgumentMangledNames = []
        }

        if descriptor.flags.contains(.hasInvertibleProtocols) {
            self.invertedProtocols = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: InvertibleProtocolSet.self)
        } else {
            self.invertedProtocols = nil
        }
    }
}
