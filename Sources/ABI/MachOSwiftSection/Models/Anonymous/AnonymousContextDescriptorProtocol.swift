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

// MARK: - Deprecated Mach-O and pointer forms

extension AnonymousContextDescriptorProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: mangledName(in: machO.context).")
    public func mangledName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName? {
        try mangledName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: mangledName(in: .inProcess).")
    public func mangledName() throws -> MangledName? {
        try mangledName(in: InProcessContext.shared)
    }
}
