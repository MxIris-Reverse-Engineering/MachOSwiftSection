import MachOKit
import MachOFoundation
import MachOMacro

public protocol ContextDescriptorProtocol: ResolvableLocatableLayoutWrapper where Layout: ContextDescriptorLayout {
    func genericContext<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> GenericContext?
    func parent<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> SymbolOrElement<ContextDescriptorWrapper>?
}


extension ContextDescriptorProtocol {
    public func parent<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        guard layout.flags.kind != .module else { return nil }
        return try layout.parent.resolve(from: offset + layout.offset(of: .parent), in: machO).asOptional
    }

    public func genericContext<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try GenericContext(contextDescriptor: self, in: machO)
    }
}
