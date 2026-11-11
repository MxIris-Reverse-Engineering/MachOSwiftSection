import MachOKit
import MachOBase

public protocol AnonymousContextDescriptorProtocol: ContextDescriptorProtocol where Layout: AnonymousContextDescriptorLayout {}

extension AnonymousContextDescriptorProtocol {
    public func mangledName(in context: some ReadingContext) throws -> MangledName? {
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
