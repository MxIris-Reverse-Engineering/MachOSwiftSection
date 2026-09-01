import Foundation
import SwiftDeclaration
import SwiftAttributeInference
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDeclarationRendering
import Demangling
import Semantic
import SwiftStdlibToolbox
import MachOKit
import Dependencies
import Utilities
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches
@_spi(Internals) import SwiftInspection

@_spi(Support)
public final class SwiftDeclarationPrinter<MachO: FieldLayoutRenderable>: Sendable {
    public let machO: MachO

    @Mutex
    public private(set) var configuration: SwiftDeclarationPrintConfiguration = .init()

    /// Resolvers binned per role at registration time (`addTypeNameResolver`),
    /// so each delegate query walks only the resolvers that can answer it and
    /// the print path never runs a conformance cast.
    private struct TypeNameResolverRegistry: Sendable {
        var moduleNameResolvers: [any ModuleNameResolving] = []
        var cImportedNameResolvers: [any CImportedNameResolving] = []
        var opaqueTypeResolvers: [any OpaqueTypeResolving] = []
    }

    @Mutex
    private var typeNameResolverRegistry: TypeNameResolverRegistry = .init()

    /// `package` so in-package renderers that drive this printer — notably
    /// ``SwiftDiffableInterfaceRenderer`` — report their own degradations into
    /// the same sinks rather than inventing a second reporting channel.
    ///
    /// Injectable for the same reason: a renderer that already owns an indexer's
    /// dispatcher passes it straight in, so one set of handlers covers indexing
    /// and printing alike.
    package let eventDispatcher: SwiftIndexEvents.Dispatcher

    @Mutex
    var typeDemangleResolver: DemangleResolver = .using(options: .default)

    /// Memoized static field-layout provider for the offline (`MachOFile`) path,
    /// built once on first use — only when the reader is a `MachOFile` and a
    /// layout-bearing flag is on. `.computed(nil)` records "no provider", so the
    /// (relatively expensive) dependency-closure build is attempted at most once.
    @Mutex
    private var memoizedStaticFieldLayoutProvider: StaticFieldLayoutProviderState = .uncomputed

    private enum StaticFieldLayoutProviderState: Sendable {
        case uncomputed
        case computed((any StaticFieldLayoutProvider)?)
    }

    /// Builds (once) and returns the offline field-layout provider for the
    /// current configuration, or `nil` for the in-process (`MachOImage`) path or
    /// when no layout-bearing flag is set.
    ///
    /// Fast path reads the synthesized `@Mutex` getter (one `withLock`); when the
    /// state is still `.uncomputed`, the slow path takes the underlying `Mutex`
    /// directly via `_memoizedStaticFieldLayoutProvider.withLock` and runs a
    /// double-checked compute-and-install inside one critical section, so the
    /// (relatively expensive) dependency-closure build cannot race or duplicate
    /// even when the printer is shared across concurrent renders.
    func staticFieldLayoutProvider() -> (any StaticFieldLayoutProvider)? {
        if case .computed(let provider) = memoizedStaticFieldLayoutProvider {
            return provider
        }
        let configurationSnapshot = self.configuration
        return _memoizedStaticFieldLayoutProvider.withLock { state in
            if case .computed(let provider) = state {
                return provider
            }
            let provider: (any StaticFieldLayoutProvider)?
            if configurationSnapshot.printFieldOffset || configurationSnapshot.printTypeLayout || configurationSnapshot.printEnumLayout || configurationSnapshot.printExpandedFieldOffsets {
                // Reader-type-dispatched (no runtime cast): only `MachOFile` builds a
                // provider; `MachOImage` returns nil.
                provider = MachO.makeStaticFieldLayoutProvider(machO: machO, resolution: configurationSnapshot.staticLayoutDependencyResolution)
            } else {
                provider = nil
            }
            state = .computed(provider)
            return provider
        }
    }

    public init(configuration: SwiftDeclarationPrintConfiguration = .init(), eventHandlers: [SwiftIndexEvents.Handler] = [], in machO: MachO) {
        self.machO = machO
        // Before `configuration`: that property is `@Mutex`-wrapped with a
        // default, so assigning it counts as using `self`, which is only legal
        // once every stored property is initialized.
        self.eventDispatcher = .init()
        self.configuration = configuration
        eventDispatcher.addHandlers(eventHandlers)
        self.typeDemangleResolver = .using { [weak self] node in
            if let self {
                var printer = TypeNodePrinter(delegate: self)
                try await printer.printRoot(node)
            }
        }
    }

