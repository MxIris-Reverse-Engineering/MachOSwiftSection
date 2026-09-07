import SwiftDeclaration
import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import Demangling
import SwiftStdlibToolbox
import MachOKit
import Dependencies
import Utilities
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches
@_spi(Internals) import SwiftInspection

public struct MachOIndexedValue<MachO: MachOSwiftSectionRepresentableWithCache, Value> {
    public let machO: MachO
    public let value: Value

    @inlinable
    public init(machO: MachO, value: Value) {
        self.machO = machO
        self.value = value
    }
}

extension MachOIndexedValue: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }
}

extension MachOIndexedValue: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

extension MachOIndexedValue: Sendable where Value: Sendable {}

@_spi(Support)
public final class SwiftDeclarationIndexer<MachO: MachOSwiftSectionRepresentableWithCache>: Sendable {
    /// Indexing-local carrier for a nested type's resolved-but-unlinked
    /// parent context (evolution proposal 0002). Lives only for the duration
    /// of `indexTypes()` — it replaced the stored
    /// `TypeDefinition.parentContext` property, which kept a second
    /// fully-parsed `TypeContextWrapper` inline on every affected definition
    /// with no reader after indexing.
    private enum UnlinkedParentContext {
        case `extension`(ExtensionContext)
        case type(TypeContextWrapper)
        case symbol(Symbol)
    }

    /// Snapshot of the six public statistics accessors' answers, frozen at
    /// the end of `prepare()` immediately before the section-wrapper
    /// populations are released (evolution proposal 0002). The accessors
    /// read this snapshot, so they keep answering after the arrays they
    /// were once computed from are gone; before preparation every count
    /// is 0, matching the empty arrays they mirror.
    @usableFromInline
    struct PreparationStatistics: Sendable {
        @usableFromInline var numberOfTypes: Int = 0
        @usableFromInline var numberOfEnums: Int = 0
        @usableFromInline var numberOfStructs: Int = 0
        @usableFromInline var numberOfClasses: Int = 0
        @usableFromInline var numberOfProtocols: Int = 0
        @usableFromInline var numberOfProtocolConformances: Int = 0
    }

    @usableFromInline
    final class Storage: Sendable {
        @usableFromInline @Mutex
        var preparationStatistics: PreparationStatistics = .init()

        @usableFromInline @Mutex
        var types: [TypeContextWrapper] = []

        @usableFromInline @Mutex
        var protocols: [MachOSwiftSection.`Protocol`] = []

        @usableFromInline @Mutex
        var protocolConformances: [ProtocolConformance] = []

        @usableFromInline @Mutex
        var associatedTypes: [AssociatedType] = []

        /// Name-level forward map of the conformance section (evolution
        /// proposal 0002): which protocols each type conforms to. This is
        /// the only per-(type, protocol) fact any post-indexing consumer
        /// reads — the parsed `ProtocolConformance` / `AssociatedType`
        /// values that previously backed the keyed maps here are indexing
        /// transients now, released when `prepare()` finishes.
        @usableFromInline @Mutex
        var conformingProtocolNamesByTypeName: OrderedDictionary<TypeName, OrderedSet<ProtocolName>> = [:]

        @usableFromInline @Mutex
        var conformingTypesByProtocolName: OrderedDictionary<ProtocolName, OrderedSet<TypeName>> = [:]

        @usableFromInline @Mutex
        var rootTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]

