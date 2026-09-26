import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols

extension ExtensionDefinition {
    /// The extension-side twin of `TypeDefinition.applyThunkAttributes`
    /// (evolution proposal `objc-implementation-class-recognition`): the sweep
    /// files an extension member's `To` thunk under the EXTENDED type's name
    /// and node, so the same lookup that decorates a type's own members
    /// decorates the members its extensions add. Before this the interface
    /// printed `@objc` on a class's members but never on its extensions'.
    package func applyThunkAttributes(
        symbolIndexStore: SymbolIndexStore,
        typeName: String,
        typeNode: NodeReference,
        in machO: some MachORepresentableWithCache
    ) {
        MemberAttributeApplication.applyThunkAttributes(
            symbolIndexStore: symbolIndexStore,
            typeName: typeName,
            typeNode: typeNode,
            in: machO,
            functions: &functions,
            variables: &variables,
            staticFunctions: &staticFunctions,
            staticVariables: &staticVariables,
            allocators: &allocators
        )
    }
}
