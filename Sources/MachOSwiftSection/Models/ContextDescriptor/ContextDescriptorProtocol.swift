import MachOKit
import MachOBase

@dynamicMemberLookup
public protocol ContextDescriptorProtocol: ResolvableLocatableLayoutWrapper where Layout: ContextDescriptorLayout {
    func genericContext(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> GenericContext?
    func parent(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<ContextDescriptorWrapper>?
    func moduleContextDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> (any ModuleContextDescriptorProtocol)?
    func isCImportedContextDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Bool

    func genericContext() throws -> GenericContext?
    func parent() throws -> SymbolOrElement<ContextDescriptorWrapper>?
    func moduleContextDescriptor() throws -> (any ModuleContextDescriptorProtocol)?
    func isCImportedContextDescriptor() throws -> Bool

    func genericContext(in context: some ReadingContext) throws -> GenericContext?
    func parent(in context: some ReadingContext) throws -> SymbolOrElement<ContextDescriptorWrapper>?
    func moduleContextDescriptor(in context: some ReadingContext) throws -> (any ModuleContextDescriptorProtocol)?
    func isCImportedContextDescriptor(in context: some ReadingContext) throws -> Bool

    subscript<T>(dynamicMember keyPath: KeyPath<ContextDescriptorFlags, T>) -> T { get }
}

extension ContextDescriptorProtocol {
    
    public subscript<T>(dynamicMember keyPath: KeyPath<ContextDescriptorFlags, T>) -> T {
        layout.flags[keyPath: keyPath]
    }
    
    public func parent(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        guard layout.flags.kind != .module, layout.parent.isValid else { return nil }
        return try layout.parent.resolve(from: offset + layout.offset(of: .parent), in: machO).asOptional
    }

    public func genericContext(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try GenericContext(contextDescriptor: self, in: machO)
    }

    public func moduleContextDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> (any ModuleContextDescriptorProtocol)? {
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

    public func isCImportedContextDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Bool {
        guard let moduleContextDescriptor = try moduleContextDescriptor(in: machO) else { return false }
        let moduleName = try moduleContextDescriptor.name(in: machO)
        return moduleName == CImportedModuleNames.cSynthesized || moduleName == CImportedModuleNames.objectiveC
    }
}

extension ContextDescriptorProtocol {
    public func parent() throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        guard layout.flags.kind != .module, layout.parent.isValid else { return nil }
        return try layout.parent.resolve(from: layout.pointer(from: asPointer, of: .parent)).asOptional
    }

    public func genericContext() throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try GenericContext(contextDescriptor: self)
    }

    public func moduleContextDescriptor() throws -> (any ModuleContextDescriptorProtocol)? {
        if let module = self as? (any ModuleContextDescriptorProtocol) {
            return module
        } else {
            var parent: SymbolOrElement<ContextDescriptorWrapper>? = try parent()
            while let currentParent = parent {
                if let module = currentParent.resolved?.contextDescriptor as? (any ModuleContextDescriptorProtocol) {
                    return module
                }
                parent = try currentParent.resolved?.parent()
            }
            return nil
        }
    }

    public func isCImportedContextDescriptor() throws -> Bool {
        guard let moduleContextDescriptor = try moduleContextDescriptor() else { return false }
        let moduleName = try moduleContextDescriptor.name()
        return moduleName == CImportedModuleNames.cSynthesized || moduleName == CImportedModuleNames.objectiveC
    }
}

// MARK: - ReadingContext Support

extension ContextDescriptorProtocol {
    public func parent(in context: some ReadingContext) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        guard layout.flags.kind != .module, layout.parent.isValid else { return nil }
        let baseAddress = try context.addressFromOffset(offset)
        let address = context.advanceAddress(baseAddress, by: layout.offset(of: .parent).cast())
        return try layout.parent.resolve(at: address, in: context).asOptional
    }

    public func genericContext(in context: some ReadingContext) throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try GenericContext(contextDescriptor: self, in: context)
    }

    public func moduleContextDescriptor(in context: some ReadingContext) throws -> (any ModuleContextDescriptorProtocol)? {
        if let module = self as? (any ModuleContextDescriptorProtocol) {
            return module
        } else {
            var parent: SymbolOrElement<ContextDescriptorWrapper>? = try parent(in: context)
            while let currentParent = parent {
                if let module = currentParent.resolved?.contextDescriptor as? (any ModuleContextDescriptorProtocol) {
                    return module
                }
                parent = try currentParent.resolved?.parent(in: context)
            }
            return nil
        }
    }

    public func isCImportedContextDescriptor(in context: some ReadingContext) throws -> Bool {
        guard let moduleContextDescriptor = try moduleContextDescriptor(in: context) else { return false }
        let moduleName = try moduleContextDescriptor.name(in: context)
        return moduleName == CImportedModuleNames.cSynthesized || moduleName == CImportedModuleNames.objectiveC
    }
}