        @usableFromInline @Mutex
        var allTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]

        @usableFromInline @Mutex
        var rootProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]

        @usableFromInline @Mutex
        var allProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]

        @usableFromInline @Mutex
        var typeExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]

        @usableFromInline @Mutex
        var protocolExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]

        @usableFromInline @Mutex
        var typeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]

        @usableFromInline @Mutex
        var conformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]

        @usableFromInline @Mutex
        var globalVariableDefinitions: [VariableDefinition] = []

        @usableFromInline @Mutex
        var globalFunctionDefinitions: [FunctionDefinition] = []
    }

    @usableFromInline
    struct AllStorageCache: @unchecked Sendable {
        var allConformingProtocolNamesByTypeName: OrderedDictionary<TypeName, OrderedSet<ProtocolName>>?
        var allConformingTypesByProtocolName: OrderedDictionary<ProtocolName, OrderedSet<MachOIndexedValue<MachO, TypeName>>>?
        var allRootTypeDefinitions: OrderedDictionary<TypeName, MachOIndexedValue<MachO, TypeDefinition>>?
        var allAllTypeDefinitions: OrderedDictionary<TypeName, MachOIndexedValue<MachO, TypeDefinition>>?
        var allRootProtocolDefinitions: OrderedDictionary<ProtocolName, MachOIndexedValue<MachO, ProtocolDefinition>>?
        var allAllProtocolDefinitions: OrderedDictionary<ProtocolName, MachOIndexedValue<MachO, ProtocolDefinition>>?
        var allTypeExtensionDefinitions: OrderedDictionary<ExtensionName, [MachOIndexedValue<MachO, ExtensionDefinition>]>?
        var allProtocolExtensionDefinitions: OrderedDictionary<ExtensionName, [MachOIndexedValue<MachO, ExtensionDefinition>]>?
        var allTypeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [MachOIndexedValue<MachO, ExtensionDefinition>]>?
        var allConformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [MachOIndexedValue<MachO, ExtensionDefinition>]>?
        var allGlobalVariableDefinitions: [MachOIndexedValue<MachO, VariableDefinition>]?
        var allGlobalFunctionDefinitions: [MachOIndexedValue<MachO, FunctionDefinition>]?
    }

    public let machO: MachO

    @Mutex
    public private(set) var configuration: SwiftDeclarationIndexConfiguration = .init()

    @Mutex
    public private(set) var subIndexers: [SwiftDeclarationIndexer<MachO>] = []

    @usableFromInline
    let currentStorage: Storage = .init()

    @Mutex
    @usableFromInline
    var allStorageCache: AllStorageCache = .init()

    /// `package` so a renderer driving this indexer can hand the same dispatcher
    /// to its printers, keeping one sink set for the whole run.
    package let eventDispatcher: SwiftIndexEvents.Dispatcher = .init()

    @Mutex
    private var isPrepared: Bool = false

    public init(configuration: SwiftDeclarationIndexConfiguration = .init(), eventHandlers: [SwiftIndexEvents.Handler] = [], in machO: MachO) {
        self.machO = machO
        self.configuration = configuration
        eventDispatcher.addHandlers(eventHandlers)
    }

    /// Evicts the per-image caches this indexer's `prepare()` was the one to
    /// build, and only when it is the image's LAST live indexer — an
    /// earlier-deinitializing sibling must never wipe caches out from under a
    /// still-live one (the survivor's already-built names would keep an
    /// orphaned store alive while new names land in a fresh one, splitting the
    /// `store ===` fast paths for the rest of its lifetime). PR #103 review,
    /// finding M6; the per-cache split is the follow-up round.
    deinit {
        PerImageCacheEvictionRegistry.deregisterLiveIndexer(
            ObjectIdentifier(self),
            forImageIdentifier: machO.identifier
        ) { claims in
            if claims.symbolStore {
                @Dependency(\.symbolIndexStore)
                var symbolIndexStore
                symbolIndexStore.remove(for: machO)
            }
            // Claimed separately from the symbol store: both of these are also
            // populated by SwiftLayout, the renderers and SwiftSpecialization,
            // so "this indexer built the symbol store" says nothing about who
            // built these.
            //
            // The memo is never left behind when the interned store goes — its
            // values are references INTO that store, so keeping it would pin the
            // store's buffers and the eviction would reclaim nothing. That
            // pairing is enforced by `Claims.normalized`, which the registry
            // applies before calling this, rather than by these three
            // independent branches: as three separate flags the combination
            // "drop the store, keep the memo" was reachable, and it freed
            // nothing at all.
            if claims.internedNames {
                InternedNodeReferenceCache.shared.remove(for: machO)
            }
            if claims.demangleMemo {
                MetadataReader.removeCache(for: machO)
            }
        }
    }

    public func updateConfiguration(_ newConfiguration: SwiftDeclarationIndexConfiguration) async throws {
        let oldConfiguration = configuration

        configuration = newConfiguration

        if oldConfiguration.showCImportedTypes != newConfiguration.showCImportedTypes {
            // `prepare()` is guarded by `isPrepared`, which nothing ever
            // reset — so this re-preparation was a silent no-op on an
            // already-prepared indexer and the configuration change never
            // took effect. Resetting makes the re-run real; the bucket reset
            // at the top of `index()` (evolution proposal 0007) keeps the
            // re-run from duplicating every appended extension block.
            isPrepared = false
            try await prepare()
        }
    }

    public func addSubIndexer(_ subIndexer: SwiftDeclarationIndexer<MachO>) {
        subIndexers.append(subIndexer)
        allStorageCache = AllStorageCache()
    }

    public func removeSubIndexer(at index: Int) {
        subIndexers.remove(at: index)
        allStorageCache = AllStorageCache()
    }

    /// Detaches a previously registered sub-indexer by identity, the inverse of
    /// `addSubIndexer(_:)`. No-op when it was never registered.
    ///
    /// Registration is what keeps a per-image indexer — and therefore its whole
    /// declaration graph, including the `NodeStore` its definitions reference —
    /// alive for as long as the aggregate lives. Dropping the last reference
    /// lets the sub-indexer deinit, which in turn evicts its `SymbolIndexStore`
    /// entry (see this type's `deinit`), so per-image memory is actually
    /// reclaimed. Callers that hold the indexer rather than its position should
    /// prefer this over the index-based overload.
    ///
    /// The search and the removal share one critical section: looking the
    /// position up through the property's getter and then removing it through
    /// `removeSubIndexer(at:)` would take the lock twice, and a concurrent
    /// removal in between would either detach the wrong sub-indexer or trap on
    /// an out-of-range index.
    public func removeSubIndexer(_ subIndexer: SwiftDeclarationIndexer<MachO>) {
        let didRemoveSubIndexer = _subIndexers.withLock { registeredSubIndexers in
            guard let index = registeredSubIndexers.firstIndex(where: { $0 === subIndexer }) else { return false }
            registeredSubIndexers.remove(at: index)
            return true
        }
        guard didRemoveSubIndexer else { return }
        allStorageCache = AllStorageCache()
    }

    /// Indexes the image (section extraction, per-definition construction,
    /// extension-container unification, per-image cache claims). Runs on the
    /// demangler's large-stack task executor (evolution proposal
    /// `large-stack-executor-and-cross-version-parallelism`): every demangle
    /// and print inside runs inline instead of hopping to a pool thread per
    /// call. Output is independent of where it runs.
    public func prepare() async throws {
        if isPrepared { return }
        try await LargeStackTaskExecution.run {
            try await prepareIndexes()
        }
    }

    private func prepareIndexes() async throws {
        eventDispatcher.dispatch(.phaseTransition(phase: .preparation, state: .started))

        for subIndexer in subIndexers {
            try await subIndexer.prepare()
        }

        do {
            eventDispatcher.dispatch(.extractionStarted(section: .swiftTypes))
            currentStorage.types = try machO.swift.types
            eventDispatcher.dispatch(.extractionCompleted(result: SwiftIndexEvents.ExtractionResult(section: .swiftTypes, count: currentStorage.types.count)))
        } catch {
            eventDispatcher.dispatch(.extractionFailed(section: .swiftTypes, error: error))
            currentStorage.types = []
        }

        do {
            eventDispatcher.dispatch(.extractionStarted(section: .swiftProtocols))
            currentStorage.protocols = try machO.swift.protocols
            eventDispatcher.dispatch(.extractionCompleted(result: SwiftIndexEvents.ExtractionResult(section: .swiftProtocols, count: currentStorage.protocols.count)))
        } catch {
            eventDispatcher.dispatch(.extractionFailed(section: .swiftProtocols, error: error))
            currentStorage.protocols = []
        }

        do {
            eventDispatcher.dispatch(.extractionStarted(section: .protocolConformances))
            currentStorage.protocolConformances = try machO.swift.protocolConformances
            eventDispatcher.dispatch(.extractionCompleted(result: SwiftIndexEvents.ExtractionResult(section: .protocolConformances, count: currentStorage.protocolConformances.count)))
        } catch {
            eventDispatcher.dispatch(.extractionFailed(section: .protocolConformances, error: error))
            currentStorage.protocolConformances = []
        }

        do {
            eventDispatcher.dispatch(.extractionStarted(section: .associatedTypes))
            currentStorage.associatedTypes = try machO.swift.associatedTypes
            eventDispatcher.dispatch(.extractionCompleted(result: SwiftIndexEvents.ExtractionResult(section: .associatedTypes, count: currentStorage.associatedTypes.count)))
        } catch {
            eventDispatcher.dispatch(.extractionFailed(section: .associatedTypes, error: error))
            currentStorage.associatedTypes = []
        }

        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        // Sample membership **before** kicking off the build, and register this
        // indexer as a live user of the image's caches. Each cache is sampled
        // on its own: whichever ones are absent now are the ones this
        // `prepare()` is about to install, so those — and only those — are
        // claimed. A claim means "an indexer built this entry", never which
        // one; the eviction itself runs in the deinit of the image's LAST live
        // indexer, so a shared entry never disappears under a live sibling.
        // False-positive claims (an entry someone else then rebuilds) are fine:
        // the worst case is a redundant rebuild after every indexer is gone,
        // which is exactly the pre-cache status quo. Entries built by
        // non-indexer callers are never claimed and never evicted here — and
        // since SwiftLayout / the renderers / SwiftSpecialization populate the
        // interned-name store and the demangle memo without any symbol store,
        // that guarantee only holds if the three are sampled separately.
        PerImageCacheEvictionRegistry.registerLiveIndexer(
            ObjectIdentifier(self),
            forImageIdentifier: machO.identifier
        ) {
            // Inside the registry's lock — see `registerLiveIndexer`. As
            // argument expressions these ran before it was taken.
            .init(
                symbolStore: !symbolIndexStore.contains(in: machO),
                internedNames: !InternedNodeReferenceCache.shared.contains(in: machO),
                demangleMemo: !MetadataReader.cacheExists(for: machO)
            )
        }

        eventDispatcher.dispatch(.extractionStarted(section: .symbolIndex))
        var symbolIndexTotalCount = 0
        for await progress in symbolIndexStore.prepareWithProgress(in: machO) {
            symbolIndexTotalCount = progress.totalCount
            eventDispatcher.dispatch(.symbolIndexProgress(currentCount: progress.currentCount, totalCount: progress.totalCount))
        }
        eventDispatcher.dispatch(.extractionCompleted(result: SwiftIndexEvents.ExtractionResult(section: .symbolIndex, count: symbolIndexTotalCount)))

        do {
            try await index()
        } catch {
            eventDispatcher.dispatch(.phaseTransition(phase: .indexing, state: .failed(error)))
            throw error
        }

        // Freeze the public statistics BEFORE the wrapper populations are
        // released below — post-preparation is the accessors' only useful
        // reading time, and without this snapshot they would silently
        // answer 0 (indistinguishable from an empty binary).
        let indexedTypes = currentStorage.types
        currentStorage.preparationStatistics = PreparationStatistics(
            numberOfTypes: indexedTypes.count,
            numberOfEnums: indexedTypes.count(where: \.isEnum),
            numberOfStructs: indexedTypes.count(where: \.isStruct),
            numberOfClasses: indexedTypes.count(where: \.isClass),
            numberOfProtocols: currentStorage.protocols.count,
            numberOfProtocolConformances: currentStorage.protocolConformances.count
        )

        // The section-wrapper populations are inputs to the index passes and
        // nothing else (evolution proposal 0002): every fact a post-indexing
        // consumer needs has been frozen onto the definitions or the
        // name-level maps above. Releasing them here drops the eagerly
        // parsed trailing-object arrays (`[ResilientWitness]` chief among
        // them) for the indexer's whole lifetime.
        currentStorage.types = []
        currentStorage.protocols = []
        currentStorage.protocolConformances = []
        currentStorage.associatedTypes = []

        eventDispatcher.dispatch(.phaseTransition(phase: .preparation, state: .completed))

        allStorageCache = AllStorageCache()
        isPrepared = true
    }

    private func index() async throws {
        eventDispatcher.dispatch(.phaseTransition(phase: .indexing, state: .started))

        // Idempotence (evolution proposal 0007): the extension producers below
        // APPEND into these buckets (the nested-type discovery in
        // `indexTypes`, the member-symbol scan in `indexExtensions`), so a
        // re-entered run — a retried `prepare()`, `updateConfiguration(_:)` —
        // used to duplicate every appended extension block verbatim while the
        // assigned dictionaries stayed correct.
        currentStorage.typeExtensionDefinitions = [:]
        currentStorage.protocolExtensionDefinitions = [:]
        currentStorage.typeAliasExtensionDefinitions = [:]
        currentStorage.conformanceExtensionDefinitions = [:]

        do {
            eventDispatcher.dispatch(.phaseOperationStarted(phase: .indexing, operation: .typeIndexing))
            try await indexTypes()
            eventDispatcher.dispatch(.phaseOperationCompleted(phase: .indexing, operation: .typeIndexing))
        } catch {
            eventDispatcher.dispatch(.phaseOperationFailed(phase: .indexing, operation: .typeIndexing, error: error))
            throw error
        }

        do {
            eventDispatcher.dispatch(.phaseOperationStarted(phase: .indexing, operation: .protocolIndexing))
            try await indexProtocols()
            eventDispatcher.dispatch(.phaseOperationCompleted(phase: .indexing, operation: .protocolIndexing))
        } catch {
            eventDispatcher.dispatch(.phaseOperationFailed(phase: .indexing, operation: .protocolIndexing, error: error))
            throw error
        }

        do {
            eventDispatcher.dispatch(.phaseOperationStarted(phase: .indexing, operation: .conformanceIndexing))
            try await indexConformances()
            eventDispatcher.dispatch(.phaseOperationCompleted(phase: .indexing, operation: .conformanceIndexing))
        } catch {
            eventDispatcher.dispatch(.phaseOperationFailed(phase: .indexing, operation: .conformanceIndexing, error: error))
            throw error
        }

        do {
            eventDispatcher.dispatch(.phaseOperationStarted(phase: .indexing, operation: .extensionIndexing))
            try await indexExtensions()
            eventDispatcher.dispatch(.phaseOperationCompleted(phase: .indexing, operation: .extensionIndexing))
        } catch {
            eventDispatcher.dispatch(.phaseOperationFailed(phase: .indexing, operation: .extensionIndexing, error: error))
            throw error
        }

        unifyExtensionContainers()

        try await indexGlobals()

        eventDispatcher.dispatch(.phaseTransition(phase: .indexing, state: .completed))
    }

    private func indexTypes() async throws {
        eventDispatcher.dispatch(.typeIndexingStarted(totalTypes: currentStorage.types.count))
        var currentModuleTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]
        var cImportedCount = 0
        var successfulCount = 0
        var failedCount = 0

        for type in currentStorage.types {
            if let isCImportedContext = try? type.contextDescriptorWrapper.contextDescriptor.isCImportedContextDescriptor(in: machO), !configuration.showCImportedTypes, isCImportedContext {
                cImportedCount += 1
                eventDispatcher.dispatch(.typeProcessingSkippedCImported)
                continue
            }

            do {
                let declaration = try await TypeDefinition(type: type, in: machO)
                currentModuleTypeDefinitions[declaration.typeName] = declaration
                successfulCount += 1
                eventDispatcher.dispatch(.typeProcessed(context: SwiftIndexEvents.TypeContext(typeName: declaration.typeName.name, kind: declaration.typeName.kind)))
            } catch {
                failedCount += 1
                let failedTypeName = try? type.typeName(in: machO)
                eventDispatcher.dispatch(.typeProcessingFailed(typeName: failedTypeName?.name, error: error))
            }
        }

        var nestedTypeCount = 0
        var extensionTypeCount = 0

        // Indexing-local carrier for the resolved-but-unlinked parent context
        // of a nested type (evolution proposal 0002): written by the nesting
        // walk below, read once by the synthetic-extension pass, released when
        // this function returns. It was previously a stored
        // `TypeDefinition.parentContext` property, which retained a second
        // fully-parsed `TypeContextWrapper` on every affected definition for
        // the definition's lifetime with no reader after this function.
        var unlinkedParentContextsByTypeName: [TypeName: UnlinkedParentContext] = [:]

        for type in currentStorage.types {
            guard let typeName = try? type.typeName(in: machO), let childDefinition = currentModuleTypeDefinitions[typeName] else {
                continue
            }

            var resolvedParentName: String?
            var parentContext = try ContextWrapper.type(type).parent(in: machO)

            parentLoop: while let currentContextOrSymbol = parentContext {
                switch currentContextOrSymbol {
                case .symbol(let symbol):
                    unlinkedParentContextsByTypeName[typeName] = .symbol(symbol)
                    break parentLoop
                case .element(let currentContext):
                    if case .type(let typeContext) = currentContext, let parentTypeName = try? typeContext.typeName(in: machO) {
                        if let parentDefinition = currentModuleTypeDefinitions[parentTypeName] {
                            childDefinition.parent = parentDefinition
                            parentDefinition.typeChildren.append(childDefinition)
                            resolvedParentName = parentTypeName.name
                        } else {
                            unlinkedParentContextsByTypeName[typeName] = .type(typeContext)
                            resolvedParentName = parentTypeName.name
                        }
                        nestedTypeCount += 1
                        break parentLoop
                    } else if case .extension(let extensionContext) = currentContext {
                        unlinkedParentContextsByTypeName[typeName] = .extension(extensionContext)
                        extensionTypeCount += 1
                        break parentLoop
                    }
                    parentContext = try currentContext.parent(in: machO)
                }
            }

            eventDispatcher.dispatch(.typeNestingResolved(context: SwiftIndexEvents.TypeNestingContext(childTypeName: typeName.name, parentTypeName: resolvedParentName)))
        }

        var rootTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]

        for (typeName, typeDefinition) in currentModuleTypeDefinitions {
            if typeDefinition.parent == nil, unlinkedParentContextsByTypeName[typeName] == nil {
                rootTypeDefinitions[typeName] = typeDefinition
            } else if let parentContext = unlinkedParentContextsByTypeName[typeName] {
                switch parentContext {
                case .extension(let extensionContext):
                    guard let extendedContextMangledName = extensionContext.extendedContextMangledName else { continue }
                    guard let extensionTypeNode = try MetadataReader.demangleType(for: extendedContextMangledName, in: machO).first(of: .type) else { continue }
                    guard let extensionTypeKind = extensionTypeNode.typeKind else { continue }

                    let extensionTypeName = TypeName(node: InternedNodeReferenceCache.shared.reference(interning: extensionTypeNode, in: machO), kind: extensionTypeKind)

                    var genericSignature: NodeReference?

                    if let currentRequirements = extensionContext.genericContext?.uniqueCurrentRequirements(in: machO), !currentRequirements.isEmpty {
                        genericSignature = try MetadataReader.buildGenericSignature(for: currentRequirements, in: machO).map { InternedNodeReferenceCache.shared.reference(interning: $0, in: machO) }
                    }

                    let extensionDefinition = try ExtensionDefinition(extensionName: extensionTypeName.extensionName, genericSignature: genericSignature, protocolConformance: nil, in: machO)
                    extensionDefinition.types = [typeDefinition]
                    currentStorage.typeExtensionDefinitions[extensionDefinition.extensionName, default: []].append(extensionDefinition)
                case .type(let parentType):
                    let parentTypeName = try parentType.typeName(in: machO)
                    let extensionDefinition = try ExtensionDefinition(extensionName: parentTypeName.extensionName, genericSignature: nil, protocolConformance: nil, in: machO)
                    extensionDefinition.types = [typeDefinition]
                    currentStorage.typeExtensionDefinitions[extensionDefinition.extensionName, default: []].append(extensionDefinition)
                case .symbol(let symbol):
                    guard let type = try MetadataReader.demangleType(for: symbol, in: machO)?.first(of: .type), let kind = type.typeKind else { continue }
                    let parentTypeName = TypeName(node: InternedNodeReferenceCache.shared.reference(interning: type, in: machO), kind: kind)
                    let extensionDefinition = try ExtensionDefinition(extensionName: parentTypeName.extensionName, genericSignature: nil, protocolConformance: nil, in: machO)
                    extensionDefinition.types = [typeDefinition]
                    currentStorage.typeExtensionDefinitions[extensionDefinition.extensionName, default: []].append(extensionDefinition)
                }
            }
        }

        currentStorage.rootTypeDefinitions = rootTypeDefinitions
        currentStorage.allTypeDefinitions = currentModuleTypeDefinitions

        eventDispatcher.dispatch(.typeIndexingCompleted(result: SwiftIndexEvents.TypeIndexingResult(totalProcessed: currentStorage.types.count, successful: successfulCount, failed: failedCount, cImportedSkipped: cImportedCount, nestedTypes: nestedTypeCount, extensionTypes: extensionTypeCount)))
    }

    private func indexProtocols() async throws {
        eventDispatcher.dispatch(.protocolIndexingStarted(totalProtocols: currentStorage.protocols.count))
        var rootProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]
        var allProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]
        var successfulCount = 0
        var failedCount = 0

        for proto in currentStorage.protocols {
            var protocolName: ProtocolName?
            do {
                let protocolDefinition = try ProtocolDefinition(protocol: proto, in: machO)
                protocolName = try proto.protocolName(in: machO)
                if let protocolName {
                    var parentContext = try ContextWrapper.protocol(proto).parent(in: machO)?.resolved
                    var isRoot = true
                    while let currentContext = parentContext {
                        if case .type(let typeContext) = currentContext, let parentTypeName = try? typeContext.typeName(in: machO) {
                            if let parentDefinition = currentStorage.allTypeDefinitions[parentTypeName] {
                                protocolDefinition.parent = parentDefinition
                                parentDefinition.protocolChildren.append(protocolDefinition)
                                isRoot = false
                            }
                            break
                        } else if case .extension(let extensionContext) = currentContext {
                            protocolDefinition.extensionContext = extensionContext
                            isRoot = false
                            break
                        }
                        parentContext = try currentContext.parent(in: machO)?.resolved
                    }
                    allProtocolDefinitions[protocolName] = protocolDefinition
                    if isRoot {
                        rootProtocolDefinitions[protocolName] = protocolDefinition
                    } else if let extensionContext = protocolDefinition.extensionContext, let extendedContextMangledName = extensionContext.extendedContextMangledName {
                        guard let typeNode = try MetadataReader.demangleType(for: extendedContextMangledName, in: machO).first(of: .type) else { continue }
                        guard let typeKind = typeNode.typeKind else { continue }
                        let typeName = TypeName(node: InternedNodeReferenceCache.shared.reference(interning: typeNode, in: machO), kind: typeKind)
                        var genericSignature: NodeReference?
                        if let currentRequirements = extensionContext.genericContext?.uniqueCurrentRequirements(in: machO), !currentRequirements.isEmpty {
                            genericSignature = try MetadataReader.buildGenericSignature(for: currentRequirements, in: machO).map { InternedNodeReferenceCache.shared.reference(interning: $0, in: machO) }
                        }
                        let extensionDefinition = try ExtensionDefinition(extensionName: typeName.extensionName, genericSignature: genericSignature, protocolConformance: nil, in: machO)
                        extensionDefinition.protocols = [protocolDefinition]
                        currentStorage.typeExtensionDefinitions[extensionDefinition.extensionName, default: []].append(extensionDefinition)
                    }

                    successfulCount += 1

                    eventDispatcher.dispatch(.protocolProcessed(context: SwiftIndexEvents.ProtocolContext(protocolName: protocolName.name, requirementCount: proto.requirements.count)))
                } else {
                    failedCount += 1
                }
            } catch {
                eventDispatcher.dispatch(.protocolProcessingFailed(protocolName: protocolName?.name ?? "unknown", error: error))
                failedCount += 1
            }
        }

        currentStorage.rootProtocolDefinitions = rootProtocolDefinitions
        currentStorage.allProtocolDefinitions = allProtocolDefinitions
        eventDispatcher.dispatch(.protocolIndexingCompleted(result: SwiftIndexEvents.ProtocolIndexingResult(totalProcessed: currentStorage.protocols.count, successful: successfulCount, failed: failedCount)))
    }

    private func indexConformances() async throws {
        eventDispatcher.dispatch(.conformanceIndexingStarted(input: SwiftIndexEvents.ConformanceIndexingInput(totalConformances: currentStorage.protocolConformances.count, totalAssociatedTypes: currentStorage.associatedTypes.count)))
        var protocolConformancesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, ProtocolConformance>> = [:]
        var failedConformances = 0

        for conformance in currentStorage.protocolConformances {
            var typeName: TypeName?
            var protocolName: ProtocolName?
            do {
                typeName = try conformance.typeName(in: machO)
                protocolName = try conformance.protocolName(in: machO)
                if let typeName, let protocolName {
                    protocolConformancesByTypeName[typeName, default: [:]][protocolName] = conformance
                    currentStorage.conformingProtocolNamesByTypeName[typeName, default: []].append(protocolName)
                    currentStorage.conformingTypesByProtocolName[protocolName, default: []].append(typeName)
                    eventDispatcher.dispatch(.conformanceFound(context: SwiftIndexEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)))
                } else {
                    eventDispatcher.dispatch(.nameExtractionWarning(for: .protocolConformance))
                    failedConformances += 1
                }
            } catch {
                let context = SwiftIndexEvents.ConformanceContext(typeName: typeName?.name ?? "unknown", protocolName: protocolName?.name ?? "unknown")
                eventDispatcher.dispatch(.conformanceProcessingFailed(context: context, error: error))
                failedConformances += 1
            }
        }

        var associatedTypesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, AssociatedType>> = [:]
        var failedAssociatedTypes = 0

        for associatedType in currentStorage.associatedTypes {
            var typeName: TypeName?
            var protocolName: ProtocolName?
            do {
                typeName = try associatedType.typeName(in: machO)
                protocolName = try associatedType.protocolName(in: machO)

                if let typeName, let protocolName {
                    associatedTypesByTypeName[typeName, default: [:]][protocolName] = associatedType
                    eventDispatcher.dispatch(.associatedTypeFound(context: SwiftIndexEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)))
                } else {
                    eventDispatcher.dispatch(.nameExtractionWarning(for: .associatedType))
                    failedAssociatedTypes += 1
                }
            } catch {
                let context = SwiftIndexEvents.ConformanceContext(typeName: typeName?.name ?? "unknown", protocolName: protocolName?.name ?? "unknown")
                eventDispatcher.dispatch(.associatedTypeProcessingFailed(context: context, error: error))
                failedAssociatedTypes += 1
            }
        }
        var associatedTypesByTypeNameCopy = associatedTypesByTypeName

        var conformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]
        var extensionCount = 0
        var failedExtensions = 0

        for (typeName, protocolConformances) in protocolConformancesByTypeName {
            for (protocolName, protocolConformance) in protocolConformances {
                do {
                    let associatedType = associatedTypesByTypeNameCopy[typeName]?[protocolName]
                    if associatedType != nil {
                        associatedTypesByTypeNameCopy[typeName]?.removeValue(forKey: protocolName)
                        if associatedTypesByTypeNameCopy[typeName]?.isEmpty == true {
                            associatedTypesByTypeNameCopy.removeValue(forKey: typeName)
                        }
                    }

                    let conformanceAssociatedTypes = associatedType.map { [$0] } ?? []
                    let extensionDefinition = try ExtensionDefinition(extensionName: typeName.extensionName, genericSignature: MetadataReader.buildGenericSignature(for: protocolConformance.conditionalRequirements, in: machO).map { InternedNodeReferenceCache.shared.reference(interning: $0, in: machO) }, protocolConformance: protocolConformance, conformingProtocolName: protocolName, associatedTypes: conformanceAssociatedTypes, resolvedAssociatedTypeWitnesses: resolvedWitnessProjections(of: conformanceAssociatedTypes), in: machO)
                    extensionDefinition.isRetroactive = protocolConformance.flags.isRetroactive
                    conformanceExtensionDefinitions[extensionDefinition.extensionName, default: []].append(extensionDefinition)
                    extensionCount += 1
                    eventDispatcher.dispatch(.conformanceExtensionCreated(context: SwiftIndexEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)))
                } catch {
                    let context = SwiftIndexEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)
                    eventDispatcher.dispatch(.conformanceExtensionCreationFailed(context: context, error: error))
                    failedExtensions += 1
                }
            }
        }
        for (remainingTypeName, remainingAssociatedTypeByProtocolName) in associatedTypesByTypeNameCopy {
            for (_, remainingAssociatedType) in remainingAssociatedTypeByProtocolName {
                let extensionDefinition = try ExtensionDefinition(extensionName: remainingTypeName.extensionName, genericSignature: nil, protocolConformance: nil, associatedTypes: [remainingAssociatedType], resolvedAssociatedTypeWitnesses: resolvedWitnessProjections(of: [remainingAssociatedType]), in: machO)
                conformanceExtensionDefinitions[extensionDefinition.extensionName, default: []].append(extensionDefinition)
            }
        }

        // P1-9: Merge typealias-only conformance extensions that share the same extended
        // type. The binary emits one AssociatedType descriptor per protocol requirement,
        // so a type conforming to multiple related protocols (e.g. Sequence + Collection
        // + BidirectionalCollection) ends up with several bare `extension X { typealias
        // ... }` blocks whose entries overlap. A typealias-only extension has no
        // `protocolConformance`, no `genericSignature`, no nested types or protocols — we
        // can safely union their `associatedTypes` into one representative block. Order is
        // preserved by folding successors into the first occurrence.
        var mergedConformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]
        for (extensionName, extensions) in conformanceExtensionDefinitions {
            var primaryTypealiasOnly: ExtensionDefinition? = nil
            var preservedExtensions: [ExtensionDefinition] = []
            for extensionDefinition in extensions {
                let isTypealiasOnly = extensionDefinition.protocolConformanceDescriptor == nil
                    && extensionDefinition.genericSignature == nil
                    && extensionDefinition.types.isEmpty
                    && extensionDefinition.protocols.isEmpty
                if isTypealiasOnly {
                    if let existing = primaryTypealiasOnly {
                        existing.absorbAssociatedTypes(of: extensionDefinition)
                    } else {
                        primaryTypealiasOnly = extensionDefinition
                        preservedExtensions.append(extensionDefinition)
                    }
                } else {
                    preservedExtensions.append(extensionDefinition)
                }
            }
            mergedConformanceExtensionDefinitions[extensionName] = preservedExtensions
        }

        currentStorage.conformanceExtensionDefinitions = mergedConformanceExtensionDefinitions

        // Populate conforming protocol names on each TypeDefinition for attribute inference
        for (typeName, conformances) in protocolConformancesByTypeName {
            if let typeDefinition = currentStorage.allTypeDefinitions[typeName] {
                typeDefinition.conformingProtocolNames = Set(conformances.keys.map(\.name))
            }
        }

        eventDispatcher.dispatch(.conformanceIndexingCompleted(result: SwiftIndexEvents.ConformanceIndexingResult(conformedTypes: protocolConformancesByTypeName.count, associatedTypeCount: associatedTypesByTypeName.count, extensionCount: extensionCount, failedConformances: failedConformances, failedAssociatedTypes: failedAssociatedTypes, failedExtensions: failedExtensions)))
    }

    /// Freezes associated-type witness records into Mach-O-free projections
    /// while the Mach-O is still in hand — the record accessors cannot be
    /// resolved later by the snapshot layer. An unresolvable record is skipped
    /// (same tolerance as the printers' record collection).
    private func resolvedWitnessProjections(of associatedTypes: [AssociatedType]) -> [AssociatedTypeWitnessProjection] {
        var seenNames: Set<String> = []
        var projections: [AssociatedTypeWitnessProjection] = []
        for associatedType in associatedTypes {
            for record in associatedType.records {
                guard let recordName = try? record.name(in: machO),
                      let mangledTypeName = try? record.substitutedTypeName(in: machO),
                      let typeNode = try? MetadataReader.demangleType(for: mangledTypeName, in: machO)
                else { continue }
                guard seenNames.insert(recordName).inserted else { continue }
                projections.append(AssociatedTypeWitnessProjection(name: recordName, substitutedTypeText: typeNode.print(using: .default)))
            }
        }
        return projections
    }

    private func indexExtensions() async throws {
        eventDispatcher.dispatch(.extensionIndexingStarted)

        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        let memberSymbolsByName = await symbolIndexStore.memberSymbols(
            of: .allocator(inExtension: true),
            .variable(inExtension: true, isStatic: false, isStorage: false),
            .variable(inExtension: true, isStatic: true, isStorage: false),
            .variable(inExtension: true, isStatic: true, isStorage: true),
            .function(inExtension: true, isStatic: false),
            .function(inExtension: true, isStatic: true),
            .subscript(inExtension: true, isStatic: false),
            .subscript(inExtension: true, isStatic: true),
            excluding: [],
            in: machO
        )

        var typeExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]
        var protocolExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]
        var typeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]
        var typeExtensionCount = 0
        var protocolExtensionCount = 0
        var typeAliasExtensionCount = 0
        var failedExtensions = 0

        for (typeNodeKey, memberSymbols) in memberSymbolsByName {
            let node = typeNodeKey.reference
            // The async overload (upstream `DemanglingNode.print(using:) async`,
            // present since 0.5.1) suspends the task instead of blocking a
            // cooperative worker when the walk moves to a large-stack thread —
            // restoring the pre-migration `await node.print` semantics.
            let name = await node.print(using: .interfaceTypeBuilderOnly)
            // Node-matched: same-named private types collide on the stripped
            // printed name, and a name-only lookup could answer with the
            // sibling's kind (issue #115's family).
            guard let typeInfo = symbolIndexStore.typeInfo(for: name, node: node, in: machO) else {
                eventDispatcher.dispatch(.extensionTargetNotFound(targetName: name))
                continue
            }

            func extensionDefinition(of kind: ExtensionKind, for memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>, genericSignature: NodeReference?) throws -> ExtensionDefinition {
                let extensionDefinition = try ExtensionDefinition(extensionName: .init(node: node, kind: kind), genericSignature: genericSignature, protocolConformance: nil, in: machO)
                var memberCount = 0

                for (kind, memberSymbols) in memberSymbolsByKind {
                    switch kind {
                    case .allocator(inExtension: true):
                        let allocators = DefinitionBuilder.allocators(for: memberSymbols.mapToDemangledSymbolWithOffset())
                        extensionDefinition.allocators.append(contentsOf: allocators)
                        memberCount += allocators.count
                    case .variable(inExtension: true, isStatic: false, isStorage: false):
                        let variables = DefinitionBuilder.variables(for: memberSymbols.mapToDemangledSymbolWithOffset(), fieldNames: [], isGlobalOrStatic: false)
                        extensionDefinition.variables.append(contentsOf: variables)
                        memberCount += variables.count
                    case .function(inExtension: true, isStatic: false):
                        let functions = DefinitionBuilder.functions(for: memberSymbols.mapToDemangledSymbolWithOffset(), isGlobalOrStatic: false)
                        extensionDefinition.functions.append(contentsOf: functions)
                        memberCount += functions.count
                    case .variable(inExtension: true, isStatic: true, _):
                        let staticVariables = DefinitionBuilder.variables(for: memberSymbols.mapToDemangledSymbolWithOffset(), fieldNames: [], isGlobalOrStatic: true)
                        extensionDefinition.staticVariables.append(contentsOf: staticVariables)
                        memberCount += staticVariables.count
                    case .function(inExtension: true, isStatic: true):
                        let staticFunctions = DefinitionBuilder.functions(for: memberSymbols.mapToDemangledSymbolWithOffset(), isGlobalOrStatic: true)
                        extensionDefinition.staticFunctions.append(contentsOf: staticFunctions)
                        memberCount += staticFunctions.count
                    case .subscript(inExtension: true, isStatic: false):
                        let subscripts = DefinitionBuilder.subscripts(for: memberSymbols.mapToDemangledSymbolWithOffset(), isStatic: false)
                        extensionDefinition.subscripts.append(contentsOf: subscripts)
                        memberCount += subscripts.count
                    case .subscript(inExtension: true, isStatic: true):
                        let staticSubscripts = DefinitionBuilder.subscripts(for: memberSymbols.mapToDemangledSymbolWithOffset(), isStatic: true)
                        extensionDefinition.staticSubscripts.append(contentsOf: staticSubscripts)
                        memberCount += staticSubscripts.count
                    default:
                        break
                    }
                }

                extensionDefinition.orderedMembers = OrderedMember.offsetOrdered(OrderedMember.allMembers(from: extensionDefinition))

                eventDispatcher.dispatch(.extensionCreated(context: SwiftIndexEvents.ExtensionContext(targetName: name, memberCount: memberCount)))
                return extensionDefinition
            }

            var memberSymbolsByGenericSignature: OrderedDictionary<NodeReference, OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>> = [:]
            var memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]> = [:]

            for (kind, memberSymbols) in memberSymbols {
                for memberSymbol in memberSymbols {
                    // Variables cannot carry a member-level `where` clause the
                    // way functions and subscripts can, so a constrained
                    // extension variable needs its own `extension … where …`
                    // block, keyed by signature. A signature none of whose
                    // children are requirement kinds would render a bare
                    // header visually identical to the catch-all block
                    // (evolution proposal 0007) — those fold into the
                    // catch-all instead of fragmenting.
                    if let genericSignature = memberSymbol.demangledNode.first(of: .dependentGenericSignature), case .variable = kind, !genericSignature.all(of: .requirementKinds).isEmpty {
                        memberSymbolsByGenericSignature[genericSignature, default: [:]][kind, default: []].append(memberSymbol)
                    } else {
                        memberSymbolsByKind[kind, default: []].append(memberSymbol)
                    }
                }
            }

            do {
                if let typeKind = typeInfo.kind.typeKind {
                    let extensionName = ExtensionName(node: node, kind: .type(typeKind))

                    for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                        try typeExtensionDefinitions[extensionName, default: []].append(extensionDefinition(of: .type(typeKind), for: memberSymbolsByKind, genericSignature: node))
                        typeExtensionCount += 1
                    }
                    if !memberSymbolsByKind.isEmpty {
                        try typeExtensionDefinitions[extensionName, default: []].append(extensionDefinition(of: .type(typeKind), for: memberSymbolsByKind, genericSignature: nil))
                        typeExtensionCount += 1
                    }

                } else if typeInfo.kind == .protocol {
                    let extensionName = ExtensionName(node: node, kind: .protocol)

                    for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                        try protocolExtensionDefinitions[extensionName, default: []].append(extensionDefinition(of: .protocol, for: memberSymbolsByKind, genericSignature: node))
                        protocolExtensionCount += 1
                    }
                    if !memberSymbolsByKind.isEmpty {
                        try protocolExtensionDefinitions[extensionName, default: []].append(extensionDefinition(of: .protocol, for: memberSymbolsByKind, genericSignature: nil))
                        protocolExtensionCount += 1
                    }
                } else {
                    let extensionName = ExtensionName(node: node, kind: .typeAlias)

                    for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                        try typeAliasExtensionDefinitions[extensionName, default: []].append(extensionDefinition(of: .typeAlias, for: memberSymbolsByKind, genericSignature: node))
                        typeAliasExtensionCount += 1
                    }
                    if !memberSymbolsByKind.isEmpty {
                        try typeAliasExtensionDefinitions[extensionName, default: []].append(extensionDefinition(of: .typeAlias, for: memberSymbolsByKind, genericSignature: nil))
                        typeAliasExtensionCount += 1
                    }
                }
            } catch {
                eventDispatcher.dispatch(.extensionCreationFailed(targetName: name, error: error))
                failedExtensions += 1
            }
        }

        for (extensionName, typeExtensionDefinition) in typeExtensionDefinitions {
            currentStorage.typeExtensionDefinitions[extensionName, default: []].append(contentsOf: typeExtensionDefinition)
        }

        for (extensionName, protocolExtensionDefinition) in protocolExtensionDefinitions {
            currentStorage.protocolExtensionDefinitions[extensionName, default: []].append(contentsOf: protocolExtensionDefinition)
        }

        currentStorage.typeAliasExtensionDefinitions = typeAliasExtensionDefinitions

        eventDispatcher.dispatch(.extensionIndexingCompleted(result: SwiftIndexEvents.ExtensionIndexingResult(typeExtensions: typeExtensionCount, protocolExtensions: protocolExtensionCount, typeAliasExtensions: typeAliasExtensionCount, failed: failedExtensions)))
    }

    private func indexGlobals() async throws {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        currentStorage.globalVariableDefinitions = DefinitionBuilder.variables(for: symbolIndexStore.globalSymbols(of: .variable(isStorage: false), .variable(isStorage: true), in: machO).mapToDemangledSymbolWithOffset(), fieldNames: [], isGlobalOrStatic: true)
        currentStorage.globalFunctionDefinitions = DefinitionBuilder.functions(for: symbolIndexStore.globalSymbols(of: .function, in: machO).mapToDemangledSymbolWithOffset(), isGlobalOrStatic: true)
    }

    // MARK: - Extension container unification (evolution proposal 0007)

    /// The (protocol, where-clause, retroactive) identity that decides whether
    /// two definitions filed under one `ExtensionName` are the same source
    /// container. Structurally keyed: the definitions' nodes may come from
    /// different stores (the interned image store vs `MetadataReader` minis),
    /// where store-identity equality never matches.
    private struct ExtensionContainerIdentity: Hashable {
        let protocolNodeKey: StructuralNodeReferenceKey?
        let genericSignatureKey: StructuralNodeReferenceKey?
        let isRetroactive: Bool
    }

    /// Container unification, in two moves:
    ///
    /// 1. **Same-identity merge.** Within each bucket entry, definitions
    ///    sharing one `ExtensionContainerIdentity` are one source container
    ///    that different producers discovered separately (the nested-type
    ///    discovery and the member-symbol scan both file signature-less
    ///    blocks under the same name) — they merge into the first. Eager
    ///    definitions only: a conformance-backed definition resolves its
    ///    members lazily at print time, so merging one away here would lose
    ///    them silently.
    /// 2. **Protocol attachment.** A protocol's symbol-scan extension blocks
    ///    attach to `ProtocolDefinition.defaultImplementationExtensions`, so
    ///    the interface renders them trailing the protocol declaration — the
    ///    symbol scan is a superset of what the descriptor's per-requirement
    ///    default-implementation walk resolves (identical-code-folded
    ///    addresses lose members there), which is why the trailing copy used
    ///    to render FEWER members than the extensions-block copy of the same
    ///    block. The double emission collapses because the top-level printer
    ///    skips attached definitions; the definitions deliberately STAY in
    ///    the bucket — the ABI-diff layer snapshots containers from the
    ///    buckets, and removing them would drop the containers from
    ///    snapshots (the differ already groups same-key containers, so the
    ///    in-bucket merge does not change snapshot content either).
    private func unifyExtensionContainers() {
        currentStorage.typeExtensionDefinitions = mergingSameIdentityContainers(currentStorage.typeExtensionDefinitions)
        currentStorage.protocolExtensionDefinitions = mergingSameIdentityContainers(currentStorage.protocolExtensionDefinitions)
        currentStorage.typeAliasExtensionDefinitions = mergingSameIdentityContainers(currentStorage.typeAliasExtensionDefinitions)
        currentStorage.conformanceExtensionDefinitions = mergingSameIdentityContainers(currentStorage.conformanceExtensionDefinitions)

        // Keyed on `ExtensionName` — whose `Hashable` is STRUCTURAL over the
        // name node — not on the printed `.name` string: `.name` is printed
        // with `interfaceTypeBuilderOnly`, which strips private
        // discriminators, so two same-named `private protocol`s collapse onto
        // one key. Under a string key the map was last-wins and the
        // attachment below is an ASSIGNMENT, so the loser's whole bucket was
        // first flagged `isAttachedToProtocolDefinition` (which removes it
        // from the top-level extensions block) and then overwritten out of
        // `defaultImplementationExtensions` — its members vanished from the
        // output entirely, and which bucket lost depended on iteration order
        // (issue #115's family). `allProtocolDefinitions` already keys on the
        // structurally-hashed `ProtocolName`, so the two declarations are
        // distinct there; only this lookup table flattened them.
        var protocolDefinitionsByName: [ExtensionName: ProtocolDefinition] = [:]
        for (protocolName, protocolDefinition) in currentStorage.allProtocolDefinitions {
            protocolDefinitionsByName[protocolName.extensionName] = protocolDefinition
        }
        for (extensionName, definitions) in currentStorage.protocolExtensionDefinitions {
            guard let protocolDefinition = protocolDefinitionsByName[extensionName] else { continue }
            for definition in definitions {
                definition.isAttachedToProtocolDefinition = true
            }
            protocolDefinition.defaultImplementationExtensions = definitions
        }
    }

    private func mergingSameIdentityContainers(_ buckets: OrderedDictionary<ExtensionName, [ExtensionDefinition]>) -> OrderedDictionary<ExtensionName, [ExtensionDefinition]> {
        var result: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]
        for (extensionName, definitions) in buckets {
            var primaryByIdentity: [ExtensionContainerIdentity: ExtensionDefinition] = [:]
            var preservedDefinitions: [ExtensionDefinition] = []
            for definition in definitions {
                // Conformance-backed definitions resolve members lazily at
                // print time — merging one away here would lose them. Same-
                // identity conformance duplicates would mean duplicated
                // conformance records, which do not occur in practice.
                guard definition.protocolConformanceDescriptor == nil else {
                    preservedDefinitions.append(definition)
                    continue
                }
                let identity = ExtensionContainerIdentity(
                    protocolNodeKey: definition.conformingProtocolName.map { StructuralNodeReferenceKey($0.node) },
                    genericSignatureKey: definition.genericSignature.map { StructuralNodeReferenceKey($0) },
                    isRetroactive: definition.isRetroactive
                )
                if let primaryDefinition = primaryByIdentity[identity] {
                    primaryDefinition.absorbMembers(of: definition)
                } else {
                    primaryByIdentity[identity] = definition
                    preservedDefinitions.append(definition)
                }
            }
            result[extensionName] = preservedDefinitions
        }
        return result
    }
}

