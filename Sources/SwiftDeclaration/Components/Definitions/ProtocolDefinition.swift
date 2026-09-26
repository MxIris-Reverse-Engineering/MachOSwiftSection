import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import Demangling
import Semantic
import SwiftStdlibToolbox
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

public final class ProtocolDefinition: Definition, MutableDefinition {
    /// The protocol's descriptor reference (evolution proposal 0002). The
    /// full `MachOSwiftSection.Protocol` — requirement arrays included — is
    /// rebuilt on demand via `materializedProtocol(in:)` instead of living
    /// on every definition for its lifetime; the name is frozen separately
    /// in `protocolName`.
    public let protocolDescriptor: ProtocolDescriptor

    public let protocolName: ProtocolName

    public package(set) weak var parent: TypeDefinition?

    public package(set) var extensionContext: ExtensionContext? = nil

    public package(set) var defaultImplementationExtensions: [ExtensionDefinition] = []

    public package(set) var associatedTypes: [String] = []

    public package(set) var allocators: [FunctionDefinition] = []

    public package(set) var constructors: [FunctionDefinition] = []

    public package(set) var variables: [VariableDefinition] = []

    public package(set) var functions: [FunctionDefinition] = []

    public package(set) var subscripts: [SubscriptDefinition] = []

    public package(set) var staticVariables: [VariableDefinition] = []

    public package(set) var staticFunctions: [FunctionDefinition] = []

    public package(set) var staticSubscripts: [SubscriptDefinition] = []

    public package(set) var strippedSymbolicRequirements: [StrippedSymbolicRequirement] = []

    /// The PWT offsets of every requirement (resolved or stripped) that
    /// carries a **resilient default witness** — read from the descriptor's
    /// relative pointer (pure arithmetic, no symbol table), so the fact is
    /// exact even when the default's own symbol is stripped. The compiler
    /// emits default witnesses only for resilient protocols (public,
    /// library-evolution module); a non-resilient protocol's requirements
    /// never appear here even with source-level defaults. Correlates with the
    /// `offset` stored on resolved members' definitions/accessors; consumed
    /// by SwiftDiffing's default-implementation-aware compatibility verdict.
    public package(set) var defaultedRequirementPWTOffsets: Set<Int> = []

    public package(set) var orderedMembers: [OrderedMember] = []

    /// Whether `index(in:)` has completed a pass over this definition.
    ///
    /// The setter is `internal`, not `private`, only because the indexing
    /// pass lives in `ProtocolDefinition+Indexing.swift`: nothing outside this
    /// target may flip it, and inside it only that pass does.
    public internal(set) var isIndexed: Bool = false

    /// Whether this protocol's descriptor is in the image's export trie,
    /// resolved once at construction (see ``ExportStatus``). Available the
    /// moment `SwiftDeclarationIndexer.prepare()` returns — the verdict needs
    /// only the descriptor's offset and the name node, never `index(in:)`'s
    /// products. Same symbol-index caveat as
    /// ``TypeDefinition/exportStatus``.
    public let exportStatus: ExportStatus

    public var hasMembers: Bool {
        !associatedTypes.isEmpty || !variables.isEmpty || !functions.isEmpty ||
            !subscripts.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !staticSubscripts.isEmpty || !allocators.isEmpty || !constructors.isEmpty || !strippedSymbolicRequirements.isEmpty
    }

    /// The initializer still receives the full wrapper — the indexer holds
    /// one from the section sweep anyway — but only its descriptor reference
    /// is retained.
    public init(`protocol`: MachOSwiftSection.`Protocol`, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        self.protocolDescriptor = `protocol`.descriptor
        let node = try SymbolicDemangler.demangleContext(for: .protocol(`protocol`.descriptor), in: machO)
        let protocolName = ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: node, in: machO))
        self.protocolName = protocolName
        self.exportStatus = ExportStatus.resolve(
            forProtocolDescriptorAt: `protocol`.descriptor.offset,
            protocolNameNode: protocolName.node,
            in: machO
        )
    }

    /// Test/tooling surface: constructs a definition around a RAW descriptor
    /// reference, no parsed wrapper required — error-contract tests use it to
    /// build a definition whose materialization deterministically fails
    /// (a real descriptor layout re-wrapped at an out-of-bounds offset).
    /// Mirrors `ExtensionDefinition`'s descriptor-only initializer.
    /// `exportStatus` defaults to the no-verdict case because a definition
    /// built this way has no trustworthy descriptor to rule on.
    package init(
        protocolDescriptor: ProtocolDescriptor,
        protocolName: ProtocolName,
        exportStatus: ExportStatus = .descriptorSymbolNameUnresolvable
    ) {
        self.protocolDescriptor = protocolDescriptor
        self.protocolName = protocolName
        self.exportStatus = exportStatus
    }

    /// Rebuilds the full `MachOSwiftSection.Protocol` (requirement arrays
    /// included) from the retained descriptor. Materialization discipline
    /// (evolution proposal 0002): call at most once per operation and thread
    /// the result through as a local variable — the result is deliberately
    /// not cached.
    public func materializedProtocol(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MachOSwiftSection.`Protocol` {
        try MachOSwiftSection.`Protocol`(descriptor: protocolDescriptor, in: machO)
    }
}
