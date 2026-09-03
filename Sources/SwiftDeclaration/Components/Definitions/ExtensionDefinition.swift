import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import Demangling
import Semantic
import SwiftStdlibToolbox
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

public final class ExtensionDefinition: Definition, MutableDefinition {
    public let extensionName: ExtensionName

    public let genericSignature: NodeReference?

    /// The conformance's descriptor reference (evolution proposal 0002), or
    /// `nil` for member / typealias-only extensions. The full
    /// `ProtocolConformance` — resilient witnesses and the rest of its
    /// trailing objects — is rebuilt on demand via
    /// `materializedProtocolConformance(in:)` instead of living on every
    /// conformance extension for its lifetime.
    ///
    /// One documented exception: `missingSymbolWitnesses` below copies the
    /// witnesses this extension could not resolve to a symbol, so an extension
    /// that has any does retain that subset for its lifetime.
    public let protocolConformanceDescriptor: ProtocolConformanceDescriptor?

    /// The conformed protocol, resolved to a Mach-O-free name at index time.
    /// Non-nil only for conformance extensions; the target's typealias-only
    /// blocks and member extensions carry `nil`. This is what lets the
    /// Mach-O-free diff layer attribute changes to a specific conformance.
    public let conformingProtocolName: ProtocolName?

    public package(set) var associatedTypes: [AssociatedType]

    /// The associated-type witnesses of `associatedTypes`, resolved into pure
    /// value data at index time (their `AssociatedTypeRecord` accessors are
    /// Mach-O-bound, so the snapshot layer cannot resolve them later).
    public package(set) var resolvedAssociatedTypeWitnesses: [AssociatedTypeWitnessProjection]

    public package(set) var types: [TypeDefinition] = []

    public package(set) var protocols: [ProtocolDefinition] = []

    public package(set) var allocators: [FunctionDefinition] = []

    public package(set) var constructors: [FunctionDefinition] = []

    public package(set) var variables: [VariableDefinition] = []

    public package(set) var functions: [FunctionDefinition] = []

    public package(set) var subscripts: [SubscriptDefinition] = []

    public package(set) var staticVariables: [VariableDefinition] = []

    public package(set) var staticFunctions: [FunctionDefinition] = []

    public package(set) var staticSubscripts: [SubscriptDefinition] = []

    public package(set) var isRetroactive: Bool = false

    /// Set by the indexer's container-unification pass (evolution proposal
    /// 0007) when this symbol-scan protocol-extension block was attached to
    /// its `ProtocolDefinition.defaultImplementationExtensions` — the
    /// top-level interface then renders it trailing the protocol declaration
    /// and skips it in the extensions block, so the same block no longer
    /// prints twice. The definition deliberately STAYS in the indexer's
    /// bucket: the ABI-diff layer snapshots containers from the buckets, and
    /// removing it there would silently drop the container from snapshots.
    public package(set) var isAttachedToProtocolDefinition: Bool = false

    /// Resilient witnesses `index(in:)` could not resolve to an implementation
    /// symbol.
    ///
    /// The one `[ResilientWitness]` that survives proposal 0002's descriptor
    /// slimming (see `protocolConformanceDescriptor`) — retained deliberately as
    /// an SPI-consumer surface for inspecting stripped conformances, with no
    /// in-package consumer today. Note `index(in:)` appends without resetting,
    /// so a re-entry after a mid-loop throw would record an entry twice; that is
    /// inert only because nothing reads the array. Anything that starts reading
    /// it must clear it at the top of `index(in:)` first.
    public package(set) var missingSymbolWitnesses: [ResilientWitness] = []

    public package(set) var orderedMembers: [OrderedMember] = []

    public private(set) var isIndexed: Bool = false

    public var hasMembers: Bool {
        !variables.isEmpty || !functions.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !allocators.isEmpty || !constructors.isEmpty || !staticSubscripts.isEmpty || !subscripts.isEmpty
    }

    /// The initializer still receives the full `ProtocolConformance` — the
    /// indexer materializes the whole conformance section anyway to derive
    /// attribution — but only its descriptor reference is retained, so the
    /// parsed wrapper is released once the indexer's grouping pass ends. Its
    /// `[ResilientWitness]` goes with it, except for the unresolvable subset
    /// `index(in:)` copies onto `missingSymbolWitnesses`.
    public init<MachO: MachOSwiftSectionRepresentableWithCache>(extensionName: ExtensionName, genericSignature: NodeReference?, protocolConformance: ProtocolConformance?, conformingProtocolName: ProtocolName? = nil, associatedTypes: [AssociatedType] = [], resolvedAssociatedTypeWitnesses: [AssociatedTypeWitnessProjection] = [], in machO: MachO) throws {
        self.extensionName = extensionName
        self.genericSignature = genericSignature
        self.protocolConformanceDescriptor = protocolConformance?.descriptor
        self.conformingProtocolName = conformingProtocolName
        self.associatedTypes = associatedTypes
        self.resolvedAssociatedTypeWitnesses = resolvedAssociatedTypeWitnesses
    }