// MARK: - Current Storage Property Mappings

extension SwiftDeclarationIndexer {
    // The section-wrapper populations (`types` / `protocols` /
    // `protocolConformances` / `associatedTypes`) and the parsed-value keyed
    // maps that used to be projected here are indexing transients since
    // evolution proposal 0002 — released when `prepare()` finishes, so they
    // no longer have a public projection. The name-level maps below are the
    // retained conformance facts.

    @inlinable
    public var conformingProtocolNamesByTypeName: OrderedDictionary<TypeName, OrderedSet<ProtocolName>> { currentStorage.conformingProtocolNamesByTypeName }

    @inlinable
    public var conformingTypesByProtocolName: OrderedDictionary<ProtocolName, OrderedSet<TypeName>> { currentStorage.conformingTypesByProtocolName }

    @inlinable
    public var rootTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> { currentStorage.rootTypeDefinitions }

    @inlinable
    public var allTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> { currentStorage.allTypeDefinitions }

    @inlinable
    public var rootProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> { currentStorage.rootProtocolDefinitions }

    @inlinable
    public var allProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> { currentStorage.allProtocolDefinitions }

    @inlinable
    public var typeExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { currentStorage.typeExtensionDefinitions }

    @inlinable
    public var protocolExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { currentStorage.protocolExtensionDefinitions }

