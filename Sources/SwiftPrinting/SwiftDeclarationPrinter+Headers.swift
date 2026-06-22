import SwiftDeclaration
import MachOSwiftSection
import MachOKit
import Semantic
import Demangling
import OrderedCollections
import Dependencies
import SwiftDeclarationRendering
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

/// Model-driven declaration-header rendering for the interface path.
///
/// These mirror the header portion of `SwiftDump`'s `*Dumper.declaration`
/// getters but render the clean, **unbound** interface form straight from the
/// descriptor plus the shared `SwiftDeclarationRendering` helpers, so the
/// interface printer no longer instantiates a `SwiftDump` dumper. The dump path
/// keeps its own (address/offset-annotated, optionally generic-bound) header
/// rendering in `SwiftDump`; the two paths intentionally diverge.
@_spi(Support)
extension SwiftDeclarationPrinter {
    /// Renders a type's declaration header (`struct Foo<A> : Bar where …`),
    /// mirroring the matching `StructDumper`/`ClassDumper`/`EnumDumper`
    /// `declaration` getter in its unbound form.
    @SemanticStringBuilder
    package func renderTypeDeclarationHeader(for type: TypeContextWrapper, displayParentName: Bool, level: Int, leafNameNode: Node? = nil) async throws -> SemanticString {
        let resolver = typeDemangleResolver
        switch type {
        case .struct(let dumped):
            Keyword(.struct)
            Space()
            try await renderUnboundTypeName(.struct, descriptorWrapper: .type(.struct(dumped.descriptor)), name: dumped.descriptor.name(in: machO), displayParentName: displayParentName, leafNameNode: leafNameNode, resolver: resolver)
            try await renderGenericSignatureWithInvertibles(genericContext: dumped.genericContext, invertibleProtocolSet: dumped.invertibleProtocolSet, resolver: resolver)
        case .enum(let dumped):
            Keyword(.enum)
            Space()
            try await renderUnboundTypeName(.enum, descriptorWrapper: .type(.enum(dumped.descriptor)), name: dumped.descriptor.name(in: machO), displayParentName: displayParentName, leafNameNode: leafNameNode, resolver: resolver)
            try await renderGenericSignatureWithInvertibles(genericContext: dumped.genericContext, invertibleProtocolSet: dumped.invertibleProtocolSet, resolver: resolver)
        case .class(let dumped):
            if dumped.descriptor.isActor {
                if isDistributedActor(dumped) {
                    Keyword(.distributed)
                    Space()
                }
                Keyword(.actor)
            } else {
                Keyword(.class)
            }
            Space()
            try await renderUnboundTypeName(.class, descriptorWrapper: .type(.class(dumped.descriptor)), name: dumped.descriptor.name(in: machO), displayParentName: displayParentName, leafNameNode: leafNameNode, resolver: resolver)
            let superclass = try await renderClassSuperclass(dumped, resolver: resolver)
            if let genericContext = dumped.genericContext {
                try await genericContext.dumpGenericSignature(resolver: resolver, in: machO) {
                    superclass
                }
            } else {
                superclass
            }
        }
    }

    @SemanticStringBuilder
    private func renderGenericSignatureWithInvertibles(genericContext: TypeGenericContext?, invertibleProtocolSet: InvertibleProtocolSet?, resolver: DemangleResolver) async throws -> SemanticString {
        if let genericContext {
            try await genericContext.dumpGenericSignature(resolver: resolver, in: machO) {
                if let invertibleProtocolSet, invertibleProtocolSet.hasInvertedProtocols {
                    invertibleProtocolSet.dumpInvertedProtocolsInheritance
                }
            }
        } else if let invertibleProtocolSet, invertibleProtocolSet.hasInvertedProtocols {
            invertibleProtocolSet.dumpInvertedProtocolsInheritance
        }
    }

