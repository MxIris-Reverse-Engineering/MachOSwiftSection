import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols

extension TypeDefinition {
    /// Builds every symbol-backed member of this type — the six member
    /// categories plus the two `deinit` symbols — from the image's symbol
    /// index, joining each to its dispatch facts through `dispatchLookups`.
    ///
    /// Returns the accessor groups that were suppressed because their name
    /// matches a stored field record: those carry dispatch facts the field
    /// still needs, and `foldStoredPropertyAccessors(_:into:)` folds them back
    /// on. Every other product is assigned onto the definition in place.
    func indexMembers<MachO: MachOSwiftSectionRepresentableWithCache>(
        fieldNames: Set<String>,
        dispatchLookups: ClassDispatchLookups,
        symbolIndexStore: SymbolIndexStore,
        in machO: MachO
    ) -> [String: [Accessor]] {
        let name = typeName.name
        let node = typeName.node

        allocators = DefinitionBuilder.allocators(
            for: symbolIndexStore.memberSymbols(of: .allocator(inExtension: false), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            dispatchLookups: dispatchLookups
        )

        // See the property doc comments for the role each symbol plays.
        // The deallocator drives whether `deinit` is printed at all; the
        // destructor (only present on classes) is exposed as an extra
        // address comment. Both go through the node-matched overload like
        // every other member kind — a name-only `.first` could hand a
        // same-named private sibling's deinit address to this type
        // (issue #115's family).
        deallocatorSymbol = symbolIndexStore.memberSymbols(of: .deallocator, for: name, node: node, in: machO).first?.detachedFromSharedTable()
        destructorSymbol = symbolIndexStore.memberSymbols(of: .destructor, for: name, node: node, in: machO).first?.detachedFromSharedTable()

        let variablesProduct = DefinitionBuilder.variablesProduct(
            for: symbolIndexStore.memberSymbols(of: .variable(inExtension: false, isStatic: false, isStorage: false), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            fieldNames: fieldNames,
            dispatchLookups: dispatchLookups,
            isGlobalOrStatic: false
        )
        variables = variablesProduct.variables

        staticVariables = DefinitionBuilder.variables(
            for: symbolIndexStore.memberSymbols(
                of: .variable(inExtension: false, isStatic: true, isStorage: false),
                .variable(inExtension: false, isStatic: true, isStorage: true),
                for: name,
                node: node,
                in: machO
            ).map { .init(base: $0, offset: nil) },
            dispatchLookups: dispatchLookups,
            isGlobalOrStatic: true
        )

        functions = DefinitionBuilder.functions(
            for: symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: false), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            dispatchLookups: dispatchLookups,
            isGlobalOrStatic: false
        )

        staticFunctions = DefinitionBuilder.functions(
            for: symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: true), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            dispatchLookups: dispatchLookups,
            isGlobalOrStatic: true
        )

        subscripts = DefinitionBuilder.subscripts(
            for: symbolIndexStore.memberSymbols(of: .subscript(inExtension: false, isStatic: false), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            dispatchLookups: dispatchLookups,
            isStatic: false
        )

        staticSubscripts = DefinitionBuilder.subscripts(
            for: symbolIndexStore.memberSymbols(of: .subscript(inExtension: false, isStatic: true), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            dispatchLookups: dispatchLookups,
            isStatic: true
        )

        return variablesProduct.storedPropertyAccessorsByFieldName
    }
}
