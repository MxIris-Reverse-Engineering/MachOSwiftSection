import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import Utilities
import Dependencies
import OrderedCollections
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

package struct ClassDumper<MachO: FieldLayoutRenderable>: TypedDumper {
    package typealias Dumped = Class

    package typealias Metadata = ClassMetadataObjCInterop

    package let dumped: Dumped

    package let metadataContext: DumperMetadataContext<Metadata>?

    package let configuration: DumperConfiguration

    package let machO: MachO

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    package init(_ dumped: Dumped, using configuration: DumperConfiguration, in machO: MachO) {
        self.init(dumped, metadataContext: nil, using: configuration, in: machO)
    }

    package init(_ dumped: Dumped, metadataContext: DumperMetadataContext<Metadata>?, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
        self.metadataContext = metadataContext
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var declaration: SemanticString {
        get async throws {
            if dumped.descriptor.isActor {
                if isDistributedActor {
                    Keyword(.distributed)
                    Space()
                }
                Keyword(.actor)
            } else {
                Keyword(.class)
            }

            Space()

            try await name
            let superclass = try await superclass
            // For a specialized class dumper, `name` already prints the
            // bound generic form so the `<A: Hashable, ...>` clause would
            // duplicate the type-argument display. Emit the superclass
            // segment directly in that case.
            let isBound = boundDumpedMetatype() != nil
            if !isBound, let genericContext = dumped.genericContext {
                try await genericContext.dumpGenericSignature(resolver: demangleResolver, in: machO) {
                    superclass
                }
            } else {
                superclass
            }
        }
    }

    /// The set of inner function nodes of `.distributedThunk` symbols whose class
    /// context matches this class. Used for both class-level (`distributed actor`)
    /// and method-level (`distributed func`) keyword emission.
    private var distributedFunctionNodes: Set<StructuralNodeReferenceKey> {
        get throws {
            guard dumped.descriptor.isActor else { return [] }

            let currentTypeNode = try MetadataReader.demangleContext(for: .type(.class(dumped.descriptor)), in: machO)
            let currentTypeName = currentTypeNode.print(using: .interfaceTypeBuilderOnly)

            var nodes: Set<StructuralNodeReferenceKey> = []

            for thunkSymbol in symbolIndexStore.symbols(of: .distributedThunk, in: machO) {
                let rootNode = thunkSymbol.demangledNode
                guard let functionNode = rootNode.children.first(where: { $0.kind != .distributedThunk }) else { continue }
                guard let contextNode = functionNode.children.first else { continue }
                let thunkTypeName = Node.create(kind: .type, child: contextNode.materialize()).print(using: .interfaceTypeBuilderOnly)
                guard thunkTypeName == currentTypeName else { continue }
                // Structural key over the store-backed reference: the method
                // loop probes with reference-form function nodes, and keying
                // structurally spares materializing a tree per thunk.
                nodes.insert(StructuralNodeReferenceKey(functionNode))
            }

            return nodes
        }
    }

    private var isDistributedActor: Bool {
        guard dumped.descriptor.isActor else { return false }
        return ((try? distributedFunctionNodes) ?? []).isEmpty == false
    }

    @SemanticStringBuilder
    package var superclass: SemanticString {
        get async throws {
            let hasInvertedProtocols = dumped.invertibleProtocolSet?.hasInvertedProtocols ?? false
            if let superclassMangledName = try dumped.descriptor.superclassTypeMangledName(in: machO) {
                Standard(":")
                Space()
                try await demangleResolver.resolve(for: MetadataReader.demangleType(for: superclassMangledName, in: machO))
                if hasInvertedProtocols {
                    Standard(",")
                    Space()
                    dumped.invertibleProtocolSet!.dumpInvertedProtocolNames
                }
            } else if let resilientSuperclass = dumped.resilientSuperclass, let kind = dumped.descriptor.resilientSuperclassReferenceKind, let superclass = try await resilientSuperclass.dumpSuperclass(resolver: demangleResolver, for: kind, in: machO) {
                Standard(":")
                Space()
                superclass
                if hasInvertedProtocols {
                    Standard(",")
                    Space()
                    dumped.invertibleProtocolSet!.dumpInvertedProtocolNames
                }
            } else if hasInvertedProtocols {
                dumped.invertibleProtocolSet!.dumpInvertedProtocolsInheritance
            }
        }
    }

    package var fields: SemanticString {
        get async throws {
            // Shared field-metadata comment rendering (single source with
            // `SwiftPrinting`). See `StructDumper.fields` for the rationale
            // behind `autoResolveAccessorMetadata: false`.
            let fieldLayoutRenderer = FieldLayoutRenderer(
                type: .class(dumped),
                metadata: try? metadataContext?.resolvedMetadataWrapper(),
                machO: machO,
                configuration: configuration,
                autoResolveAccessorMetadata: false
            )
            let fieldOffsets = fieldLayoutRenderer.fieldOffsets
            // `final` recovery for stored `var`s (evolution proposal 0006),
            // mirroring the model path in `TypeDefinition.index`: a stored
            // `var` whose accessors occupy no vtable slot was declared
            // `final`. Both sets stay empty when the evidence is missing
            // (actor, no vtable header, stripped symbols), and a name absent
            // from `storedAccessorFieldNames` never gets marked — absence of
            // evidence is not `final`.
            let canRecoverFinalFields = dumped.vTableDescriptorHeader != nil && !dumped.descriptor.isActor
            let finalRecoveryInterfaceName = canRecoverFinalFields ? try await interfaceName.string : ""
            // Same-named private types share the stripped name bucket, and
            // both sets below decide a `final` keyword — so the lookups must
            // be node-matched exactly like the member loops in `members`
            // (issue #115). A context that cannot be demangled falls back to
            // the name-only (merged) lookup rather than dropping evidence.
            let finalRecoveryContextNode = canRecoverFinalFields ? try? MetadataReader.demangleContext(for: .type(.class(dumped.descriptor)), in: machO) : nil
            let vtableAccessorNames = canRecoverFinalFields ? vtableAccessorFieldNames(interfaceNameString: finalRecoveryInterfaceName, contextNode: finalRecoveryContextNode) : []
            let storedAccessorNames = canRecoverFinalFields ? storedAccessorFieldNames(interfaceNameString: finalRecoveryInterfaceName, contextNode: finalRecoveryContextNode) : []
            for (offset, fieldRecord) in try dumped.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                BreakLine()

                let mangledTypeName = try fieldRecord.mangledTypeName(in: machO)

                try await fieldLayoutRenderer.storedFieldComments(forFieldAtIndex: offset.index, mangledTypeName: mangledTypeName, fieldOffsets: fieldOffsets)

                Indent(level: configuration.indentation)

                let demangledTypeNode = try fieldDemangledTypeNode(for: mangledTypeName)

                let fieldName = try fieldRecord.fieldName(in: machO)

                let strippedFieldName = fieldName.stripLazyPrefix
                let isFinalField = canRecoverFinalFields
                    && fieldRecord.flags.contains(.isVariadic)
                    && storedAccessorNames.contains(strippedFieldName)
                    && !vtableAccessorNames.contains(strippedFieldName)

                fieldDeclarationKeywords(for: fieldRecord, typeNode: demangledTypeNode, fieldName: fieldName, isFinal: isFinalField)

                MemberDeclaration(fieldName.stripLazyPrefix)

                Standard(":")

                Space()

                try await demangleResolver.modify {
                    if case .options(let demangleOptions) = $0 {
                        return .options(demangleOptions.union(.removeReferenceStoragePrefix))
                    } else {
                        return $0
                    }
                }
                .resolve(for: demangledTypeNode)

                if offset.isEnd {
                    BreakLine()
                }
            }
        }
    }

    package var body: SemanticString {
        get async throws {
            try await declaration

            Space()

            Standard("{")

            try await fields

            let distributedFunctionNodes = (try? self.distributedFunctionNodes) ?? []

            var methodVisitedNodes: OrderedSet<StructuralNodeReferenceKey> = []
            let vtableBaseOffset = dumped.vTableDescriptorHeader.map { Int($0.layout.vTableOffset) }
            for (offset, descriptor) in dumped.methodDescriptors.offsetEnumerated() {
                BreakLine()

                if configuration.printVTableOffset, let vtableBaseOffset {
                    configuration.vtableOffsetComment(slotOffset: vtableBaseOffset + offset.index)
                }

                if configuration.printMemberAddress, !descriptor.implementation.isNull {
                    let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                    configuration.memberAddressComment(offset: implOffset, addressString: machO.addressString(forOffset: implOffset))
                }

                Indent(level: 1)

                // Pre-resolve the method node so we can check distributed status
                // before deciding which keywords to emit.
                var resolvedMethodNode: NodeReference? = nil
                if let symbols = try? descriptor.implementationSymbols(in: machO) {
                    resolvedMethodNode = try? await validNode(for: symbols, visitedNodes: methodVisitedNodes)
                }

                let isDistributedMethod: Bool = {
                    guard descriptor.flags.kind == .method,
                          let root = resolvedMethodNode,
                          let functionNode = root.children.first(where: { $0.kind == .function }) else { return false }
                    return distributedFunctionNodes.contains(StructuralNodeReferenceKey(functionNode))
                }()

                dumpMethodKind(for: descriptor)

                dumpMethodKeyword(for: descriptor, isDistributed: isDistributedMethod)

                try await dumpMethodDeclaration(for: descriptor, resolvedNode: resolvedMethodNode, visitedNodes: &methodVisitedNodes)

                if offset.isEnd {
                    BreakLine()
                }
            }

            var parentVTableCache = ParentClassVTableCache()
            var methodOverrideVisitedNodes: OrderedSet<StructuralNodeReferenceKey> = []
            for (offset, descriptor) in dumped.methodOverrideDescriptors.offsetEnumerated() {
                BreakLine()

                if configuration.printVTableOffset {
                    if let vtableSlot = try? parentVTableCache.slotIndex(for: descriptor, in: machO) {
                        configuration.vtableOffsetComment(slotOffset: vtableSlot)
                    }
                }

                if configuration.printMemberAddress, !descriptor.implementation.isNull {
                    let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                    configuration.memberAddressComment(offset: implOffset, addressString: machO.addressString(forOffset: implOffset))
                }

                Indent(level: 1)

                let methodDescriptor = try descriptor.methodDescriptor(in: machO)

                if let symbols = try? descriptor.implementationSymbols(in: machO), let node = try await validNode(for: symbols, visitedNodes: methodOverrideVisitedNodes) {
                    dumpMethodKind(for: methodDescriptor?.resolved)
                    Keyword(.override)
                    Space()
                    try await demangleResolver.resolve(for: node)
                    _ = methodOverrideVisitedNodes.append(StructuralNodeReferenceKey(node))
                } else if !descriptor.implementation.isNull {
                    dumpMethodKind(for: methodDescriptor?.resolved)
                    Keyword(.override)
                    Space()
                    FunctionDeclaration(machO.addressString(forOffset: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))).insertSubFunctionPrefix)
                } else if let methodDescriptor {
                    switch methodDescriptor {
                    case .symbol(let symbol):
                        Keyword(.override)
                        Space()
                        try await MetadataReader.demangleSymbolReference(for: symbol, in: machO).asyncMap { try await demangleResolver.resolve(for: $0) }
                    case .element(let element):
                        dumpMethodKind(for: element)
                        Keyword(.override)
                        Space()
                        dumpMethodKeyword(for: element)
                        try? await dumpMethodDeclaration(for: element, visitedNodes: &methodOverrideVisitedNodes)
                    }
                } else {
                    Error("Symbol not found")
                }

                if offset.isEnd {
                    BreakLine()
                }
            }

            var methodDefaultOverrideVisitedNodes: OrderedSet<StructuralNodeReferenceKey> = []
            for (offset, descriptor) in dumped.methodDefaultOverrideDescriptors.offsetEnumerated() {
                BreakLine()

                if configuration.printMemberAddress, !descriptor.implementation.isNull {
                    let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                    configuration.memberAddressComment(offset: implOffset, addressString: machO.addressString(forOffset: implOffset))
                }

                Indent(level: 1)

                Keyword(.override)

                Space()

                if let symbols = try? descriptor.implementationSymbols(in: machO), let node = try await validNode(for: symbols, visitedNodes: methodDefaultOverrideVisitedNodes) {
                    try await demangleResolver.resolve(for: node)
                    _ = methodDefaultOverrideVisitedNodes.append(StructuralNodeReferenceKey(node))
                } else if !descriptor.implementation.isNull {
                    FunctionDeclaration(machO.addressString(forOffset: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))).insertSubFunctionPrefix)
                } else {
                    Error("Symbol not found")
                }

                if offset.isEnd {
                    BreakLine()
                }
            }

            let interfaceNameString = try await interfaceName.string

            // The same two exemptions the interface path applies (evolution
            // proposal 0008): a member whose only reachability is not its own
            // exported symbol must not be flagged. An `override`'s
            // implementation symbol is an ordinary member symbol of THIS
            // class (external callers link the parent's dispatch thunk), and
            // an `@objc` member dispatches through objc_msgSend — its ObjC
            // entry point is the implementation name plus the `To` suffix,
            // which identifies it without demangling.
            let overrideImplementationSymbolNames = configuration.printExportStatus ? collectOverrideImplementationSymbolNames() : []

            // Same-named private types share the stripped name bucket; the
            // context node picks this type's own sub-bucket (issue #115).
            // A context that cannot be demangled falls back to the name-only
            // (merged) lookup rather than dropping members.
            let contextNode = try? MetadataReader.demangleContext(for: .type(.class(dumped.descriptor)), in: machO)

            for kind in SymbolIndexStore.MemberKind.allCases {
                let memberSymbols = if let contextNode {
                    symbolIndexStore.memberSymbols(of: kind, for: interfaceNameString, node: contextNode, in: machO)
                } else {
                    symbolIndexStore.memberSymbols(of: kind, for: interfaceNameString, in: machO)
                }
                for (offset, symbol) in memberSymbols.offsetEnumerated() {
                    if offset.isStart {
                        BreakLine()

                        Indent(level: 1)

                        InlineComment(kind.description)
                    }

                    BreakLine()

                    if configuration.printMemberAddress {
                        configuration.memberAddressComment(offset: symbol.offset, addressString: machO.addressString(forOffset: symbol.offset))
                    }

                    if configuration.printExportStatus,
                       !overrideImplementationSymbolNames.contains(symbol.name),
                       !symbolIndexStore.containsSymbol(named: symbol.name + "To", in: machO),
                       symbolIndexStore.isExportedIncludingDerivedSymbols(name: symbol.name, in: machO) == false {
                        configuration.exportStatusComment()
                    }

                    Indent(level: 1)

                    try await demangleResolver.resolve(for: symbol.demangledNode)

                    if offset.isEnd {
                        BreakLine()
                    }
                }
            }

            for kind in SymbolIndexStore.MemberKind.allCases {
                let methodDescriptorSymbols = if let contextNode {
                    symbolIndexStore.methodDescriptorMemberSymbols(of: kind, for: interfaceNameString, node: contextNode, in: machO)
                } else {
                    symbolIndexStore.methodDescriptorMemberSymbols(of: kind, for: interfaceNameString, in: machO)
                }
                for (offset, symbol) in methodDescriptorSymbols.offsetEnumerated() {
                    if offset.isStart {
                        BreakLine()

                        Indent(level: 1)

                        InlineComment("[Method] " + kind.description)
                    }

                    BreakLine()

                    if configuration.printMemberAddress {
                        configuration.memberAddressComment(offset: symbol.offset, addressString: machO.addressString(forOffset: symbol.offset))
                    }

                    // These rows are the `Tq` method-descriptor DATA symbols;
                    // the derived-form expansion only makes sense over the
                    // member's implementation name, so strip the suffix
                    // before querying (querying "…Tq" would append the
                    // derived suffixes onto it — "…TqTj" etc. never exist —
                    // degrading to the bare-name query this proposal's own
                    // analysis rejects).
                    if configuration.printExportStatus {
                        let implementationName = symbol.name.hasSuffix("Tq") ? String(symbol.name.dropLast(2)) : symbol.name
                        if symbolIndexStore.isExportedIncludingDerivedSymbols(name: implementationName, in: machO) == false {
                            configuration.exportStatusComment()
                        }
                    }

                    Indent(level: 1)

                    try await demangleResolver.resolve(for: symbol.demangledNode)

                    if offset.isEnd {
                        BreakLine()
                    }
                }
            }

            Standard("}")
        }
    }

    /// Implementation-symbol names consumed by the override / default-override
    /// vtable sections — these are ordinary member symbols of THIS class, so
    /// the member-symbol loops must exempt them from export-status
    /// annotation (evolution proposal 0008: external callers link the
    /// PARENT's dispatch thunk; the subclass exports nothing of its own).
    private func collectOverrideImplementationSymbolNames() -> Set<String> {
        var names: Set<String> = []
        for descriptor in dumped.methodOverrideDescriptors {
            if let symbols = try? descriptor.implementationSymbols(in: machO) {
                for overrideSymbol in symbols {
                    names.insert(overrideSymbol.name)
                }
            }
        }
        for descriptor in dumped.methodDefaultOverrideDescriptors {
            if let symbols = try? descriptor.implementationSymbols(in: machO) {
                for overrideSymbol in symbols {
                    names.insert(overrideSymbol.name)
                }
            }
        }
        return names
    }

    package var name: SemanticString {
        get async throws {
            if let boundNode = boundDumpedTypeNode() {
                try await resolveBoundDumpedTypeName(boundNode)
            } else {
                try await _name(using: demangleResolver)
            }
        }
    }

    private var interfaceName: SemanticString {
        get async throws {
            try await _name(using: .options(.interface))
        }
    }

    @SemanticStringBuilder
    private func _name(using resolver: DemangleResolver) async throws -> SemanticString {
        if configuration.displayParentName {
            try await resolver.resolve(for: MetadataReader.demangleContext(for: .type(.class(dumped.descriptor)), in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .class, dumped.descriptor.name(in: machO))
        }
    }

    @SemanticStringBuilder
    private func dumpMethodKind(for descriptor: MethodDescriptor?) -> SemanticString? {
        if let descriptor {
            InlineComment("[\(descriptor.flags.kind)]")

            Space()
        }
    }

    @SemanticStringBuilder
    private func dumpMethodKeyword(for descriptor: MethodDescriptor, isDistributed: Bool = false) -> SemanticString {
        if !descriptor.flags.isInstance, descriptor.flags.kind != .`init` {
            // Every entry here has a vtable method descriptor, so a type-level one was declared `class`.
            Keyword(.class)
            Space()
        }

        if descriptor.flags.isDynamic {
            Keyword(.dynamic)
            Space()
        }

        if descriptor.flags.kind == .method {
            if isDistributed {
                Keyword(.distributed)
                Space()
            }
            Keyword(.func)
            Space()
        }
    }

    @SemanticStringBuilder
    private func dumpMethodDeclaration(for descriptor: MethodDescriptor, resolvedNode: NodeReference? = nil, visitedNodes: inout OrderedSet<StructuralNodeReferenceKey>) async throws -> SemanticString {
        let node: NodeReference?
        if let resolvedNode {
            node = resolvedNode
        } else if let symbols = try? descriptor.implementationSymbols(in: machO) {
            node = try await validNode(for: symbols, visitedNodes: visitedNodes)
        } else {
            node = nil
        }

        if let node {
            try await demangleResolver.resolve(for: node)
            _ = visitedNodes.append(StructuralNodeReferenceKey(node))
        } else if !descriptor.implementation.isNull {
            FunctionDeclaration(machO.addressString(forOffset: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))).insertSubFunctionPrefix)
        } else {
            Error("Symbol not found")
        }
    }

    /// Field names (lazy-stripped) whose getter/setter/modify/read accessors
    /// occupy vtable slots — i.e. the stored `var`s that were NOT declared
    /// `final`. Paired with `storedAccessorFieldNames(interfaceNameString:contextNode:)`
    /// (the evidence gate) by `fields` to recover the `final` keyword on the
    /// remaining stored `var`s (evolution proposal 0006).
    ///
    /// Two evidence sources, same as the model path in `TypeDefinition.index`:
    /// the descriptor→implementation-symbol resolution, plus the type's `Tq`
    /// method-descriptor symbols — per-member data symbols at unique
    /// addresses, immune to the identical-code-folding that can fold many
    /// accessor implementations onto one address and defeat the first source.
    private func vtableAccessorFieldNames(interfaceNameString: String, contextNode: Node?) -> Set<String> {
        var names: Set<String> = []
        let accessorKinds: Set<MethodDescriptorKind> = [.getter, .setter, .modifyCoroutine, .readCoroutine]
        for descriptor in dumped.methodDescriptors where accessorKinds.contains(descriptor.flags.kind) {
            guard let symbols = try? descriptor.implementationSymbols(in: machO) else { continue }
            for symbol in symbols {
                guard let node = MetadataReader.demangleSymbolReference(for: symbol, in: machO),
                      let variableName = node.first(of: .variable)?.identifier else { continue }
                names.insert(variableName)
            }
        }
        let variableKind: SymbolIndexStore.MemberKind = .variable(inExtension: false, isStatic: false, isStorage: false)
        let descriptorSymbols = if let contextNode {
            symbolIndexStore.methodDescriptorMemberSymbols(of: variableKind, for: interfaceNameString, node: contextNode, in: machO)
        } else {
            symbolIndexStore.methodDescriptorMemberSymbols(of: variableKind, for: interfaceNameString, in: machO)
        }
        for descriptorSymbol in descriptorSymbols {
            guard let variableName = descriptorSymbol.demangledNode.first(of: .variable)?.identifier else { continue }
            names.insert(variableName)
        }
        return names
    }

    /// Field names for which instance-variable accessor symbols exist at all —
    /// the evidence gate for `final` recovery: a name with no accessor symbol
    /// (stripped symbol table) cannot testify either way and stays unmarked.
    /// `@objc` members are excluded outright: without a vtable descriptor they
    /// dispatch through the ObjC runtime (`@objc dynamic`) — overridable, so
    /// never `final` (same exclusion as the model path in
    /// `TypeDefinition.index`).
    private func storedAccessorFieldNames(interfaceNameString: String, contextNode: Node?) -> Set<String> {
        var names: Set<String> = []
        let variableKind: SymbolIndexStore.MemberKind = .variable(inExtension: false, isStatic: false, isStorage: false)
        let accessorSymbols = if let contextNode {
            symbolIndexStore.memberSymbols(of: variableKind, for: interfaceNameString, node: contextNode, in: machO)
        } else {
            symbolIndexStore.memberSymbols(of: variableKind, for: interfaceNameString, in: machO)
        }
        for symbol in accessorSymbols {
            guard let variableName = symbol.demangledNode.first(of: .variable)?.identifier else { continue }
            names.insert(variableName)
        }
        let objcMembers = if let contextNode {
            symbolIndexStore.thunkAttributeMembers(of: .objCAttribute, for: interfaceNameString, node: contextNode, in: machO)
        } else {
            symbolIndexStore.thunkAttributeMembers(of: .objCAttribute, for: interfaceNameString, in: machO)
        }
        for objcMember in objcMembers where !objcMember.isStatic {
            names.remove(objcMember.memberName)
        }
        return names
    }

    package func validNode(for symbols: Symbols, visitedNodes: borrowing OrderedSet<StructuralNodeReferenceKey> = []) async throws -> NodeReference? {
        let currentInterfaceName = try await _name(using: .options(.interfaceType)).string
        for symbol in symbols {
            if let node = MetadataReader.demangleSymbolReference(for: symbol, in: machO), let classNode = node.first(of: .class), await classNode.print(using: .interfaceType) == currentInterfaceName, !visitedNodes.contains(StructuralNodeReferenceKey(node)) {
                return node
            }
        }
        return nil
    }

}
