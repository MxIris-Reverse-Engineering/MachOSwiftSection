import MachOKit

public protocol ContextDescriptorProtocol: LocatableLayoutWrapper where Layout: ContextDescriptorLayout {}

extension ContextDescriptorProtocol {
    public func parent(in machOFile: MachOFile) throws -> ResolvableElement<ContextDescriptorWrapper>? {
        guard layout.flags.kind != .module else { return nil }
        return try layout.parent.resolve(from: offset + 4, in: machOFile).asOptional
    }

    public func genericContext(in machO: MachOFile) throws -> GenericContext? {
        return try .init(contextDescriptor: self, in: machO)
    }
}
