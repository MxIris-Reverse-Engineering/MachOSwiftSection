import MachOKit
import MachOFoundation

import Demangle

@dynamicMemberLookup
public protocol ContextDescriptorProtocol: ResolvableLocatableLayoutWrapper where Layout: ContextDescriptorLayout {
    func genericContext<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> GenericContext?
    func parent<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SymbolOrElement<ContextDescriptorWrapper>?
    func moduleContextDesciptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> (any ModuleContextDescriptorProtocol)?
    func isCImportedContextDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Bool
}


extension ContextDescriptorProtocol {
    public func parent<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        guard layout.flags.kind != .module, layout.parent.isValid else { return nil }
        return try layout.parent.resolve(from: offset + layout.offset(of: .parent), in: machO).asOptional
    }

    public func genericContext<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try GenericContext(contextDescriptor: self, in: machO)
    }
    
    public func moduleContextDesciptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> (any ModuleContextDescriptorProtocol)? {
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
    
    public func isCImportedContextDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Bool {
        guard let moduleContextDescriptor = try moduleContextDesciptor(in: machO) else { return false }
        let moduleName = try moduleContextDescriptor.name(in: machO)
        return moduleName == cModule || moduleName == objcModule
    }
}