    /// Builds a printer that reports into an existing dispatcher.
    ///
    /// For a caller that already owns one — ``SwiftDiffableInterfaceRenderer``
    /// shares its indexer's — so indexing and printing land in one set of sinks
    /// and the host attaches handlers once. `Handler` is not `Sendable`, so
    /// passing the dispatcher is also the only way to carry sinks across a
    /// `Sendable` boundary.
    package init(configuration: SwiftDeclarationPrintConfiguration = .init(), eventDispatcher: SwiftIndexEvents.Dispatcher, in machO: MachO) {
        self.machO = machO
        self.eventDispatcher = eventDispatcher
        self.configuration = configuration
        self.typeDemangleResolver = .using { [weak self] node in
            if let self {
                var printer = TypeNodePrinter(delegate: self)
                try await printer.printRoot(node)
            }
        }
    }

    public func updateConfiguration(_ configuration: SwiftDeclarationPrintConfiguration) {
        self.configuration = configuration
        // The memoized provider was built against the previous configuration's
        // layout flags + dependency resolution. Reset it so the next
        // `staticFieldLayoutProvider()` call rebuilds against the new one.
        _memoizedStaticFieldLayoutProvider.withLock { $0 = .uncomputed }
    }

    public func addTypeNameResolver(_ resolver: any TypeNameResolving) {
        _typeNameResolverRegistry.withLock { registry in
            var matchedAnyRole = false
            if let moduleNameResolver = resolver as? any ModuleNameResolving {
                registry.moduleNameResolvers.append(moduleNameResolver)
                matchedAnyRole = true
            }
            if let cImportedNameResolver = resolver as? any CImportedNameResolving {
                registry.cImportedNameResolvers.append(cImportedNameResolver)
                matchedAnyRole = true
            }
            if let opaqueTypeResolver = resolver as? any OpaqueTypeResolving {
                registry.opaqueTypeResolvers.append(opaqueTypeResolver)
                matchedAnyRole = true
            }
            assert(matchedAnyRole, "resolver conforms to no role protocol and would never be consulted")
        }
    }

    public func removeAllTypeNameResolvers() {
        typeNameResolverRegistry = .init()
    }

    @SemanticStringBuilder
    public func printTypeDefinition(_ typeDefinition: TypeDefinition, level: Int = 1, displayParentName: Bool = false) async throws -> SemanticString {
        let printingContext = SwiftIndexEvents.PrintingContext(name: typeDefinition.typeName.name, kind: .type)
        eventDispatcher.dispatch(.definitionPrintStarted(context: printingContext))

        if !typeDefinition.isIndexed {
            try await typeDefinition.index(in: machO)
        }

        // Infer type-level attributes
        let typeAttributeInferrer = TypeAttributeInferrer()
        typeDefinition.attributes = typeAttributeInferrer.infer(for: typeDefinition)

        // Emit type-level attributes, each on its own line before the declaration
        for attribute in typeDefinition.attributes {
            Indent(level: level - 1)
            Keyword(attribute.keyword)
            BreakLine()
        }

        // Specialized definitions carry the runtime-resolved metadata; the
        // header renderer uses it to print the bound generic name
        // (`Box<Int>`, not `Box<A> where …`) — the same substitution the
        // dump path performs via `TypedDumper.boundDumpedTypeNode()`.
        let specializedMetadata: MetadataWrapper? = typeDefinition.isSpecialized ? typeDefinition.metadata : nil

        // This print operation's single wrapper materialization (proposal
        // 0002), threaded into the header and field renderers below.
        let materializedTypeContext = try typeDefinition.materializedTypeContext(in: machO)

        try await DeclarationBlock(level: level) {
            try await renderTypeDeclarationHeader(for: materializedTypeContext, displayParentName: displayParentName, level: level, specializedMetadata: specializedMetadata)
        } body: {
            // Per-CHILD catch: one nested child whose printing throws drops
            // only itself — the same per-definition contract `printRoot`
            // applies at the top level, pushed into the nested loops. A
            // child's throw once escaped here and the top-level catch
            // discarded the whole enclosing type.
            for child in typeDefinition.typeChildren {
                if let renderedChild = await printCatchedThrowing(
                    dispatchingTo: eventDispatcher,
                    context: .init(name: child.typeName.name, kind: .type),
                    {
                        try await NestedDeclaration {
                            try await printTypeDefinition(child, level: level + 1)
                        }
                    }
                ) {
                    renderedChild
                }
            }

            for child in typeDefinition.protocolChildren {
                if let renderedChild = await printCatchedThrowing(
                    dispatchingTo: eventDispatcher,
                    context: .init(name: child.protocolName.name, kind: .protocol),
                    {
                        try await NestedDeclaration {
                            try await printProtocolDefinition(child, level: level + 1)
                        }
                    }
                ) {
                    renderedChild
                }
            }

            try await renderModelFields(typeDefinition, typeContext: materializedTypeContext, level: level)

            try await printDefinition(typeDefinition, level: level)
        }

        eventDispatcher.dispatch(.definitionPrintCompleted(context: printingContext))
    }