    @inlinable
    public var typeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { currentStorage.typeAliasExtensionDefinitions }

    @inlinable
    public var conformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { currentStorage.conformanceExtensionDefinitions }

    @inlinable
    public var globalVariableDefinitions: [VariableDefinition] { currentStorage.globalVariableDefinitions }

    @inlinable
    public var globalFunctionDefinitions: [FunctionDefinition] { currentStorage.globalFunctionDefinitions }
}

// MARK: - All Storage Property Mappings (Current + SubIndexers)

// The merged "all*" aggregates fan out across the entire sub-indexer tree, which
// makes them expensive to recompute. They were the dominant O(n²) hotspot in
// callers that read these properties inside per-type loops. We memoize them on
// the indexer; the cache is invalidated whenever `prepare()`, `addSubIndexer`,
// or `removeSubIndexer` runs. After `prepare()` the indexer is treated as
// effectively read-only — modifying a sub-indexer in place after a parent has
// populated its cache will not propagate, so reorganize hierarchies before the
// first read.
extension SwiftDeclarationIndexer {
    public var allConformingProtocolNamesByTypeName: OrderedDictionary<TypeName, OrderedSet<ProtocolName>> {
        if let cached = allStorageCache.allConformingProtocolNamesByTypeName { return cached }
        var result = currentStorage.conformingProtocolNamesByTypeName
        for subIndexer in subIndexers {
            for (typeName, protocolNames) in subIndexer.allConformingProtocolNamesByTypeName {
                result[typeName, default: []].formUnion(protocolNames)
            }
        }
        allStorageCache.allConformingProtocolNamesByTypeName = result
        return result
    }

