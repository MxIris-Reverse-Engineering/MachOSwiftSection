import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols

/// Cross-references `@objc` / `@nonobjc` / `distributed` thunk attribute
/// members (pre-extracted and bucketed by parent type name inside
/// `SymbolIndexStore`) with already-built member definitions, appending the
/// matching attribute to each affected member. Shared by `TypeDefinition`
/// and `ExtensionDefinition` — the sweep unwraps extension contexts when it
/// buckets a thunk, so an extension's members are filed under the extended
/// type's name and node, and one lookup serves both containers.
package enum MemberAttributeApplication {
    /// Each thunk kind with the attribute it proves and the suffix its
    /// mangling appends to the member's name.
    package static let thunkKindsAndAttributes: [(thunkKind: Node.Kind, attribute: SwiftAttribute, mangledSuffix: String)] = [
        (.objCAttribute, .objc, "To"),
        (.nonObjCAttribute, .nonobjc, "TO"),
        (.distributedThunk, .distributed, "TE"),
    ]

    package static func applyThunkAttributes(
        symbolIndexStore: SymbolIndexStore,
        typeName: String,
        typeNode: NodeReference,
        in machO: some MachORepresentableWithCache,
        functions: inout [FunctionDefinition],
        variables: inout [VariableDefinition],
        staticFunctions: inout [FunctionDefinition],
        staticVariables: inout [VariableDefinition],
        allocators: inout [FunctionDefinition]
    ) {
        for (thunkKind, attribute, mangledSuffix) in thunkKindsAndAttributes {
            // Node-matched: the member-name matching below is string-based,
            // so a same-named private sibling's thunks must never reach it
            // (issue #115's family).
            let members = symbolIndexStore.thunkAttributeMembers(of: thunkKind, for: typeName, node: typeNode, in: machO)
            var hasInitializerThunk = false
            for member in members {
                if member.isStatic {
                    apply(attribute, toFunctionsNamed: member.memberName, withThunkSuffix: mangledSuffix, in: &staticFunctions, symbolIndexStore: symbolIndexStore, in: machO)
                    apply(attribute, toVariableNamed: member.memberName, in: &staticVariables)
                } else {
                    apply(attribute, toFunctionsNamed: member.memberName, withThunkSuffix: mangledSuffix, in: &functions, symbolIndexStore: symbolIndexStore, in: machO)
                    apply(attribute, toVariableNamed: member.memberName, in: &variables)
                    if member.isInit {
                        hasInitializerThunk = true
                    }
                }
            }
            if hasInitializerThunk {
                apply(attribute, toAllocatorsWithThunkSuffix: mangledSuffix, in: &allocators, symbolIndexStore: symbolIndexStore, in: machO)
            }
        }
    }

    /// `attribute` on each of `definitions` named `name` whose own symbol has
    /// the thunk `mangledSuffix` spells: a thunk's name is its member's mangled
    /// name plus the suffix. Overloads share a name, and the name alone gave
    /// the attribute to a Swift-only overload of an `@objc` method. A merged
    /// function (`…Tm`) is the member it was merged from.
    package static func apply(
        _ attribute: SwiftAttribute,
        toFunctionsNamed name: String,
        withThunkSuffix mangledSuffix: String,
        in definitions: inout [FunctionDefinition],
        symbolIndexStore: SymbolIndexStore,
        in machO: some MachORepresentableWithCache
    ) {
        for definitionIndex in definitions.indices where definitions[definitionIndex].name == name && !definitions[definitionIndex].attributes.contains(attribute) {
            var memberSymbolName = definitions[definitionIndex].symbol.name
            if memberSymbolName.hasSuffix("Tm") {
                memberSymbolName.removeLast(2)
            }
            if symbolIndexStore.containsSymbol(named: memberSymbolName + mangledSuffix, in: machO) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }

    package static func apply(_ attribute: SwiftAttribute, toFunctionNamed name: String, in definitions: inout [FunctionDefinition]) {
        for definitionIndex in definitions.indices {
            if definitions[definitionIndex].name == name && !definitions[definitionIndex].attributes.contains(attribute) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }

    package static func apply(_ attribute: SwiftAttribute, toVariableNamed name: String, in definitions: inout [VariableDefinition]) {
        for definitionIndex in definitions.indices {
            if definitions[definitionIndex].name == name && !definitions[definitionIndex].attributes.contains(attribute) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }

    /// `attribute` on each allocator whose initializer has a thunk of the
    /// kind `mangledSuffix` spells. An initializer's thunk records no member
    /// name to match by (its `memberName` is the first identifier the tree
    /// reaches, the type's), so the initializer is found by mangled name: the
    /// thunk enters the initializing entry point, whose name is the
    /// allocator's with `fC` swapped for `fc`. Every allocator used to get the
    /// attribute as soon as one initializer had the thunk, which printed a
    /// Swift-only initializer as `@objc init(rootView:)` beside the class's
    /// `@objc init?(coder:)`.
    package static func apply(
        _ attribute: SwiftAttribute,
        toAllocatorsWithThunkSuffix mangledSuffix: String,
        in definitions: inout [FunctionDefinition],
        symbolIndexStore: SymbolIndexStore,
        in machO: some MachORepresentableWithCache
    ) {
        for definitionIndex in definitions.indices where !definitions[definitionIndex].attributes.contains(attribute) {
            var allocatorName = definitions[definitionIndex].symbol.name
            if allocatorName.hasSuffix("Tm") {
                allocatorName.removeLast(2)
            }
            guard allocatorName.hasSuffix("fC") else { continue }
            let thunkName = String(allocatorName.dropLast(2)) + "fc" + mangledSuffix
            if symbolIndexStore.containsSymbol(named: thunkName, in: machO) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }
}