    @SemanticStringBuilder
    public func printProtocolDefinition(_ protocolDefinition: ProtocolDefinition, level: Int = 1, displayParentName: Bool = false) async throws -> SemanticString {
        // Context and start event FIRST, exactly like `printTypeDefinition`.
        // The materialization below throws (proposal 0002 rebuilt the wrapper
        // from its descriptor), and a failure that precedes the start event
        // makes the caller's catch dispatch a `definitionPrintFailed` with no
        // matching start — an event consumer cannot pair those.
        //
        // The name is the QUALIFIED one: `printTypeDefinition`'s context and
        // every caller-side failure context in `SwiftInterfaceBuilder` use
        // `DefinitionName.name`, while `Protocol.name` is the descriptor's BARE
        // name ("View" against "SwiftUI.View"), so the two events named the same
        // protocol two different ways and could not be correlated at all.
        let printingContext = SwiftIndexEvents.PrintingContext(name: protocolDefinition.protocolName.name, kind: .protocol)
        eventDispatcher.dispatch(.definitionPrintStarted(context: printingContext))

        // This print operation's single wrapper materialization (proposal
        // 0002), threaded into the header and associated-type renderers below.
        let dumpedProtocol = try protocolDefinition.materializedProtocol(in: machO)

        if !protocolDefinition.isIndexed {
            try await protocolDefinition.index(in: machO)
        }

        try await DeclarationBlock(level: level) {
            try await renderProtocolDeclarationHeader(for: dumpedProtocol, displayParentName: displayParentName)
        } body: {
            try await renderProtocolAssociatedTypes(for: dumpedProtocol, level: level)

            try await printDefinition(protocolDefinition, level: level)

            if configuration.printStrippedSymbolicItem, !protocolDefinition.strippedSymbolicRequirements.isEmpty {
                for strippedSymbolicRequirement in protocolDefinition.strippedSymbolicRequirements {
                    MemberList(level: level) {
                        OffsetComment(prefix: "PWT offset", offset: strippedSymbolicRequirement.pwtOffset, emit: configuration.printPWTOffset)
                        strippedSymbolicRequirement.strippedSymbolicInfo()
                    }
                }
            }
        }

        if protocolDefinition.parent == nil {
            // Per-extension catch: a default-implementation extension whose
            // printing throws drops only itself, not the protocol it trails.
            await BlockList {
                for extensionDefinition in protocolDefinition.defaultImplementationExtensions {
                    await printCatchedThrowing(
                        dispatchingTo: eventDispatcher,
                        context: .init(name: extensionDefinition.extensionName.name, kind: .extension)
                    ) {
                        try await printExtensionDefinition(extensionDefinition)
                    }
                }
            }
        }

        eventDispatcher.dispatch(.definitionPrintCompleted(context: printingContext))
    }

