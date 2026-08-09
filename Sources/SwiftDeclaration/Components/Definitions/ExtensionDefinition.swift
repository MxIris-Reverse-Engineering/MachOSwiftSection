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

    public package(set) var missingSymbolWitnesses: [ResilientWitness] = []

    public package(set) var orderedMembers: [OrderedMember] = []

    public private(set) var isIndexed: Bool = false

    public var hasMembers: Bool {
        !variables.isEmpty || !functions.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !allocators.isEmpty || !constructors.isEmpty || !staticSubscripts.isEmpty || !subscripts.isEmpty
    }

    /// The initializer still receives the full `ProtocolConformance` — the
    /// indexer materializes the whole conformance section anyway to derive
    /// attribution — but only its descriptor reference is retained, so the
    /// parsed wrapper (and its `[ResilientWitness]`) is released once the
    /// indexer's grouping pass ends.
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

    package func index<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) async throws {
        guard !isIndexed else { return }

        // Cheap pre-check on the retained descriptor keeps the typealias-only
        // majority from materializing at all; the one materialization below
        // is this operation's single allowed one (proposal 0002).
        guard protocolConformanceDescriptor != nil else { return }
        guard let protocolConformance = try materializedProtocolConformance(in: machO), !protocolConformance.resilientWitnesses.isEmpty else { return }

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

        for resilientWitness in protocolConformance.resilientWitnesses {
            if let symbols = try resilientWitness.implementationSymbols(in: machO), let symbol = try _symbol(for: symbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                _ = visitedNodes.append(StructuralNodeReferenceKey(symbol.demangledNode))
                addSymbol(.init(symbol), memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
            } else if let requirement = try resilientWitness.requirement(in: machO) {
                switch requirement {
                case .symbol(let symbol):
                    if let demangledNode = MetadataReader.demangleSymbolReference(for: symbol, in: machO) {
                        addSymbol(.init(.init(symbol: symbol, demangledNode: demangledNode)), memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
                    }
                case .element(let element):
                    if let symbols = try await Symbols.resolve(from: element.offset, in: machO), let symbol = try _symbol(for: symbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(StructuralNodeReferenceKey(symbol.demangledNode))
                        addSymbol(.init(symbol), memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
                    } else if let defaultImplementationSymbols = try element.defaultImplementationSymbols(in: machO), let symbol = try _symbol(for: defaultImplementationSymbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(StructuralNodeReferenceKey(symbol.demangledNode))
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

        orderedMembers = OrderedMember.offsetOrdered(OrderedMember.allMembers(from: self))

        isIndexed = true
    }
}