    /// Mach-O-free initializer for pure-value construction (tests, tooling).
    /// Carries no conformance descriptor — only the frozen attribution fields.
    package init(extensionName: ExtensionName, genericSignature: NodeReference?, conformingProtocolName: ProtocolName? = nil, resolvedAssociatedTypeWitnesses: [AssociatedTypeWitnessProjection] = []) {
        self.extensionName = extensionName
        self.genericSignature = genericSignature
        self.protocolConformanceDescriptor = nil
        self.conformingProtocolName = conformingProtocolName
        self.associatedTypes = []
        self.resolvedAssociatedTypeWitnesses = resolvedAssociatedTypeWitnesses
    }

    /// Test/tooling surface: constructs a definition around a RAW descriptor
    /// reference, no parsed wrapper required — error-contract tests use it to
    /// build a definition whose materialization deterministically fails
    /// (a real descriptor layout re-wrapped at an out-of-bounds offset).
    package init(extensionName: ExtensionName, genericSignature: NodeReference?, protocolConformanceDescriptor: ProtocolConformanceDescriptor?) {
        self.extensionName = extensionName
        self.genericSignature = genericSignature
        self.protocolConformanceDescriptor = protocolConformanceDescriptor
        self.conformingProtocolName = nil
        self.associatedTypes = []
        self.resolvedAssociatedTypeWitnesses = []
    }

    /// Rebuilds the full `ProtocolConformance` (trailing objects included)
    /// from the retained descriptor; `nil` for member / typealias-only
    /// extensions. Materialization discipline (evolution proposal 0002):
    /// call at most once per operation and thread the result through as a
    /// local variable — the result is deliberately not cached.
    public func materializedProtocolConformance<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolConformance? {
        try protocolConformanceDescriptor.map { try ProtocolConformance(descriptor: $0, in: machO) }
    }

    /// Folds another definition's associated types (and their frozen witness
    /// projections) into this one — the indexer's typealias-only merge path.
    package func absorbAssociatedTypes(of other: ExtensionDefinition) {
        associatedTypes.append(contentsOf: other.associatedTypes)
        for projection in other.resolvedAssociatedTypeWitnesses where !resolvedAssociatedTypeWitnesses.contains(projection) {
            resolvedAssociatedTypeWitnesses.append(projection)
        }
    }

    /// Folds another definition's members and nested declarations into this
    /// one — the indexer's same-container-identity merge (evolution proposal
    /// 0007): two `ExtensionDefinition`s under the same extension name with
    /// the same (protocol, where-clause, retroactive) identity are one source
    /// container that different producers discovered separately (the
    /// nested-type discovery vs the member-symbol scan), so their contents
    /// belong in one printed block. The producers see disjoint content, so
    /// this appends without member-level dedup; `orderedMembers` is rebuilt
    /// to interleave the union by offset.
    package func absorbMembers(of other: ExtensionDefinition) {
        types.append(contentsOf: other.types)
        protocols.append(contentsOf: other.protocols)
        allocators.append(contentsOf: other.allocators)
        constructors.append(contentsOf: other.constructors)
        variables.append(contentsOf: other.variables)
        functions.append(contentsOf: other.functions)
        subscripts.append(contentsOf: other.subscripts)
        staticVariables.append(contentsOf: other.staticVariables)
        staticFunctions.append(contentsOf: other.staticFunctions)
        staticSubscripts.append(contentsOf: other.staticSubscripts)
        missingSymbolWitnesses.append(contentsOf: other.missingSymbolWitnesses)
        absorbAssociatedTypes(of: other)
        orderedMembers = OrderedMember.offsetOrdered(OrderedMember.allMembers(from: self))
    }