    public var allConformingTypesByProtocolName: OrderedDictionary<ProtocolName, OrderedSet<MachOIndexedValue<MachO, TypeName>>> {
        if let cached = allStorageCache.allConformingTypesByProtocolName { return cached }
        var result: OrderedDictionary<ProtocolName, OrderedSet<MachOIndexedValue<MachO, TypeName>>> = [:]
        for (protocolName, typeNames) in currentStorage.conformingTypesByProtocolName {
            result[protocolName] = OrderedSet(typeNames.map { .init(machO: machO, value: $0) })
        }
        for subIndexer in subIndexers {
            for (protocolName, typeNames) in subIndexer.allConformingTypesByProtocolName {
                result[protocolName, default: []].formUnion(typeNames)
            }
        }
        allStorageCache.allConformingTypesByProtocolName = result
        return result
    }

    public var allRootTypeDefinitions: OrderedDictionary<TypeName, MachOIndexedValue<MachO, TypeDefinition>> {
        if let cached = allStorageCache.allRootTypeDefinitions { return cached }
        var result = currentStorage.rootTypeDefinitions.mapValues { MachOIndexedValue(machO: machO, value: $0) }
        for subIndexer in subIndexers {
            result.merge(subIndexer.allRootTypeDefinitions) { current, _ in current }
        }
        allStorageCache.allRootTypeDefinitions = result
        return result
    }