    @SemanticStringBuilder
    public func printExtensionDefinition(_ extensionDefinition: ExtensionDefinition, level: Int = 1) async throws -> SemanticString {
        let printingContext = SwiftIndexEvents.PrintingContext(name: extensionDefinition.extensionName.name, kind: .extension)
        eventDispatcher.dispatch(.definitionPrintStarted(context: printingContext))

        if !extensionDefinition.isIndexed {
            try await extensionDefinition.index(in: machO)
        }

        try await DeclarationBlock(level: level) {
            try await printExtensionHeader(extensionDefinition, level: level)
        } body: {
            // Per-CHILD catch, same contract as `printTypeDefinition`'s
            // nested loops: a nested definition whose printing throws
            // drops only itself, never the whole extension.
            for typeDefinition in extensionDefinition.types {
                if let renderedChild = await printCatchedThrowing(
                    dispatchingTo: eventDispatcher,
                    context: .init(name: typeDefinition.typeName.name, kind: .type),
                    {
                        try await NestedDeclaration {
                            try await printTypeDefinition(typeDefinition, level: level + 1)
                        }
                    }
                ) {
                    renderedChild
                }
            }

            for protocolDefinition in extensionDefinition.protocols {
                if let renderedChild = await printCatchedThrowing(
                    dispatchingTo: eventDispatcher,
                    context: .init(name: protocolDefinition.protocolName.name, kind: .protocol),
                    {
                        try await NestedDeclaration {
                            try await printProtocolDefinition(protocolDefinition, level: level + 1)
                        }
                    }
                ) {
                    renderedChild
                }
            }

            if !extensionDefinition.associatedTypes.isEmpty {
                try await renderMergedAssociatedTypeRecords(of: extensionDefinition.associatedTypes, level: 1)
            }

            try await printDefinition(extensionDefinition, level: 1)
        }

        eventDispatcher.dispatch(.definitionPrintCompleted(context: printingContext))
    }

    /// Renders an extension's header line (`extension Foo : Bar where …`) with no
    /// opening brace or body. Extracted from `printExtensionDefinition` so the
    /// diff renderer can emit it under its own `+`/`-` marker; the definition
    /// printer calls it too, so there is a single source of truth.
    @SemanticStringBuilder
    public func printExtensionHeader(_ extensionDefinition: ExtensionDefinition, level: Int) async throws -> SemanticString {
        Keyword(.extension)
        Space()
        extensionDefinition.extensionName.print()

        // This print operation's single conformance materialization
        // (proposal 0002). Propagates on failure: a public entry must not
        // hold a weaker error contract than the `index(in:)` that precedes
        // it on every in-repo path — both run this same materialization, so
        // in-repo the throw is unreachable, but an external caller invoking
        // this entry directly on an un-indexed definition would otherwise
        // get a confidently wrong `extension Foo` header with the
        // conformance clause, `@retroactive`, and global-actor markers
        // silently missing (a `try?` here once conflated that failure with
        // "no conformance at all").
        let materializedProtocolConformance = try extensionDefinition.materializedProtocolConformance(in: machO)

        // Pre-leaf-migration `dumpProtocolName` semantics: a `nil` protocol
        // node collapses to an *empty* name but still emits the clause (the
        // dangling `extension Foo: @retroactive ` form), while a *thrown*
        // resolution error drops the whole clause. The post-migration
        // optional-chain conflated the two, silently suppressing the clause —
        // including its `@retroactive` / global-actor markers — whenever the
        // reference was unresolvable.
        let conformanceProtocolName: SemanticString? = {
            guard let protocolConformance = materializedProtocolConformance else { return nil }
            do {
                let protocolNode = try protocolConformance.protocolNode(in: machO)
                return protocolNode?.printSemantic(using: .interfaceTypeBuilderOnly) ?? SemanticString()
            } catch {
                return nil
            }
        }()
        if let protocolConformance = materializedProtocolConformance,
           let protocolName = conformanceProtocolName {
            Standard(":")
            Space()
            if extensionDefinition.isRetroactive {
                Keyword(.atRetroactive)
                Space()
            }
            if let globalActorReference = protocolConformance.globalActorReference,
               let globalActorTypeName = try? globalActorReference.typeName(in: machO),
               let globalActorNode = try? MetadataReader.demangleType(for: globalActorTypeName, in: machO) {
                Standard("@")
                try await printThrowingType(globalActorNode, isProtocol: false, level: level)
                Space()
            }
            protocolName
        }

        if let genericSignature = extensionDefinition.genericSignature {
            let nodes = genericSignature.all(of: .requirementKinds)
            for (index, node) in nodes.enumerated() {
                if index == 0 {
                    Space()
                    Keyword(.where)
                    Space()
                }

                try await printThrowingType(node.materialize(), isProtocol: extensionDefinition.extensionName.isProtocol, level: level)

                if index < nodes.count - 1 {
                    Standard(",")
                    Space()
                }
            }
        }
    }