    package func index<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) async throws {
        guard !isIndexed else { return }

        // Cheap pre-check on the retained descriptor keeps the typealias-only
        // majority from materializing at all; the one materialization below
        // is this operation's single allowed one (proposal 0002). Both early
        // returns are COMPLETED indexings ("nothing to index"), so they must
        // set `isIndexed` — otherwise every later consumer (the printer's
        // three probes plus the diffable builder) re-enters the whole
        // materialization per print. A thrown materialization deliberately
        // leaves the flag unset so a failed read can be retried.
        guard protocolConformanceDescriptor != nil else {
            isIndexed = true
            return
        }
        guard let protocolConformance = try materializedProtocolConformance(in: machO), !protocolConformance.resilientWitnesses.isEmpty else {
            isIndexed = true
            return
        }

        // Structurally keyed: `demangleSymbolReference` returns references from
        // different stores, and store-identity equality would let the same
        // implementation symbol be claimed by two witnesses.
        func _symbol(for symbols: Symbols, typeName: String, visitedNodes: borrowing OrderedSet<StructuralNodeReferenceKey> = []) throws -> DemangledSymbol? {
            for symbol in symbols {
                if let node = MetadataReader.demangleSymbolReference(for: symbol, in: machO), let protocolConformanceNode = node.first(of: .protocolConformance), let symbolTypeName = protocolConformanceNode.children.first?.print(using: .interfaceTypeBuilderOnly), symbolTypeName == typeName || PrimitiveTypeMappingCache.shared.storage(in: machO)?.primitiveType(for: typeName) == symbolTypeName, !visitedNodes.contains(StructuralNodeReferenceKey(node)) {
                    return .init(symbol: symbol, demangledNode: node)
                }
            }
            return nil
        }
        var visitedNodes: OrderedSet<StructuralNodeReferenceKey> = []
        var memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbolWithOffset]> = [:]
        var defaultImplementationSymbolNames: Set<String> = []

        for resilientWitness in protocolConformance.resilientWitnesses {
            if let symbols = resilientWitness.implementationSymbols(in: machO), let symbol = try _symbol(for: symbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                _ = visitedNodes.append(StructuralNodeReferenceKey(symbol.demangledNode))
                addSymbol(.init(symbol), memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
            } else if let requirement = try resilientWitness.requirement(in: machO) {
                switch requirement {
                case .symbol(let symbol):
                    if let demangledNode = MetadataReader.demangleSymbolReference(for: symbol, in: machO) {
                        addSymbol(.init(.init(symbol: symbol, demangledNode: demangledNode)), memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
                    }
                case .element(let element):
                    if let symbols = machO.symbols(offset: element.offset), let symbol = try _symbol(for: symbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(StructuralNodeReferenceKey(symbol.demangledNode))
                        addSymbol(.init(symbol), memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
                    } else if let defaultImplementationSymbols = element.defaultImplementationSymbols(in: machO), let symbol = try _symbol(for: defaultImplementationSymbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(StructuralNodeReferenceKey(symbol.demangledNode))
                        // The witness resolved through the requirement's
                        // DEFAULT implementation — the code lives in a
                        // protocol extension, not on the conforming type
                        // (evolution proposal 0007). Remember the symbol so
                        // the built member can carry the fact.
                        defaultImplementationSymbolNames.insert(symbol.name)
                        addSymbol(.init(symbol), memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
                    } else if !element.defaultImplementation.isNull {
                        missingSymbolWitnesses.append(resilientWitness)
                    } else if !resilientWitness.implementation.isNull {
                        missingSymbolWitnesses.append(resilientWitness)
                    } else {
                        missingSymbolWitnesses.append(resilientWitness)
                    }
                }
            } else if !resilientWitness.implementation.isNull {
                missingSymbolWitnesses.append(resilientWitness)
            } else {
                missingSymbolWitnesses.append(resilientWitness)
            }
        }

        setDefinitions(for: memberSymbolsByKind, inExtension: true)

        if !defaultImplementationSymbolNames.isEmpty {
            markProtocolExtensionDefaults(named: defaultImplementationSymbolNames)
        }

        orderedMembers = OrderedMember.offsetOrdered(OrderedMember.allMembers(from: self))

        isIndexed = true
    }

    /// Marks the members whose witness resolved through a protocol
    /// requirement's default implementation, matched back by mangled symbol
    /// name after `setDefinitions` built them.
    private func markProtocolExtensionDefaults(named symbolNames: Set<String>) {
        for index in functions.indices where symbolNames.contains(functions[index].symbol.name) {
            functions[index].isProtocolExtensionDefault = true
        }
        for index in staticFunctions.indices where symbolNames.contains(staticFunctions[index].symbol.name) {
            staticFunctions[index].isProtocolExtensionDefault = true
        }
        for index in allocators.indices where symbolNames.contains(allocators[index].symbol.name) {
            allocators[index].isProtocolExtensionDefault = true
        }
        for index in constructors.indices where symbolNames.contains(constructors[index].symbol.name) {
            constructors[index].isProtocolExtensionDefault = true
        }
        for index in variables.indices where variables[index].accessors.contains(where: { symbolNames.contains($0.symbol.name) }) {
            variables[index].isProtocolExtensionDefault = true
        }
        for index in staticVariables.indices where staticVariables[index].accessors.contains(where: { symbolNames.contains($0.symbol.name) }) {
            staticVariables[index].isProtocolExtensionDefault = true
        }
        for index in subscripts.indices where subscripts[index].accessors.contains(where: { symbolNames.contains($0.symbol.name) }) {
            subscripts[index].isProtocolExtensionDefault = true
        }
        for index in staticSubscripts.indices where staticSubscripts[index].accessors.contains(where: { symbolNames.contains($0.symbol.name) }) {
            staticSubscripts[index].isProtocolExtensionDefault = true
        }
    }
}