    public var allAllTypeDefinitions: OrderedDictionary<TypeName, MachOIndexedValue<MachO, TypeDefinition>> {
        if let cached = allStorageCache.allAllTypeDefinitions { return cached }
        var result = currentStorage.allTypeDefinitions.mapValues { MachOIndexedValue(machO: machO, value: $0) }
        for subIndexer in subIndexers {
            result.merge(subIndexer.allAllTypeDefinitions) { current, _ in current }
        }
        allStorageCache.allAllTypeDefinitions = result
        return result
    }

    public var allRootProtocolDefinitions: OrderedDictionary<ProtocolName, MachOIndexedValue<MachO, ProtocolDefinition>> {
        if let cached = allStorageCache.allRootProtocolDefinitions { return cached }
        var result = currentStorage.rootProtocolDefinitions.mapValues { MachOIndexedValue(machO: machO, value: $0) }
        for subIndexer in subIndexers {
            result.merge(subIndexer.allRootProtocolDefinitions) { current, _ in current }
        }
        allStorageCache.allRootProtocolDefinitions = result
        return result
    }

    public var allAllProtocolDefinitions: OrderedDictionary<ProtocolName, MachOIndexedValue<MachO, ProtocolDefinition>> {
        if let cached = allStorageCache.allAllProtocolDefinitions { return cached }
        var result = currentStorage.allProtocolDefinitions.mapValues { MachOIndexedValue(machO: machO, value: $0) }
        for subIndexer in subIndexers {
            result.merge(subIndexer.allAllProtocolDefinitions) { prevValue, nextValue in prevValue }
        }
        allStorageCache.allAllProtocolDefinitions = result
        return result
    }

