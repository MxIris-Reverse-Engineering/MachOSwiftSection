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

    /// Whether `index(in:)` has completed a pass over this definition.
    ///
    /// The setter is `internal`, not `private`, only because the indexing
    /// pass lives in `ExtensionDefinition+Indexing.swift`: nothing outside this
    /// target may flip it, and inside it only that pass does.
    public internal(set) var isIndexed: Bool = false

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
}