    @SemanticStringBuilder
    private func renderUnboundTypeName(_ kind: SemanticType.TypeKind, descriptorWrapper: ContextDescriptorWrapper, name: String, displayParentName: Bool, leafNameNode: Node?, resolver: DemangleResolver) async throws -> SemanticString {
        if displayParentName {
            try await resolver.resolve(for: MetadataReader.demangleContext(for: descriptorWrapper, in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            renderLeafName(kind: kind, bareName: name, leafNameNode: leafNameNode)
        }
    }

    /// Renders a declaration's own leaf name. For an ordinary type this is just
    /// `TypeDeclaration(kind, bareName)`; for a `private`/`fileprivate` type whose
    /// leaf name demangles to a `.privateDeclName`, the build-specific
    /// discriminator is surfaced as `(Name in _ABC)` by printing the leaf node with
    /// `.showPrivateDiscriminators`. Without it a discriminator-only difference
    /// between two builds renders as two identical bare names, making a nested
    /// private type look wholly changed when only its discriminator moved. Both
    /// `.default` printing and the descriptor `name` elide the discriminator, so
    /// re-including it requires that explicit option on the leaf node. `leafNameNode`
    /// is `nil` on the normal (non-diff) print path, which keeps the bare name.
    @SemanticStringBuilder
    private func renderLeafName(kind: SemanticType.TypeKind, bareName: String, leafNameNode: Node?) -> SemanticString {
        if let leafNameNode, leafNameNode.kind == .privateDeclName {
            leafNameNode.printSemantic(using: [.showPrivateDiscriminators])
        } else {
            TypeDeclaration(kind: kind, bareName)
        }
    }

    @SemanticStringBuilder
    private func renderClassSuperclass(_ dumped: Class, resolver: DemangleResolver) async throws -> SemanticString {
        let hasInvertedProtocols = dumped.invertibleProtocolSet?.hasInvertedProtocols ?? false
        if let superclassMangledName = try dumped.descriptor.superclassTypeMangledName(in: machO) {
            Standard(":")
            Space()
            try await resolver.resolve(for: MetadataReader.demangleType(for: superclassMangledName, in: machO))
            if hasInvertedProtocols {
                Standard(",")
                Space()
                dumped.invertibleProtocolSet!.dumpInvertedProtocolNames
            }
        } else if let resilientSuperclass = dumped.resilientSuperclass, let kind = dumped.descriptor.resilientSuperclassReferenceKind, let superclass = try await resilientSuperclass.dumpSuperclass(resolver: resolver, for: kind, in: machO) {
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

    /// True when an `actor` class has at least one `distributedThunk` symbol
    /// whose class context matches it — mirroring `ClassDumper.isDistributedActor`.
    private func isDistributedActor(_ dumped: Class) -> Bool {
        guard dumped.descriptor.isActor else { return false }
        @Dependency(\.symbolIndexStore) var symbolIndexStore

        guard let currentTypeNode = try? MetadataReader.demangleContext(for: .type(.class(dumped.descriptor)), in: machO) else { return false }
        let currentTypeName = currentTypeNode.print(using: .interfaceTypeBuilderOnly)

        for thunkSymbol in symbolIndexStore.symbols(of: .distributedThunk, in: machO) {
            let rootNode = thunkSymbol.demangledNode
            guard let functionNode = rootNode.children.first(where: { $0.kind != .distributedThunk }) else { continue }
            guard let contextNode = functionNode.children.first else { continue }
            let thunkTypeName = Node.create(kind: .type, child: contextNode).print(using: .interfaceTypeBuilderOnly)
            if thunkTypeName == currentTypeName {
                return true
            }
        }
        return false
    }

    // MARK: - Protocol header

    /// Renders a protocol's declaration header (`protocol Foo : Bar where …`),
    /// mirroring `ProtocolDumper.declaration`.
    @SemanticStringBuilder
    package func renderProtocolDeclarationHeader(for dumped: MachOSwiftSection.`Protocol`, displayParentName: Bool, leafNameNode: Node? = nil) async throws -> SemanticString {
        let resolver = typeDemangleResolver
        Keyword(.protocol)
        Space()
        if displayParentName {
            try await resolver.resolve(for: MetadataReader.demangleContext(for: .protocol(dumped.descriptor), in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            renderLeafName(kind: .protocol, bareName: try dumped.descriptor.name(in: machO), leafNameNode: leafNameNode)
        }

        if dumped.numberOfRequirementsInSignature > 0 {
            var requirementInSignatures = dumped.requirementInSignatures
            for (offset, requirement) in requirementInSignatures.extract(where: \.isProtocolInherited).offsetEnumerated() {
                if offset.isStart {
                    Standard(":")
                } else {
                    Standard(",")
                }
                Space()
                try await requirement.descriptor.dumpContent(resolver: resolver, in: machO)
            }
            if !requirementInSignatures.isEmpty {
                Space()
                Keyword(.where)
                Space()

                for (offset, requirement) in requirementInSignatures.offsetEnumerated() {
                    try await requirement.descriptor.dumpProtocolRequirement(resolver: resolver, in: machO)
                    if !offset.isEnd {
                        Standard(",")
                        Space()
                    }
                }
            }
        }
    }

    /// Renders a protocol's `associatedtype` requirement lines, mirroring
    /// `ProtocolDumper.associatedTypes`.
    @SemanticStringBuilder
    func renderProtocolAssociatedTypes(for dumped: MachOSwiftSection.`Protocol`, level: Int) async throws -> SemanticString {
        let associatedTypes = try dumped.descriptor.associatedTypes(in: machO)
        if !associatedTypes.isEmpty {
            for (offset, associatedType) in associatedTypes.offsetEnumerated() {
                BreakLine()
                Indent(level: level)
                Keyword(.associatedtype)
                Space()
                TypeDeclaration(kind: .other, associatedType)
                if offset.isEnd {
                    BreakLine()
                }
            }
        }
    }

    // MARK: - Extension merged associated-type typealiases

    /// Emits a deduplicated `typealias` block collected from sibling
    /// conformances, mirroring `AssociatedTypeDumper.mergedRecords`.
    @SemanticStringBuilder
    func renderMergedAssociatedTypeRecords(of associatedTypes: [AssociatedType], level: Int) async throws -> SemanticString {
        let resolver = typeDemangleResolver
        let orderedRecords = collectUniqueAssociatedTypeRecords(of: associatedTypes)
        for (offset, record) in orderedRecords.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            Keyword(.typealias)
            Space()
            TypeDeclaration(kind: .other, record.name)
            Space()
            Standard("=")
            Space()
            try await resolver.resolve(for: MetadataReader.demangleType(for: record.mangledTypeName, in: machO).resolveOpaqueType(in: machO))
            if offset.isEnd {
                BreakLine()
            }
        }
    }

    private struct AssociatedTypeRecordDedupKey: Hashable {
        let name: String
        let mangledTypeName: MangledName
    }

    private func collectUniqueAssociatedTypeRecords(of associatedTypes: [AssociatedType]) -> [(name: String, mangledTypeName: MangledName)] {
        var seenKeys: Set<AssociatedTypeRecordDedupKey> = []
        var orderedRecords: [(name: String, mangledTypeName: MangledName)] = []
        for associatedType in associatedTypes {
            for record in associatedType.records {
                let recordName: String
                let mangledTypeName: MangledName
                do {
                    recordName = try record.name(in: machO)
                    mangledTypeName = try record.substitutedTypeName(in: machO)
                } catch {
                    continue
                }
                if seenKeys.insert(AssociatedTypeRecordDedupKey(name: recordName, mangledTypeName: mangledTypeName)).inserted {
                    orderedRecords.append((recordName, mangledTypeName))
                }
            }
        }
        return orderedRecords
    }

    // MARK: - Model-driven stored fields / enum cases

    /// Renders a type's stored fields (struct/class) or cases (enum) straight from
    /// the indexed `SwiftDeclaration` model, replacing the `*Dumper.fields` blob.
    /// Mirrors the dumpers' `BreakLine` + `Indent` per-record framing.
    ///
    /// Per-field metadata comments (`// Field offset:`, `// Type Layout:`, the
    /// expanded nested-offset tree) are emitted through the shared
    /// `FieldLayoutRenderer` in `SwiftDeclarationRendering` — the same source the
    /// `SwiftDump` dumpers use — gated on the configuration flags. With the flags
    /// off (the clean interface form) nothing extra is emitted; with them on
    /// (e.g. RuntimeViewer / dump-parity callers) the comments match the
    /// former dumper-delegated output.
    @SemanticStringBuilder
    func renderModelFields(_ typeDefinition: TypeDefinition, level: Int) async -> SemanticString {
        let isEnum = typeDefinition.typeName.kind == .enum

        // Shared metadata-comment renderer (single source of truth with
        // `SwiftDump`'s dumpers). `indentation: level` keeps the comments aligned
        // with the field declarations at this nesting depth, matching the former
        // dumper-delegated output.
        let renderConfiguration = DeclarationRenderConfiguration(
            demangleResolver: typeDemangleResolver,
            indentation: level,
            printFieldOffset: configuration.printFieldOffset,
            printTypeLayout: configuration.printTypeLayout,
            printEnumLayout: configuration.printEnumLayout,
            printExpandedFieldOffsets: configuration.printExpandedFieldOffsets,
            fieldOffsetTransformer: configuration.fieldOffsetTransformer,
            expandedFieldOffsetTransformer: configuration.expandedFieldOffsetTransformer,
            typeLayoutTransformer: configuration.typeLayoutTransformer,
            enumLayoutTransformer: configuration.enumLayoutTransformer,
            enumLayoutCaseTransformer: configuration.enumLayoutCaseTransformer,
            staticFieldLayoutProvider: staticFieldLayoutProvider(),
            staticLayoutDependencyResolution: configuration.staticLayoutDependencyResolution
        )
        let fieldLayoutRenderer = FieldLayoutRenderer(type: typeDefinition.type, metadata: typeDefinition.metadata, machO: machO, configuration: renderConfiguration)
        let fieldRecords = (try? typeDefinition.type.contextDescriptorWrapper.typeContextDescriptor?.fieldDescriptor(in: machO).records(in: machO)) ?? []
        let fieldOffsets = isEnum ? nil : fieldLayoutRenderer.fieldOffsets

        let enumLayout = isEnum ? await fieldLayoutRenderer.enumLayout : nil

        // Type-level enum prologue (Enum Layout strategy + spare-bit summary),
        // emitted once before the cases — mirrors `EnumDumper.fields`.
        if isEnum {
            await fieldLayoutRenderer.enumPrefixComments(enumLayout: enumLayout)
        }

        for (offset, field) in typeDefinition.fields.offsetEnumerated() {
            BreakLine()
            // Per-record metadata comments (single source of truth with the
            // `SwiftDump` dumpers): struct/class fields get the offset +
            // type-layout block; enum cases get the type-layout + enum-layout
            // block.
            if let record = fieldRecords[safe: offset.index], let mangledTypeName = try? record.mangledTypeName(in: machO) {
                if isEnum {
                    await fieldLayoutRenderer.enumCaseComments(forCaseAtIndex: offset.index, mangledTypeName: mangledTypeName, enumLayout: enumLayout)
                } else {
                    await fieldLayoutRenderer.storedFieldComments(forFieldAtIndex: offset.index, mangledTypeName: mangledTypeName, fieldOffsets: fieldOffsets)
                }
            }
            Indent(level: level)
            if isEnum {
                await printEnumCase(field, level: level)
            } else {
                await printField(field, level: level)
            }
            if offset.isEnd {
                BreakLine()
            }
        }
    }
}