    @SemanticStringBuilder
    public func printDefinition(_ definition: some Definition, level: Int = 1) async throws -> SemanticString {
        if let mutableDefinition = definition as? MutableDefinition, !mutableDefinition.isIndexed {
            try await mutableDefinition.index(in: machO)
        }

        let isProtocol = definition is ProtocolDefinition

        switch configuration.memberSortOrder {
        case .byOffset:
            await printMembersByOffset(definition, level: level, isProtocol: isProtocol)
        case .byCategory:
            await printMembersByCategory(definition, level: level, isProtocol: isProtocol)
        }
    }

    @SemanticStringBuilder
    private func printMembersByOffset(_ definition: some Definition, level: Int, isProtocol: Bool) async -> SemanticString {
        let offsetCommentPrefix = isProtocol ? "PWT offset" : "Field offset"
        let emitOffsetComment = isProtocol ? configuration.printPWTOffset : configuration.printFieldOffset
        let printMemberAddress = configuration.printMemberAddress
        let printVTableOffset = configuration.printVTableOffset
        let printExportStatus = configuration.printExportStatus
        let vtableTransformerClosure = vtableOffsetTransformerClosure

        await MemberList(level: level) {
            for member in definition.orderedMembers {
                await renderMember(member, level: level, offsetCommentPrefix: offsetCommentPrefix, emitOffsetComment: emitOffsetComment, printVTableOffset: printVTableOffset, printMemberAddress: printMemberAddress, printExportStatus: printExportStatus, vtableTransformerClosure: vtableTransformerClosure)
            }

            // Terminal step: emit `deinit` for classes and noncopyable
            // structs/enums. The deallocator symbol is not a member of the
            // ordered descriptor list because it lives in the symbol table
            // only, so it is appended after all ordered members.
            //
            // Two address comments may be emitted: the unlabeled one points
            // at the deallocator (the canonical `deinit` entry), and the
            // labeled `destructor` one points at the actual user `deinit`
            // body on classes. The destructor variant collapses to nothing
            // when the type is an actor or value type.
            if let typeDefinition = definition as? TypeDefinition, let deallocatorSymbol = typeDefinition.deallocatorSymbol {
                AddressComment(addressString: memberAddressString(forOffset: deallocatorSymbol.offset), emit: printMemberAddress)
                AddressComment(addressString: memberAddressString(forOffset: typeDefinition.destructorSymbol?.offset), label: "destructor", emit: printMemberAddress)
                Keyword(.deinit)
            }
        }
    }

    @SemanticStringBuilder
    private func printMembersByCategory(_ definition: some Definition, level: Int, isProtocol: Bool) async -> SemanticString {
        let offsetCommentPrefix = isProtocol ? "PWT offset" : "Field offset"
        let emitOffsetComment = isProtocol ? configuration.printPWTOffset : configuration.printFieldOffset
        let printMemberAddress = configuration.printMemberAddress
        let printVTableOffset = configuration.printVTableOffset
        let printExportStatus = configuration.printExportStatus
        let vtableTransformerClosure = vtableOffsetTransformerClosure

        for category in MemberCategory.allCases {
            await MemberList(level: level) {
                for member in definition.members(in: category) {
                    await renderMember(member, level: level, offsetCommentPrefix: offsetCommentPrefix, emitOffsetComment: emitOffsetComment, printVTableOffset: printVTableOffset, printMemberAddress: printMemberAddress, printExportStatus: printExportStatus, vtableTransformerClosure: vtableTransformerClosure)
                }
            }
        }

        // Terminal category: emit `deinit` for classes and noncopyable
        // structs/enums. See `printMembersByOffset` for the parallel path
        // and the rationale behind the two address comments.
        if let typeDefinition = definition as? TypeDefinition, let deallocatorSymbol = typeDefinition.deallocatorSymbol {
            MemberList(level: level) {
                AddressComment(addressString: memberAddressString(forOffset: deallocatorSymbol.offset), emit: printMemberAddress)
                AddressComment(addressString: memberAddressString(forOffset: typeDefinition.destructorSymbol?.offset), label: "destructor", emit: printMemberAddress)
                Keyword(.deinit)
            }
        }
    }

