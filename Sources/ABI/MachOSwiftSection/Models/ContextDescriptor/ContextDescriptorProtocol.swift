import MachOKit
import MachOBase

@dynamicMemberLookup
public protocol ContextDescriptorProtocol: ResolvableLocatableLayoutWrapper where Layout: ContextDescriptorLayout {
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
