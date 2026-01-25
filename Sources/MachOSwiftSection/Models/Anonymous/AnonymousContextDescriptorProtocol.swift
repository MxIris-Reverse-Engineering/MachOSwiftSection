import MachOKit
import MachOFoundation

public protocol AnonymousContextDescriptorProtocol: ContextDescriptorProtocol where Layout: AnonymousContextDescriptorLayout {}

extension AnonymousContextDescriptorProtocol {
    public func mangledName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName? {
        guard hasMangledName else {
            return nil
        }
        var currentOffset = offset + layoutSize
        if let genericContext = try genericContext(in: machO) {
            currentOffset += genericContext.size
        }
        let mangledNamePointer: RelativeDirectPointer<MangledName> = try machO.readElement(offset: currentOffset)
        return try mangledNamePointer.resolve(from: currentOffset, in: machO)
    }

    public func mangledName() throws -> MangledName? {
        guard hasMangledName else {
            return nil
        }
        var currentOffset = layoutSize
        if let genericContext = try genericContext() {
            currentOffset += genericContext.size
        }
        let pointer = try asPointer
        let mangledNamePointer: RelativeDirectPointer<MangledName> = try pointer.readElement(offset: currentOffset)
        return try mangledNamePointer.resolve(from: pointer.advanced(by: currentOffset))
    }
    
    public func mangledName<Context: ReadingContext>(in context: Context) throws -> MangledName? {
        guard hasMangledName else {
            return nil
        }
        var currentOffset = offset + layoutSize
        if let genericContext = try genericContext(in: context) {
            currentOffset += genericContext.size
        }
        let mangledNamePointerAddress = try context.addressFromOffset(currentOffset)
        let mangledNamePointer: RelativeDirectPointer<MangledName> = try context.readElement(at: mangledNamePointerAddress)
        return try mangledNamePointer.resolve(at: mangledNamePointerAddress, in: context)
    }
    
    public var hasMangledName: Bool {
        guard let kindSpecificFlags = layout.flags.kindSpecificFlags, case .anonymous(let anonymousContextDescriptorFlags) = kindSpecificFlags else {
            return false
        }
        return anonymousContextDescriptorFlags.hasMangledName
    }
}