    /// Renders one `OrderedMember` — its offset / vtable / address comments
    /// followed by the member declaration — shared by both the `byOffset` and
    /// `byCategory` paths so the per-member comment layout has a single source of
    /// truth. The emit flags and comment prefix are hoisted by the caller (they
    /// depend on the enclosing definition, not the member).
    ///
    /// The body is wrapped in a `Rows(level: level) { ... }` so each comment
    /// and the trailing declaration become independent rows at the enclosing
    /// `MemberList`'s indent level. Returning a plain `SemanticString` without
    /// `Rows` would fuse them into one row and drop the `BreakLine + Indent`
    /// separators.
    @SemanticStringBuilder
    private func renderMember(
        _ member: OrderedMember,
        level: Int,
        offsetCommentPrefix: String,
        emitOffsetComment: Bool,
        printVTableOffset: Bool,
        printMemberAddress: Bool,
        printExportStatus: Bool,
        vtableTransformerClosure: (@Sendable (Int, String?) -> SemanticString)?
    ) async -> SemanticString {
        await Rows(level: level) {
            switch member {
            case .allocator(let function), .function(let function):
                OffsetComment(prefix: offsetCommentPrefix, offset: function.offset, emit: emitOffsetComment)
                VTableOffsetComment(vtableOffset: function.vtableOffset, emit: printVTableOffset, transformer: vtableTransformerClosure)
                AddressComment(addressString: memberAddressString(forOffset: function.symbol.offset), emit: printMemberAddress)
                // Qualifies the address above (evolution proposal 0007): the
                // witness resolved to a protocol-extension DEFAULT — the code
                // lives on the protocol, and several such witnesses typically
                // share one identical-code-folded address.
                if printMemberAddress, function.isProtocolExtensionDefault {
                    Comment("protocol-extension default")
                }
                // Export status is only ruled on for members whose OWN
                // symbols are the linkage surface: an `override` links
                // through the PARENT's dispatch thunk and an `@objc` member
                // dispatches through objc_msgSend, so both routinely carry
                // zero exported symbols of their own while being perfectly
                // reachable — annotating them would be a false positive
                // (verified on the fixture: `public override` and
                // `@objc public dynamic` members both trie-miss).
                if printExportStatus, !function.isOverride, !function.attributes.contains(.objc) {
                    ExportStatusComment(isExported: exportVerdict(forSymbolNames: [function.symbol.name]))
                }
                await printFunction(function, level: level)

            case .variable(let variable):
                OffsetComment(prefix: offsetCommentPrefix, offset: variable.offset, emit: emitOffsetComment)
                for accessor in variable.accessors {
                    VTableOffsetComment(vtableOffset: accessor.vtableOffset, label: accessor.kind.addressLabel, emit: printVTableOffset, transformer: vtableTransformerClosure)
                    AddressComment(addressString: memberAddressString(forOffset: accessor.symbol.offset), label: accessor.kind.addressLabel, emit: printMemberAddress)
                }
                if printMemberAddress, variable.isProtocolExtensionDefault {
                    Comment("protocol-extension default")
                }
                if printExportStatus, !variable.isOverride, !variable.attributes.contains(.objc) {
                    ExportStatusComment(isExported: exportVerdict(forSymbolNames: variable.accessors.map(\.symbol.name)))
                }
                await printVariable(variable, level: level)

            case .subscript(let `subscript`):
                OffsetComment(prefix: offsetCommentPrefix, offset: `subscript`.offset, emit: emitOffsetComment)
                for accessor in `subscript`.accessors {
                    VTableOffsetComment(vtableOffset: accessor.vtableOffset, label: accessor.kind.addressLabel, emit: printVTableOffset, transformer: vtableTransformerClosure)
                    AddressComment(addressString: memberAddressString(forOffset: accessor.symbol.offset), label: accessor.kind.addressLabel, emit: printMemberAddress)
                }
                if printMemberAddress, `subscript`.isProtocolExtensionDefault {
                    Comment("protocol-extension default")
                }
                if printExportStatus, !`subscript`.isOverride, !`subscript`.attributes.contains(.objc) {
                    ExportStatusComment(isExported: exportVerdict(forSymbolNames: `subscript`.accessors.map(\.symbol.name)))
                }
                await printSubscript(`subscript`, level: level)
            }
        }
    }

