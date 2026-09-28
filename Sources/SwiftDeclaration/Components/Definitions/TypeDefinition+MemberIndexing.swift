import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols

extension TypeDefinition {
    /// Builds every symbol-backed member of this type — the six member
    /// categories plus the two `deinit` symbols — from the image's symbol
    /// index, joining each to its dispatch facts through `dispatchLookups`.
    ///
    /// A class's vtable member the image has no implementation symbol for is
    /// built from the symbol its method descriptor's `Tq` stands in for
    /// (`ClassDispatchLookups.supplementing(_:in:)`, evolution proposal
    /// `interface-descriptor-only-vtable-members`): a library-evolution image
    /// exports only the `Tj` / `Tq` forms of a public class method, so with
    /// the local symbols stripped — AppKit in the OS dyld shared cache, or any
    /// binary run through `strip -x` — those members had nothing else to be
    /// built from and went missing.
    ///
    /// Returns the accessor groups that were suppressed because their name
    /// matches a stored field record: those carry dispatch facts the field
    /// still needs, and `foldStoredPropertyAccessors(_:into:)` folds them back
    /// on. Every other product is assigned onto the definition in place.
    func indexMembers(
        fieldNames: Set<String>,
        dispatchLookups: ClassDispatchLookups,
        symbolIndexStore: SymbolIndexStore,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) -> [String: [Accessor]] {
        let name = typeName.name
        let node = typeName.node

        allocators = DefinitionBuilder.allocators(
            for: dispatchLookups.supplementing(symbolIndexStore.memberSymbols(of: .allocator(inExtension: false), for: name, node: node, in: machO), in: .allocators).mapToAnnotatedSymbols(),
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
            for: dispatchLookups.supplementing(symbolIndexStore.memberSymbols(of: .variable(inExtension: false, isStatic: false, isStorage: false), for: name, node: node, in: machO), in: .variables).mapToAnnotatedSymbols(),
            fieldNames: fieldNames,
            dispatchLookups: dispatchLookups,
            isGlobalOrStatic: false
        )
        variables = variablesProduct.variables

        staticVariables = DefinitionBuilder.variables(
            for: dispatchLookups.supplementing(
                symbolIndexStore.memberSymbols(
                    of: .variable(inExtension: false, isStatic: true, isStorage: false),
                    .variable(inExtension: false, isStatic: true, isStorage: true),
                    for: name,
                    node: node,
                    in: machO
                ),
                in: .staticVariables
            ).mapToAnnotatedSymbols(),
            dispatchLookups: dispatchLookups,
            isGlobalOrStatic: true
        )

        functions = DefinitionBuilder.functions(
            for: dispatchLookups.supplementing(symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: false), for: name, node: node, in: machO), in: .functions).mapToAnnotatedSymbols(),
            dispatchLookups: dispatchLookups,
            isGlobalOrStatic: false
        )

        staticFunctions = DefinitionBuilder.functions(
            for: dispatchLookups.supplementing(symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: true), for: name, node: node, in: machO), in: .staticFunctions).mapToAnnotatedSymbols(),
            dispatchLookups: dispatchLookups,
            isGlobalOrStatic: true
        )

        subscripts = DefinitionBuilder.subscripts(
            for: dispatchLookups.supplementing(symbolIndexStore.memberSymbols(of: .subscript(inExtension: false, isStatic: false), for: name, node: node, in: machO), in: .subscripts).mapToAnnotatedSymbols(),
            dispatchLookups: dispatchLookups,
            isStatic: false
        )

        staticSubscripts = DefinitionBuilder.subscripts(
            for: dispatchLookups.supplementing(symbolIndexStore.memberSymbols(of: .subscript(inExtension: false, isStatic: true), for: name, node: node, in: machO), in: .staticSubscripts).mapToAnnotatedSymbols(),
            dispatchLookups: dispatchLookups,
            isStatic: true
        )

        return variablesProduct.storedPropertyAccessorsByFieldName
    }
}