    public var allTypeExtensionDefinitions: OrderedDictionary<ExtensionName, [MachOIndexedValue<MachO, ExtensionDefinition>]> {
        if let cached = allStorageCache.allTypeExtensionDefinitions { return cached }
        var result: OrderedDictionary<ExtensionName, [MachOIndexedValue<MachO, ExtensionDefinition>]> = currentStorage.typeExtensionDefinitions.mapValues { $0.map { .init(machO: machO, value: $0) } }
        for subIndexer in subIndexers {
            for (extensionName, definitions) in subIndexer.allTypeExtensionDefinitions {
                result[extensionName, default: []].append(contentsOf: definitions)
            }
        }
        allStorageCache.allTypeExtensionDefinitions = result
        return result
    }

    public var allProtocolExtensionDefinitions: OrderedDictionary<ExtensionName, [MachOIndexedValue<MachO, ExtensionDefinition>]> {
        if let cached = allStorageCache.allProtocolExtensionDefinitions { return cached }
        var result: OrderedDictionary<ExtensionName, [MachOIndexedValue<MachO, ExtensionDefinition>]> = currentStorage.protocolExtensionDefinitions.mapValues { $0.map { .init(machO: machO, value: $0) } }
        for subIndexer in subIndexers {
            for (extensionName, definitions) in subIndexer.allProtocolExtensionDefinitions {
                result[extensionName, default: []].append(contentsOf: definitions)
            }
        }
        allStorageCache.allProtocolExtensionDefinitions = result
        return result
    }

    public var allTypeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [MachOIndexedValue<MachO, ExtensionDefinition>]> {
        if let cached = allStorageCache.allTypeAliasExtensionDefinitions { return cached }
        var result: OrderedDictionary<ExtensionName, [MachOIndexedValue<MachO, ExtensionDefinition>]> = currentStorage.typeAliasExtensionDefinitions.mapValues { $0.map { .init(machO: machO, value: $0) } }
        for subIndexer in subIndexers {
            for (extensionName, definitions) in subIndexer.allTypeAliasExtensionDefinitions {
                result[extensionName, default: []].append(contentsOf: definitions)
            }
        }
        allStorageCache.allTypeAliasExtensionDefinitions = result
        return result
    }

    public var allConformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [MachOIndexedValue<MachO, ExtensionDefinition>]> {
        if let cached = allStorageCache.allConformanceExtensionDefinitions { return cached }
        var result: OrderedDictionary<ExtensionName, [MachOIndexedValue<MachO, ExtensionDefinition>]> = currentStorage.conformanceExtensionDefinitions.mapValues { $0.map { .init(machO: machO, value: $0) } }
        for subIndexer in subIndexers {
            for (extensionName, definitions) in subIndexer.allConformanceExtensionDefinitions {
                result[extensionName, default: []].append(contentsOf: definitions)
            }
        }
        allStorageCache.allConformanceExtensionDefinitions = result
        return result
    }

