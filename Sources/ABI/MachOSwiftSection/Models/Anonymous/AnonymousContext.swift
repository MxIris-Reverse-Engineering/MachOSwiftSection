import Foundation
import MachOKit
import MachOBase

public struct AnonymousContext: TopLevelType, ContextProtocol {
    public let descriptor: AnonymousContextDescriptor
    public let genericContext: GenericContext?
    public let mangledName: MangledName?
}

// MARK: - ReadingContext Support

extension AnonymousContext {
    public init(descriptor: AnonymousContextDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor
        var currentOffset = descriptor.offset + descriptor.layoutSize

        let genericContext = try descriptor.genericContext(in: context)
        if let genericContext {
            currentOffset += genericContext.size
        }
        self.genericContext = genericContext

        if descriptor.hasMangledName {
            let mangledNamePointerAddress = try context.addressFromOffset(currentOffset)
            let mangledNamePointer: RelativeDirectPointer<MangledName> = try context.readElement(at: mangledNamePointerAddress)
            self.mangledName = try mangledNamePointer.resolve(at: mangledNamePointerAddress, in: context)
            currentOffset += MemoryLayout<RelativeDirectPointer<MangledName>>.size
        } else {
            self.mangledName = nil
        }
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension AnonymousContext {
    @available(*, deprecated, message: "Pass a ReadingContext: AnonymousContext(descriptor:in: machO.context).")
    public init(descriptor: AnonymousContextDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try self.init(descriptor: descriptor, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: AnonymousContext(descriptor:in: .inProcess).")
    public init(descriptor: AnonymousContextDescriptor) throws {
        try self.init(descriptor: descriptor, in: InProcessContext.shared)
    }
}
