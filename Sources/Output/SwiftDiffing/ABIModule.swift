import OrderedCollections
import SwiftDeclaration

/// The fully-indexed, Mach-O-free snapshot of a binary's Swift declarations
/// that `ABIDiffer` consumes.
///
/// Mirrors `SwiftDeclarationIndexer`'s definition-level classification 1:1, so
/// constructing one is a straight passthrough of the indexer's output:
///
/// ```swift
/// let module = ABIModule(
///     allTypeDefinitions: indexer.allTypeDefinitions,
///     allProtocolDefinitions: indexer.allProtocolDefinitions,
///     typeExtensionDefinitions: indexer.typeExtensionDefinitions,
///     // …
/// )
/// ```
///
/// Per the model's contract a `Definition` no longer depends on its Mach-O once
/// indexed, so the caller indexes both binaries (via `SwiftIndexing`), ensures
/// every definition is fully indexed, and hands the collections here. The
/// differ itself touches no Mach-O and is synchronous.
///
/// The `root*` dictionaries are kept for caller reporting (top-level grouping)
/// but are NOT fed to the differ — `ABIDiffer` walks the `all*` dictionaries,
/// which already include nested types keyed by their parent-qualified name, so
/// using `root*` too would double-count.
///
/// Not `Sendable`: it holds the reference-type `*Definition` model objects. The
/// differ is synchronous and single-threaded, so this is not a constraint.
public struct ABIModule {
    // MARK: Types

    public let rootTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition>
    public let allTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition>

    // MARK: Protocols

    public let rootProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition>
    public let allProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition>

    // MARK: Extensions (the indexer's four buckets; each name maps to many)

    public let typeExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]>
    public let protocolExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]>
    public let typeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]>
    public let conformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]>

    // MARK: Globals

    public let globalVariableDefinitions: [VariableDefinition]
    public let globalFunctionDefinitions: [FunctionDefinition]

    public init(
        rootTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:],
        allTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:],
        rootProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:],
        allProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:],
        typeExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:],
        protocolExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:],
        typeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:],
        conformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:],
        globalVariableDefinitions: [VariableDefinition] = [],
        globalFunctionDefinitions: [FunctionDefinition] = []
    ) {
        self.rootTypeDefinitions = rootTypeDefinitions
        self.allTypeDefinitions = allTypeDefinitions
        self.rootProtocolDefinitions = rootProtocolDefinitions
        self.allProtocolDefinitions = allProtocolDefinitions
        self.typeExtensionDefinitions = typeExtensionDefinitions
        self.protocolExtensionDefinitions = protocolExtensionDefinitions
        self.typeAliasExtensionDefinitions = typeAliasExtensionDefinitions
        self.conformanceExtensionDefinitions = conformanceExtensionDefinitions
        self.globalVariableDefinitions = globalVariableDefinitions
        self.globalFunctionDefinitions = globalFunctionDefinitions
    }
}