    public var allGlobalVariableDefinitions: [MachOIndexedValue<MachO, VariableDefinition>] {
        if let cached = allStorageCache.allGlobalVariableDefinitions { return cached }
        let result = currentStorage.globalVariableDefinitions.map { MachOIndexedValue(machO: machO, value: $0) } + subIndexers.flatMap { $0.allGlobalVariableDefinitions }
        allStorageCache.allGlobalVariableDefinitions = result
        return result
    }

    public var allGlobalFunctionDefinitions: [MachOIndexedValue<MachO, FunctionDefinition>] {
        if let cached = allStorageCache.allGlobalFunctionDefinitions { return cached }
        let result = currentStorage.globalFunctionDefinitions.map { MachOIndexedValue(machO: machO, value: $0) } + subIndexers.flatMap { $0.allGlobalFunctionDefinitions }
        allStorageCache.allGlobalFunctionDefinitions = result
        return result
    }
}

// MARK: - Statistics

// Answered from the `PreparationStatistics` snapshot frozen at the end of
// `prepare()` — the backing arrays are indexing transients released there
// (evolution proposal 0002), so reading them directly would return 0 for
// the accessors' whole useful lifetime.
extension SwiftDeclarationIndexer {
    @inlinable
    public var numberOfTypes: Int { currentStorage.preparationStatistics.numberOfTypes }

    @inlinable
    public var numberOfEnums: Int { currentStorage.preparationStatistics.numberOfEnums }

    @inlinable
    public var numberOfStructs: Int { currentStorage.preparationStatistics.numberOfStructs }

    @inlinable
    public var numberOfClasses: Int { currentStorage.preparationStatistics.numberOfClasses }

    @inlinable
    public var numberOfProtocols: Int { currentStorage.preparationStatistics.numberOfProtocols }

    @inlinable
    public var numberOfProtocolConformances: Int { currentStorage.preparationStatistics.numberOfProtocolConformances }
}

// MARK: - Per-Image Cache Eviction Coordination

/// Process-wide coordination for the per-image cache cleanup in the
/// indexer's `deinit` (PR #103 review, finding M6).
///
/// Eviction ownership is claimed per IMAGE — by whichever indexer's
/// `prepare()` found the symbol-store entry absent and therefore built it —
/// while the eviction itself is deferred to the image's LAST live indexer.
/// An owner deinitializing earlier must not wipe the three per-image caches
/// (symbol store, interned-name store, demangle memo) out from under a
/// still-live sibling: the survivor's already-built names would keep an
/// orphaned store alive while new names land in a fresh one, splitting the
/// `store ===` fast paths for the rest of its lifetime. Entries built by
/// non-indexer callers are never claimed and therefore never evicted here —
/// the pre-existing contract, now enforced per image instead of per
/// indexer.
private enum PerImageCacheEvictionRegistry {
    /// Which of the three per-image caches this image's indexers are entitled
    /// to evict.
    ///
    /// Claimed PER CACHE rather than once for all three: the symbol store is
    /// the only one an indexer's `prepare()` necessarily builds. The
    /// interned-name store and the `MetadataReader` demangle memo are also
    /// populated by SwiftLayout, `SwiftDeclarationRendering` and
    /// `SwiftSpecialization` — a "dump the image, then build its interface"
    /// sequence fills both without ever touching the symbol store. Under a
    /// single combined claim that sequence either evicts caches from under
    /// live non-indexer work (claim taken) or leaks all three (claim refused);
    /// per-cache claims give the right answer in both directions.
    struct Claims {
        var symbolStore: Bool = false
        var internedNames: Bool = false
        var demangleMemo: Bool = false

        static let none = Claims()

        mutating func formUnion(_ other: Claims) {
            symbolStore = symbolStore || other.symbolStore
            internedNames = internedNames || other.internedNames
            demangleMemo = demangleMemo || other.demangleMemo
        }

        /// Pairs the two claims that cannot be honoured independently.
        ///
        /// The demangle memo's values are `NodeReference`s into the interned
        /// store, and a surviving reference keeps that store's buffers alive —
        /// `InternedNodeReferenceCache`'s own documentation states it: "Eviction
        /// reclaims nothing while external references survive." So dropping the
        /// store while keeping the memo frees nothing at all, which is the exact
        /// inverse of what the eviction exists to do.
        ///
        /// One-way on purpose. Dropping the memo does not require dropping the
        /// store (other holders may legitimately remain); dropping the store
        /// does require dropping the memo. Both caches are keyed per image, so
        /// this pairs one image's two halves and nothing wider.
        ///
        /// This restores a binding that existed before the claims were split per
        /// cache: the three used to be evicted together, and the comment
        /// explaining why the memo must follow the store outlived the code that
        /// made it true.
        var normalized: Claims {
            var result = self
            if result.internedNames {
                result.demangleMemo = true
            }
            return result
        }
    }

    private struct ImageEntry {
        /// Identity-keyed rather than counted: registration is idempotent per
        /// indexer, so a double `prepare()` cannot inflate the population and
        /// strand the entry above zero forever (which would leak all three
        /// caches for the process lifetime). `prepare()`'s `isPrepared` guard
        /// is a plain check-then-set on an async entry point, so a concurrent
        /// second call genuinely reaches the registration.
        var liveIndexers: Set<ObjectIdentifier> = []
        var claims: Claims = .none
    }

    private static let registryLock = NSLock()

    private nonisolated(unsafe) static var entriesByImageIdentifier: [AnyHashable: ImageEntry] = [:]

    /// - Parameter sampleClaims: Tests cache membership. Taken as a closure so
    ///   it runs **under the lock**, in the same critical section as the
    ///   registration it decides. Passed as an already-computed `Claims` it was
    ///   evaluated at the call site, before the lock: a sibling's `deinit`
    ///   landing in that window let this indexer observe the caches as present,
    ///   claim nothing, register into an entry the sibling then removed, rebuild
    ///   all three, and hold no claim to evict them — leaking a symbol store
    ///   (185,988 rows on SwiftUI) plus its arena for the process lifetime.
    static func registerLiveIndexer(
        _ indexerIdentity: ObjectIdentifier,
        forImageIdentifier imageIdentifier: AnyHashable,
        samplingClaims sampleClaims: () -> Claims
    ) {
        registryLock.lock()
        defer { registryLock.unlock() }
        var imageEntry = entriesByImageIdentifier[imageIdentifier, default: ImageEntry()]
        let isFirstRegistration = imageEntry.liveIndexers.insert(indexerIdentity).inserted
        // Only a first registration contributes claims: a re-entrant
        // `prepare()` samples the caches its own earlier pass just built and
        // would otherwise answer "nobody had this, so I claim it" backwards.
        if isFirstRegistration {
            imageEntry.claims.formUnion(sampleClaims())
        }
        entriesByImageIdentifier[imageIdentifier] = imageEntry
    }

    /// Deregisters, and — only if this was the image's LAST live indexer, so a
    /// shared entry never disappears under a live sibling — evicts.
    ///
    /// - Parameter evict: Runs **under the lock**, in the same critical section
    ///   as the deregistration. Returning the claims and evicting afterwards
    ///   left a second window beyond the one `registerLiveIndexer` closes:
    ///   between this indexer leaving the lock and the caches actually going, a
    ///   sibling samples them as still present and claims nothing. Closing only
    ///   the sampling side would have moved the race rather than removed it.
    ///
    ///   Calling out under the lock is safe here because none of the three
    ///   evictions re-enters this registry; `registryLock` is a plain `NSLock`
    ///   and would deadlock if one ever did.
    static func deregisterLiveIndexer(
        _ indexerIdentity: ObjectIdentifier,
        forImageIdentifier imageIdentifier: AnyHashable,
        evicting evict: (Claims) -> Void
    ) {
        registryLock.lock()
        defer { registryLock.unlock() }
        guard var imageEntry = entriesByImageIdentifier[imageIdentifier] else { return }
        imageEntry.liveIndexers.remove(indexerIdentity)
        guard imageEntry.liveIndexers.isEmpty else {
            entriesByImageIdentifier[imageIdentifier] = imageEntry
            return
        }
        entriesByImageIdentifier.removeValue(forKey: imageIdentifier)
        evict(imageEntry.claims.normalized)
    }
}
