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

    @Mutex
    public private(set) var typeNameResolvers: [any TypeNameResolvable] = []

    let eventDispatcher: SwiftIndexEvents.Dispatcher = .init()

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
        self.configuration = configuration
        eventDispatcher.addHandlers(eventHandlers)
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

    public func addTypeNameResolver(_ resolver: any TypeNameResolvable) {
        typeNameResolvers.append(resolver)
    }

    public func removeAllTypeNameResolvers() {
        typeNameResolvers.removeAll()
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

        try await DeclarationBlock(level: level) {
            try await renderTypeDeclarationHeader(for: typeDefinition.type, displayParentName: displayParentName, level: level)
        } body: {
            for child in typeDefinition.typeChildren {
                try await NestedDeclaration {
                    try await printTypeDefinition(child, level: level + 1)
                }
            }

            for child in typeDefinition.protocolChildren {
                try await NestedDeclaration {
                    try await printProtocolDefinition(child, level: level + 1)
                }
            }

            await renderModelFields(typeDefinition, level: level)

            try await printDefinition(typeDefinition, level: level)
        }

        eventDispatcher.dispatch(.definitionPrintCompleted(context: printingContext))
    }

    @SemanticStringBuilder
    public func printProtocolDefinition(_ protocolDefinition: ProtocolDefinition, level: Int = 1, displayParentName: Bool = false) async throws -> SemanticString {
        let printingContext = SwiftIndexEvents.PrintingContext(name: protocolDefinition.protocol.name, kind: .protocol)
        eventDispatcher.dispatch(.definitionPrintStarted(context: printingContext))

        if !protocolDefinition.isIndexed {
            try await protocolDefinition.index(in: machO)
        }

        try await DeclarationBlock(level: level) {
            try await renderProtocolDeclarationHeader(for: protocolDefinition.protocol, displayParentName: displayParentName)
        } body: {
            try await renderProtocolAssociatedTypes(for: protocolDefinition.protocol, level: level)

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
            try await BlockList {
                for extensionDefinition in protocolDefinition.defaultImplementationExtensions {
                    try await printExtensionDefinition(extensionDefinition)
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
            for typeDefinition in extensionDefinition.types {
                try await NestedDeclaration {
                    try await printTypeDefinition(typeDefinition, level: level + 1)
                }
            }

            for protocolDefinition in extensionDefinition.protocols {
                try await NestedDeclaration {
                    try await printProtocolDefinition(protocolDefinition, level: level + 1)
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

        if let protocolConformance = extensionDefinition.protocolConformance,
           let protocolName = try? protocolConformance.protocolNode(in: machO)?.printSemantic(using: .interfaceTypeBuilderOnly) {
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

                try await printThrowingType(node, isProtocol: extensionDefinition.extensionName.isProtocol, level: level)

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
        let vtableTransformerClosure = vtableOffsetTransformerClosure

        await MemberList(level: level) {
            for member in definition.orderedMembers {
                await renderMember(member, level: level, offsetCommentPrefix: offsetCommentPrefix, emitOffsetComment: emitOffsetComment, printVTableOffset: printVTableOffset, printMemberAddress: printMemberAddress, vtableTransformerClosure: vtableTransformerClosure)
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
                AddressComment(addressString: memberAddressString(forOffset: deallocatorSymbol.symbol.offset), emit: printMemberAddress)
                AddressComment(addressString: memberAddressString(forOffset: typeDefinition.destructorSymbol?.symbol.offset), label: "destructor", emit: printMemberAddress)
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
        let vtableTransformerClosure = vtableOffsetTransformerClosure

        for category in MemberCategory.allCases {
            await MemberList(level: level) {
                for member in definition.members(in: category) {
                    await renderMember(member, level: level, offsetCommentPrefix: offsetCommentPrefix, emitOffsetComment: emitOffsetComment, printVTableOffset: printVTableOffset, printMemberAddress: printMemberAddress, vtableTransformerClosure: vtableTransformerClosure)
                }
            }
        }

        // Terminal category: emit `deinit` for classes and noncopyable
        // structs/enums. See `printMembersByOffset` for the parallel path
        // and the rationale behind the two address comments.
        if let typeDefinition = definition as? TypeDefinition, let deallocatorSymbol = typeDefinition.deallocatorSymbol {
            MemberList(level: level) {
                AddressComment(addressString: memberAddressString(forOffset: deallocatorSymbol.symbol.offset), emit: printMemberAddress)
                AddressComment(addressString: memberAddressString(forOffset: typeDefinition.destructorSymbol?.symbol.offset), label: "destructor", emit: printMemberAddress)
                Keyword(.deinit)
            }
        }
    }

    /// Renders one `OrderedMember` — its offset / vtable / address comments
    /// followed by the member declaration — shared by both the `byOffset` and
    /// `byCategory` paths so the per-member comment layout has a single source of
    /// truth. The emit flags and comment prefix are hoisted by the caller (they
    /// depend on the enclosing definition, not the member).
    @SemanticStringBuilder
    private func renderMember(
        _ member: OrderedMember,
        level: Int,
        offsetCommentPrefix: String,
        emitOffsetComment: Bool,
        printVTableOffset: Bool,
        printMemberAddress: Bool,
        vtableTransformerClosure: (@Sendable (Int, String?) -> SemanticString)?
    ) async -> SemanticString {
        switch member {
        case .allocator(let function), .function(let function):
            OffsetComment(prefix: offsetCommentPrefix, offset: function.offset, emit: emitOffsetComment)
            VTableOffsetComment(vtableOffset: function.vtableOffset, emit: printVTableOffset, transformer: vtableTransformerClosure)
            AddressComment(addressString: memberAddressString(forOffset: function.symbol.offset), emit: printMemberAddress)
            await printFunction(function, level: level)

        case .variable(let variable):
            OffsetComment(prefix: offsetCommentPrefix, offset: variable.offset, emit: emitOffsetComment)
            for accessor in variable.accessors {
                VTableOffsetComment(vtableOffset: accessor.vtableOffset, label: accessor.kind.addressLabel, emit: printVTableOffset, transformer: vtableTransformerClosure)
                AddressComment(addressString: memberAddressString(forOffset: accessor.symbol.offset), label: accessor.kind.addressLabel, emit: printMemberAddress)
            }
            await printVariable(variable, level: level)

        case .subscript(let `subscript`):
            OffsetComment(prefix: offsetCommentPrefix, offset: `subscript`.offset, emit: emitOffsetComment)
            for accessor in `subscript`.accessors {
                VTableOffsetComment(vtableOffset: accessor.vtableOffset, label: accessor.kind.addressLabel, emit: printVTableOffset, transformer: vtableTransformerClosure)
                AddressComment(addressString: memberAddressString(forOffset: accessor.symbol.offset), label: accessor.kind.addressLabel, emit: printMemberAddress)
            }
            await printSubscript(`subscript`, level: level)
        }
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
        await printCatchedThrowing {
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
        var printer = VariableNodePrinter(isStored: variable.isStored, isOverride: variable.isOverride, hasSetter: variable.hasSetter, indentation: level, delegate: self)
        try await printer.printRoot(variable.node)
    }

    @SemanticStringBuilder
    public func printThrowingFunction(_ function: FunctionDefinition, level: Int) async throws -> SemanticString {
        for attribute in function.attributes {
            Keyword(attribute.keyword)
            Space()
        }
        var printer = FunctionNodePrinter(isOverride: function.isOverride, delegate: self)
        try await printer.printRoot(function.node)
    }

    @SemanticStringBuilder
    public func printThrowingSubscript(_ `subscript`: SubscriptDefinition, level: Int) async throws -> SemanticString {
        for attribute in `subscript`.attributes {
            Keyword(attribute.keyword)
            Space()
        }
        var printer = SubscriptNodePrinter(isOverride: `subscript`.isOverride, hasSetter: `subscript`.hasSetter, indentation: level, delegate: self)
        try await printer.printRoot(`subscript`.node)
    }

    @SemanticStringBuilder
    public func printThrowingType(_ typeNode: Node, isProtocol: Bool, level: Int) async throws -> SemanticString {
        var printer = TypeNodePrinter(delegate: self, isProtocol: isProtocol)
        try await printer.printRoot(typeNode)
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

package func printCatchedThrowing(@SemanticStringBuilder _ body: () async throws -> SemanticString) async -> SemanticString? {
    do {
        return try await body()
    } catch {
        print(error)
        return nil
    }
}

extension SwiftDeclarationPrinter: NodePrintableDelegate {
    public func moduleName(forTypeName typeName: String) async -> String? {
        await typeNameResolvers.asyncFirstNonNil { await $0.moduleName(forTypeName: typeName) }
    }

    public func swiftName(forCName cName: String) async -> String? {
        await typeNameResolvers.asyncFirstNonNil { await $0.swiftName(forCName: cName) }
    }

    public func opaqueType(forNode node: Node, index: Int?) async -> String? {
        await typeNameResolvers.asyncFirstNonNil { await $0.opaqueType(forNode: node, index: index) }
    }
}
