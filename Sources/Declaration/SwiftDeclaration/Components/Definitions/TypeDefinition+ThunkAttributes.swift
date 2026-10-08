import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols

extension TypeDefinition {
    /// Cross-references `@objc` / `@nonobjc` thunk attribute members (pre-extracted
    /// and bucketed by parent type name inside `SymbolIndexStore`) with the
    /// already-built member definitions of this type, appending the matching
    /// attribute to each affected member. The matching itself lives in
    /// `MemberAttributeApplication`, shared with `ExtensionDefinition`.
    func applyThunkAttributes(
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

    func applyAttributeToFunction(name: String, attribute: SwiftAttribute, in definitions: inout [FunctionDefinition]) {
        MemberAttributeApplication.apply(attribute, toFunctionNamed: name, in: &definitions)
    }

    func applyAttributeToVariable(name: String, attribute: SwiftAttribute, in definitions: inout [VariableDefinition]) {
        MemberAttributeApplication.apply(attribute, toVariableNamed: name, in: &definitions)
    }

    func applyAttributeToAllocator(attribute: SwiftAttribute, in definitions: inout [FunctionDefinition]) {
        MemberAttributeApplication.apply(attribute, toEveryAllocatorIn: &definitions)
    }
}