    /// Export-status line for a TOP-LEVEL declaration (global variable /
    /// function), rendered by `SwiftInterfaceBuilder.printRoot`'s globals
    /// blocks — those never route through `renderMember`, so without this
    /// the flag would silently skip them. Globals need no `override`/`@objc`
    /// exemption (neither exists at top level). Renders empty when nothing
    /// should be emitted (flag off, or no negative verdict).
    @SemanticStringBuilder
    package func globalExportStatusComment(forSymbolNames symbolNames: [String]) -> SemanticString {
        if configuration.printExportStatus, exportVerdict(forSymbolNames: symbolNames) == false {
            // No trailing `BreakLine()`: the caller is a `BlockList`, which
            // already emits one leading break per non-empty item, so a break
            // here would separate the comment from the declaration it
            // annotates by a blank line (the member path's `Rows` keeps
            // `ExportStatusComment` adjacent the same way).
            Comment("not exported")
        }
    }

    /// The member-level export verdict backing `ExportStatusComment`
    /// (evolution proposal 0008): `false` only when EVERY symbol of the
    /// member provably lacks an export-trie entry, `true` as soon as one is
    /// exported, `nil` when there is no evidence to rule on — no symbols
    /// joined, or the image carries no export information at all — so the
    /// annotation never fires on a guess. Internal (not private): the
    /// stored-field leg lives in `SwiftDeclarationPrinter+Headers.swift`.
    func exportVerdict(forSymbolNames symbolNames: [String]) -> Bool? {
        guard !symbolNames.isEmpty else { return nil }
        @Dependency(\.symbolIndexStore) var symbolIndexStore
        for symbolName in symbolNames {
            guard let isExported = symbolIndexStore.isExportedIncludingDerivedSymbols(name: symbolName, in: machO) else { return nil }
            if isExported {
                return true
            }
        }
        return false
    }

    @SemanticStringBuilder
    public func printVariable(_ variable: VariableDefinition, level: Int) async -> SemanticString {
        await dispatchingCatchedThrowing(.init(name: variable.name, kind: .variable)) {
            try await printThrowingVariable(variable, level: level)
        }
    }

    @SemanticStringBuilder
    public func printFunction(_ function: FunctionDefinition, level: Int) async -> SemanticString {
        await dispatchingCatchedThrowing(.init(name: function.name, kind: .function)) {
            try await printThrowingFunction(function, level: level)
        }
    }

    @SemanticStringBuilder
    public func printSubscript(_ `subscript`: SubscriptDefinition, level: Int) async -> SemanticString {
        await dispatchingCatchedThrowing(.init(name: "subscript", kind: .subscript)) {
            try await printThrowingSubscript(`subscript`, level: level)
        }
    }

    @SemanticStringBuilder
    public func printType(_ typeNode: Node, isProtocol: Bool, level: Int) async -> SemanticString {
        await printCatchedThrowing(dispatchingTo: eventDispatcher, degradationSource: .typeNodeRendering) {
            try await printThrowingType(typeNode, isProtocol: isProtocol, level: level)
        }
    }

    private func dispatchingCatchedThrowing(_ context: SwiftIndexEvents.PrintingContext, @SemanticStringBuilder _ body: () async throws -> SemanticString) async -> SemanticString? {
        do {
            return try await body()
        } catch {
            eventDispatcher.dispatch(.definitionPrintFailed(context: context, error: error))
            return nil
        }
    }

    @SemanticStringBuilder
    public func printThrowingVariable(_ variable: VariableDefinition, level: Int) async throws -> SemanticString {
        for attribute in variable.attributes {
            Keyword(attribute.keyword)
            Space()
        }
        var printer = VariableNodePrinter(isStored: variable.isStored, isOverride: variable.isOverride, isClassMember: variable.isClassMember, isFinal: variable.isFinal, hasSetter: variable.hasSetter, indentation: level, delegate: self)
        try await printer.printRoot(variable.node.materialize())
    }

    @SemanticStringBuilder
    public func printThrowingFunction(_ function: FunctionDefinition, level: Int) async throws -> SemanticString {
        for attribute in function.attributes {
            Keyword(attribute.keyword)
            Space()
        }
        var printer = FunctionNodePrinter(isOverride: function.isOverride, isClassMember: function.isClassMember, isFinal: function.isFinal, delegate: self)
        try await printer.printRoot(function.node.materialize())
    }

