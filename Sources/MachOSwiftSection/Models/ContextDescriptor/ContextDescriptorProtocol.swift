import MachOKit
import MachOFoundation
import MachOMacro

@dynamicMemberLookup
public protocol ContextDescriptorProtocol: ResolvableLocatableLayoutWrapper where Layout: ContextDescriptorLayout {
    func genericContext<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> GenericContext?
    func parent<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> SymbolOrElement<ContextDescriptorWrapper>?
    func moduleContextDesciptor<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> (any ModuleContextDescriptorProtocol)?
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
    
    public func moduleContextDesciptor<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> (any ModuleContextDescriptorProtocol)? {
        if let module = self as? (any ModuleContextDescriptorProtocol) {
            return module
        } else {
            var parent: SymbolOrElement<ContextDescriptorWrapper>? = try parent(in: machO)
            while let currentParent = parent {
                if let module = currentParent.resolved?.contextDescriptor as? (any ModuleContextDescriptorProtocol) {
                    return module
                }
                parent = try currentParent.resolved?.parent(in: machO)
            }
            return nil
        }
    }
    
    public subscript<Value>(dynamicMember keyPath: KeyPath<Layout, Value>) -> Value {
        get {
            return layout[keyPath: keyPath]
        }
    }
}
