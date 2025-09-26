import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

public struct AnonymousContext: TopLevelType, ContextProtocol {
    public let descriptor: AnonymousContextDescriptor
    public let genericContext: GenericContext?
    public let mangledName: MangledName?

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: AnonymousContextDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor
        var currentOffset = descriptor.offset + descriptor.layoutSize

        let genericContext = try descriptor.genericContext(in: machO)

        if let genericContext {
            currentOffset += genericContext.size
        }
        self.genericContext = genericContext

        if descriptor.hasMangledName {
            let mangledNamePointer: RelativeDirectPointer<MangledName> = try machO.readElement(offset: currentOffset)
            self.mangledName = try mangledNamePointer.resolve(from: currentOffset, in: machO)
            currentOffset += MemoryLayout<RelativeDirectPointer<MangledName>>.size
        } else {
            self.mangledName = nil
        }
    }
}