    @SemanticStringBuilder
    public func printThrowingSubscript(_ `subscript`: SubscriptDefinition, level: Int) async throws -> SemanticString {
        for attribute in `subscript`.attributes {
            Keyword(attribute.keyword)
            Space()
        }
        var printer = SubscriptNodePrinter(isOverride: `subscript`.isOverride, isClassMember: `subscript`.isClassMember, isFinal: `subscript`.isFinal, hasSetter: `subscript`.hasSetter, indentation: level, delegate: self)
        try await printer.printRoot(`subscript`.node.materialize())
    }

    @SemanticStringBuilder
    public func printThrowingType(_ typeNode: Node, isProtocol: Bool, level: Int) async throws -> SemanticString {
        var printer = TypeNodePrinter(delegate: self, isProtocol: isProtocol)
        try await printer.printRoot(typeNode)
    }

    /// Routes an opaque-type rewrite failure into this printer's event stream.
    ///
    /// `Node+OpaqueType` lives in `SwiftDeclarationRendering`, which
    /// `SwiftDeclaration` depends on, so it cannot name the event types itself
    /// and takes a closure instead. This is where the closure is bound.
    func opaqueTypeDegradationReporter(subject: String?) -> OpaqueTypeDegradationReporter {
        let eventDispatcher = eventDispatcher
        return { error in
            eventDispatcher.dispatch(
                .renderingDegraded(
                    context: .init(source: .opaqueTypeRewrite, subject: subject),
                    error: error
                )
            )
        }
    }

    private func memberAddressString(forOffset offset: Int?) -> String? {
        guard let offset else { return nil }
        return machO.addressString(forOffset: offset)
    }

    private var vtableOffsetTransformerClosure: (@Sendable (Int, String?) -> SemanticString)? {
        guard let transformer = configuration.vtableOffsetTransformer else { return nil }
        return { slotOffset, label in transformer((slotOffset, label)) }
    }
}

/// Renders `body`, dropping only what it was rendering if it throws.
///
/// The failure is always reported, and always as an event — it must NOT be
/// printed. `swift-section interface` / `dump` stream the generated Swift to
/// stdout (`InterfaceCommand.swift:106`, `DumpCommand.swift:294`), so anything a
/// library writes there lands inside the generated output and corrupts any piped
/// or redirected interface. Issue #102 reported both halves of this from the
/// field: a run that lost 8,375 definitions emitted **zero**
/// `definitionPrintFailed` events, and its only signal was a bare
/// `unexpected(at: 8)` on stdout, fully buffered and therefore surfacing far
/// from its cause.
///
/// The dispatcher is required rather than optional. When it was optional, the
/// callers that passed nothing fell to a stderr `else` branch — which is how a
/// library ended up choosing where diagnostics go, and how the branch could
/// raise on a closed stderr and abort the host. Where the failure has no
/// definition identity (`context == nil`) it is reported as
/// ``SwiftIndexEvents/DegradationSource`` instead; a dispatcher with no handlers
/// still has `Dispatcher`'s own floor beneath it, so nothing lands nowhere.
package func printCatchedThrowing(
    isolation: isolated (any Actor)? = #isolation,
    dispatchingTo eventDispatcher: SwiftIndexEvents.Dispatcher,
    context: SwiftIndexEvents.PrintingContext? = nil,
    degradationSource: SwiftIndexEvents.DegradationSource = .typeNodeRendering,
    @SemanticStringBuilder _ body: () async throws -> SemanticString
) async -> SemanticString? {
    do {
        return try await body()
    } catch {
        if let context {
            eventDispatcher.dispatch(.definitionPrintFailed(context: context, error: error))
        } else {
            eventDispatcher.dispatch(
                .renderingDegraded(context: .init(source: degradationSource), error: error)
            )
        }
        return nil
    }
}

extension SwiftDeclarationPrinter: NodePrintableDelegate {
    public func moduleName(forTypeName typeName: String) async -> String? {
        await typeNameResolverRegistry.moduleNameResolvers.asyncFirstNonNil { await $0.moduleName(forTypeName: typeName) }
    }

    public func swiftName(forCName cName: String, category: CImportedTypeNameCategory) async -> String? {
        await typeNameResolverRegistry.cImportedNameResolvers.asyncFirstNonNil { await $0.swiftName(forCName: cName, category: category) }
    }

    public func opaqueType(forNode node: Node, index: Int?) async -> String? {
        await typeNameResolverRegistry.opaqueTypeResolvers.asyncFirstNonNil { await $0.opaqueType(forNode: node, index: index) }
    }
}
