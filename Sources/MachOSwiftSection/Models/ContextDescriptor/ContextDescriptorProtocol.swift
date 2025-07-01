import MachOKit
import MachOFoundation
import MachOMacro

public protocol ContextDescriptorProtocol: ResolvableLocatableLayoutWrapper where Layout: ContextDescriptorLayout {
    func genericContext(in machO: MachOFile) throws -> GenericContext?
    func parent(in machO: MachOFile) throws -> SymbolOrElement<ContextDescriptorWrapper>?
    
    func genericContext(in machO: MachOImage) throws -> GenericContext?
    func parent(in machO: MachOImage) throws -> SymbolOrElement<ContextDescriptorWrapper>?
}

@MachOImageAllMembersGenerator
extension ContextDescriptorProtocol {
    public func parent(in machOFile: MachOFile) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        guard layout.flags.kind != .module else { return nil }
        return try layout.parent.resolve(from: offset + layout.offset(of: .parent), in: machOFile).asOptional
    }

    public func genericContext(in machOFile: MachOFile) throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try GenericContext(contextDescriptor: self, in: machOFile)
    }
}
