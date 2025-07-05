import MachOKit
import MachOFoundation
import MachOMacro

public protocol AnonymousContextDescriptorProtocol: ContextDescriptorProtocol where Layout: AnonymousContextDescriptorLayout {}


extension AnonymousContextDescriptorProtocol {
    public func mangledName<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> MangledName? {
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
    
    public var hasMangledName: Bool {
        guard let kindSpecificFlags = layout.flags.kindSpecificFlags, case .anonymous(let anonymousContextDescriptorFlags) = kindSpecificFlags else {
            return false
        }
        return anonymousContextDescriptorFlags.hasMangledName
    }
}
