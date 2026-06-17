import Foundation
import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import Utilities
@_spi(Internals) import SwiftInspection

/// Maximum recursion depth that the nested expanded-field-offset walk will
/// descend before bailing out. Mirrors the bound formerly hosted on
/// `SwiftDump.TypedDumper`; kept in `SwiftDeclarationRendering` so both the
/// raw-descriptor dump path and the model-driven interface path share one
/// implementation (single source of truth).
package let nestedFieldOffsetExpansionDepthLimit = 16

/// Shared renderer for the *metadata-derived* field comments of a nominal type —
/// `// Field offset:`, `// Type Layout:`, and the expanded nested-field-offset
/// tree. The logic was lifted out of `SwiftDump`'s `StructDumper` / `ClassDumper`
/// (and the `TypedDumper` helpers) so the model-driven `SwiftDeclarationPrinter`
/// can emit the same comments without depending on `SwiftDump` — `SwiftDump`'s
/// dumpers and `SwiftPrinting`'s printer now both route through this type.
///
/// It deliberately avoids the generic `Metadata` parameter the dumpers carry:
/// the field-offset vector is read from the supplied (already-typed) metadata
/// wrapper, and per-field metatype resolution is parameterised by the type's
/// generic-ness + the optional specialized metadata, so a single concrete type
/// serves struct, class, value, and class-metadata callers alike.
package struct FieldLayoutRenderer<MachO: MachOSwiftSectionRepresentableWithCache> {
    package let type: TypeContextWrapper
    package let metadata: MetadataWrapper?
    package let machO: MachO
    package let configuration: DeclarationRenderConfiguration

    /// Whether the *dumped* type is generic. Drives the substitution policy in
    /// `resolveFieldMetatype` — generic types substitute against `metadata`,
    /// non-generic types resolve the bare mangled name.
    package let isGeneric: Bool

    /// - Parameters:
    ///   - providedMetadata: a caller-supplied (typically specialized) metadata
    ///     to read field offsets / drive substitution from.
    ///   - autoResolveAccessorMetadata: when `true` and no metadata is supplied,
    ///     a *non-generic* type's runtime metadata is resolved through its
    ///     accessor function (only succeeds in-process / for MachOImage) — this
    ///     mirrors `TypeContextWrapper.dumper(using:metadata:in:)` and is what
    ///     the model-driven printer wants. When `false` (the raw-descriptor dump
    ///     path), a `nil` metadata stays `nil` so the bare dumper keeps its "no
    ///     metadata context ⇒ no offsets" contract.
    package init(type: TypeContextWrapper, metadata providedMetadata: MetadataWrapper?, machO: MachO, configuration: DeclarationRenderConfiguration, autoResolveAccessorMetadata: Bool = true) {
        self.type = type
        self.machO = machO
        self.configuration = configuration

        let isGeneric: Bool
        switch type {
        case .struct(let structType):
            isGeneric = structType.descriptor.isGeneric
        case .enum(let enumType):
            isGeneric = enumType.descriptor.isGeneric
        case .class(let classType):
            isGeneric = classType.descriptor.isGeneric
        }
        self.isGeneric = isGeneric

        if let providedMetadata {
            self.metadata = providedMetadata
        } else if isGeneric || !autoResolveAccessorMetadata {
            self.metadata = nil
        } else {
            self.metadata = try? FieldLayoutRenderer.resolveAccessorMetadata(for: type, in: machO)
        }
    }

    private static func resolveAccessorMetadata(for type: TypeContextWrapper, in machO: MachO) throws -> MetadataWrapper? {
        switch type {
        case .struct(let structType):
            return try structType.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO)
        case .enum(let enumType):
            return try enumType.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO)
        case .class(let classType):
            return try classType.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO)
        }
    }

    /// `MachOContext` for non-generic types, `InProcessContext.shared` for
    /// specialized generic metadata — mirrors `TypeContextWrapper.dumper`'s
    /// reading-context selection so `fieldOffsets(for:in:)` reads from the
    /// right backing store.
    private var readingContext: any ReadingContext {
        isGeneric ? InProcessContext.shared : MachOContext(machO)
    }

    // MARK: - Field offsets (struct / class)

    /// The resolved field-offset vector for a struct or class, or `nil` when
    /// offsets are disabled, no metadata is available, or the type is not a
    /// stored-field aggregate.
    package var fieldOffsets: [Int]? {
        guard configuration.printFieldOffset, let metadata else { return nil }
        switch type {
        case .struct(let structType):
            guard let structMetadata = metadata.struct else { return nil }
            return try? structMetadata.fieldOffsets(for: structType.descriptor, in: readingContext).map { $0.cast() }
        case .class(let classType):
            guard let classMetadata = metadata.class else { return nil }
            return try? classMetadata.fieldOffsets(for: classType.descriptor, in: readingContext).map { $0.cast() }
        case .enum:
            return nil
        }
    }

    /// Renders the comment block that precedes a single stored field of a struct
    /// or class — the `// Field offset:` line (with end offset), the expanded
    /// nested-offset tree, and the `// Type Layout:` block. `fieldOffsets` is
    /// passed in so the caller computes it once per type.
    @SemanticStringBuilder
    package func storedFieldComments(
        forFieldAtIndex index: Int,
        mangledTypeName: MangledName,
        fieldOffsets: [Int]?
    ) async -> SemanticString {
        if let fieldOffsets, let startOffset = fieldOffsets[safe: index] {
            let endOffset: Int?
            if let nextFieldOffset = fieldOffsets[safe: index + 1] {
                endOffset = nextFieldOffset
            } else if let machOImage = machO.asMachOImage,
                      let metatype = resolveFieldMetatype(for: mangledTypeName, in: machOImage),
                      let typeLayout = try? StructMetadata.createInProcess(metatype).asMetadataWrapper().valueWitnessTable().typeLayout {
                endOffset = startOffset + Int(typeLayout.size)
            } else {
                endOffset = nil
            }
            configuration.fieldOffsetComment(startOffset: startOffset, endOffset: endOffset)

            if configuration.printExpandedFieldOffsets, let machOImage = machO.asMachOImage {
                expandedFieldOffsets(for: mangledTypeName, baseOffset: startOffset, baseIndentation: configuration.indentation, ancestors: [], in: machOImage)
            }
        }

        if configuration.printTypeLayout,
           let machOImage = machO.asMachOImage,
           let resolvedMetatype = resolveFieldMetatype(for: mangledTypeName, in: machOImage),
           let resolvedMetadata = try? StructMetadata.createInProcess(resolvedMetatype) {
            try? await resolvedMetadata.asMetadataWrapper().dumpTypeLayout(using: configuration)
        }
    }

    // MARK: - Enum cases

    /// Renders the comment block that precedes a single enum case — the
    /// `// Type Layout:` block for the case's payload, then (when an
    /// `enumLayout` projection is supplied) the per-case `Enum Layout` comment.
    /// Mirrors `EnumDumper.fields`' per-record ordering exactly.
    @SemanticStringBuilder
    package func enumCaseComments(
        forCaseAtIndex index: Int,
        mangledTypeName: MangledName,
        enumLayout: EnumLayoutCalculator.LayoutResult?
    ) async -> SemanticString {
        var isTypeLayoutPrinted = false

        if !mangledTypeName.isEmpty,
           configuration.printTypeLayout,
           let machOImage = machO.asMachOImage,
           let resolvedMetatype = resolveFieldMetatype(for: mangledTypeName, in: machOImage),
           let resolvedMetadata = try? StructMetadata.createInProcess(resolvedMetatype) {
            try? await resolvedMetadata.asMetadataWrapper().dumpTypeLayout(using: configuration)
            isTypeLayoutPrinted = true
        }

        if let caseProjection = enumLayout?.cases[safe: index] {
            if isTypeLayoutPrinted {
                BreakLine()
            }
            configuration.indentString
            InlineComment("Enum Layout")
            BreakLine()
            configuration.enumLayoutCaseComment(caseProjection: caseProjection)
        }
    }

    // MARK: - Field metatype resolution

    /// Resolves a field's mangled type name to a concrete `Any.Type`. Non-generic
    /// types resolve the bare name; generic types substitute against the type's
    /// specialized in-process metadata. Mirrors the constrained
    /// `TypedDumper.resolveFieldMetatype` implementations (which were identical
    /// for value and class metadata).
    package func resolveFieldMetatype(for mangledTypeName: MangledName, in machOImage: MachOImage) -> Any.Type? {
        if !isGeneric {
            return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machOImage)
        }
        if let structMetadata = metadata?.struct {
            return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, specializedFrom: structMetadata, in: machOImage)
        }
        if let enumMetadata = metadata?.enum ?? metadata?.optional {
            return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, specializedFrom: enumMetadata, in: machOImage)
        }
        if let classMetadata = metadata?.class {
            return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, specializedFrom: classMetadata, in: machOImage)
        }
        return nil
    }

    // MARK: - Expanded nested field offsets
    //
    // Lifted verbatim from `SwiftDump.TypedDumper`; behaviour-preserving. The
    // only changes: `Metadata.createInProcess` → `StructMetadata.createInProcess`
    // (the static metadata type is incidental — `asMetadataWrapper()` re-dispatches
    // on the actual kind), and the top-hop substitution goes through this type's
    // `resolveFieldMetatype`. See the original for the extensive rationale on the
    // PAC-fault-avoiding static substitution.

    @SemanticStringBuilder
    package func expandedFieldOffsets(for mangledTypeName: MangledName, baseOffset: Int, baseIndentation: Int, ancestors: [Bool], in machO: MachOImage?) -> SemanticString {
        let topMetatype: Any.Type?
        if let machO {
            topMetatype = resolveFieldMetatype(for: mangledTypeName, in: machO)
                ?? (try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machO))
        } else {
            topMetatype = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName)
        }
        if let topMetatype {
            walkNestedExpandedFieldOffsets(of: topMetatype, baseOffset: baseOffset, baseIndentation: baseIndentation, ancestors: ancestors)
        }
    }

    @SemanticStringBuilder
    private func walkNestedExpandedFieldOffsets(of metatype: Any.Type, baseOffset: Int, baseIndentation: Int, ancestors: [Bool], depth: Int = 0) -> SemanticString {
        if depth >= nestedFieldOffsetExpansionDepthLimit {
            SemanticString()
        } else if let wrapper = try? StructMetadata.createInProcess(metatype).asMetadataWrapper() {
            switch wrapper {
            case .struct(let metadata):
                walkNestedStructFieldOffsets(of: metadata, baseOffset: baseOffset, baseIndentation: baseIndentation, ancestors: ancestors, depth: depth)
            case .enum(let metadata),
                 .optional(let metadata):
                walkNestedEnumPayloadFieldOffsets(of: metadata, baseOffset: baseOffset, baseIndentation: baseIndentation, ancestors: ancestors, depth: depth)
            default:
                SemanticString()
            }
        }
    }

    @SemanticStringBuilder
    private func walkNestedStructFieldOffsets(of metadata: StructMetadata, baseOffset: Int, baseIndentation: Int, ancestors: [Bool], depth: Int) -> SemanticString {
        if let descriptor = try? metadata.structDescriptor(),
           let nestedFieldOffsets = try? metadata.fieldOffsets(for: descriptor),
           let nestedFieldRecords = try? descriptor.fieldDescriptor().records() {
            let fieldEntries = Array(zip(nestedFieldRecords, nestedFieldOffsets))
            for (fieldIndex, (nestedFieldRecord, nestedRelativeOffset)) in fieldEntries.enumerated() {
                if let fieldName = try? nestedFieldRecord.fieldName() {
                    let absoluteOffset = baseOffset + Int(nestedRelativeOffset)
                    let isLastField = fieldIndex == fieldEntries.count - 1
                    let nestedMangledTypeName = try? nestedFieldRecord.mangledTypeName()
                    let typeName = nestedTypeName(for: nestedMangledTypeName, parentMetadata: metadata)
                    configuration.expandedFieldOffsetComment(fieldName: fieldName, typeName: typeName, offset: absoluteOffset, baseIndentation: baseIndentation, ancestors: ancestors, isLast: isLastField)

                    if let nestedMangledTypeName,
                       let resolvedMetatype = resolveNestedMetatype(for: nestedMangledTypeName, parentMetadata: metadata) {
                        walkNestedExpandedFieldOffsets(of: resolvedMetatype, baseOffset: absoluteOffset, baseIndentation: baseIndentation, ancestors: ancestors + [isLastField], depth: depth + 1)
                    }
                }
            }
        }
    }

    @SemanticStringBuilder
    private func walkNestedEnumPayloadFieldOffsets(of metadata: EnumMetadata, baseOffset: Int, baseIndentation: Int, ancestors: [Bool], depth: Int) -> SemanticString {
        if let descriptor = try? metadata.enumDescriptor(),
           descriptor.hasPayloadCases,
           let records = try? descriptor.fieldDescriptor().records() {
            let payloadRecords = Array(records.prefix(descriptor.numberOfPayloadCases))
            for (payloadIndex, payloadRecord) in payloadRecords.enumerated() {
                if let mangledTypeName = try? payloadRecord.mangledTypeName(),
                   !mangledTypeName.isEmpty,
                   let resolvedMetatype = resolveNestedMetatype(for: mangledTypeName, parentMetadata: metadata) {
                    let fieldName = (try? payloadRecord.fieldName()) ?? "payload"
                    let typeName = nestedTypeName(for: mangledTypeName, parentMetadata: metadata)
                    let isLastPayload = payloadIndex == payloadRecords.count - 1
                    configuration.expandedFieldOffsetComment(fieldName: fieldName, typeName: typeName, offset: baseOffset, baseIndentation: baseIndentation, ancestors: ancestors, isLast: isLastPayload)
                    walkNestedExpandedFieldOffsets(of: resolvedMetatype, baseOffset: baseOffset, baseIndentation: baseIndentation, ancestors: ancestors + [isLastPayload], depth: depth + 1)
                }
            }
        }
    }

    private func resolveNestedMetatype<ParentMetadata: ValueMetadataProtocol>(for mangledTypeName: MangledName, parentMetadata: ParentMetadata) -> Any.Type? {
        if let boundType = staticallyBoundMetatype(for: mangledTypeName, parentMetadata: parentMetadata) {
            return boundType
        }
        guard let node = try? MetadataReader.demangleTypeUncached(for: mangledTypeName),
              !nodeContainsDependentReference(node)
        else { return nil }
        return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName)
    }

    private func nestedTypeName<ParentMetadata: ValueMetadataProtocol>(for mangledTypeName: MangledName?, parentMetadata: ParentMetadata) -> String {
        guard let mangledTypeName else { return "" }
        if let substitutedNode = substitutedNestedTypeNode(for: mangledTypeName, parentMetadata: parentMetadata) {
            return substitutedNode.printSemantic(using: .default).string
        }
        return (try? MetadataReader.demangleTypeUncached(for: mangledTypeName).printSemantic(using: .default).string) ?? ""
    }

    // MARK: - Static generic-argument substitution (PAC-fault-avoiding)

    private func substitutedNestedTypeNode<ParentMetadata: ValueMetadataProtocol>(for mangledTypeName: MangledName, parentMetadata: ParentMetadata) -> Node? {
        guard let node = try? MetadataReader.demangleTypeUncached(for: mangledTypeName) else { return nil }
        guard let keyArgumentFlags = topLevelGenericKeyArgumentFlags(of: parentMetadata) else {
            return node
        }
        let keyArgumentCount = keyArgumentFlags.lazy.filter { $0 }.count
        return substitutingGenericParameters(in: node, parentMetadata: parentMetadata, keyArgumentFlags: keyArgumentFlags, keyArgumentCount: keyArgumentCount)
    }

    private func staticallyBoundMetatype<ParentMetadata: ValueMetadataProtocol>(for mangledTypeName: MangledName, parentMetadata: ParentMetadata) -> Any.Type? {
        guard let node = try? MetadataReader.demangleTypeUncached(for: mangledTypeName) else { return nil }
        let typeNode = innerTypeNode(of: node)
        guard typeNode.kind == .dependentGenericParamType,
              let (depthValue, indexValue) = genericParameterDepthAndIndex(of: typeNode),
              depthValue == 0,
              let keyArgumentFlags = topLevelGenericKeyArgumentFlags(of: parentMetadata),
              let flatIndex = depthZeroFlatIndex(forIndex: indexValue, keyArgumentFlags: keyArgumentFlags)
        else { return nil }
        let keyArgumentCount = keyArgumentFlags.lazy.filter { $0 }.count
        return boundGenericArgumentType(at: flatIndex, keyArgumentCount: keyArgumentCount, of: parentMetadata)
    }

    private func substitutingGenericParameters<ParentMetadata: ValueMetadataProtocol>(in node: Node, parentMetadata: ParentMetadata, keyArgumentFlags: [Bool], keyArgumentCount: Int) -> Node {
        if #available(macOS 11, iOS 14, tvOS 14, watchOS 7, *),
           node.kind == .dependentGenericParamType,
           let (depthValue, indexValue) = genericParameterDepthAndIndex(of: node),
           depthValue == 0,
           let flatIndex = depthZeroFlatIndex(forIndex: indexValue, keyArgumentFlags: keyArgumentFlags),
           let argumentType = boundGenericArgumentType(at: flatIndex, keyArgumentCount: keyArgumentCount, of: parentMetadata),
           let argumentMangledString = _mangledTypeName(argumentType),
           let argumentNode = try? demangleAsNode(argumentMangledString, isType: true) {
            return innerTypeNode(of: argumentNode)
        }
        let substitutedChildren = node.children.map {
            substitutingGenericParameters(in: $0, parentMetadata: parentMetadata, keyArgumentFlags: keyArgumentFlags, keyArgumentCount: keyArgumentCount)
        }
        return Node.create(kind: node.kind, contents: node.contents, children: Array(substitutedChildren))
    }

    private func boundGenericArgumentType<ParentMetadata: ValueMetadataProtocol>(at flatIndex: Int, keyArgumentCount: Int, of parentMetadata: ParentMetadata) -> Any.Type? {
        guard flatIndex >= 0, flatIndex < keyArgumentCount else { return nil }
        guard let metadataPointer = try? parentMetadata.asPointer else { return nil }
        let genericArgumentsBase = metadataPointer.advanced(by: MemoryLayout<ParentMetadata.Layout>.size)
        let argumentBitPattern = genericArgumentsBase.load(fromByteOffset: flatIndex * MemoryLayout<UInt>.size, as: UInt.self)
        guard argumentBitPattern != 0, let argumentPointer = UnsafeRawPointer(bitPattern: argumentBitPattern) else { return nil }
        return unsafeBitCast(argumentPointer, to: Any.Type.self)
    }

    private func topLevelGenericKeyArgumentFlags<ParentMetadata: ValueMetadataProtocol>(of parentMetadata: ParentMetadata) -> [Bool]? {
        guard let descriptor = try? parentMetadata.descriptor(),
              let genericContext = try? descriptor.genericContext(),
              let topLevelParameters = genericContext.allParameters.first
        else { return nil }
        return topLevelParameters.map(\.hasKeyArgument)
    }

    private func depthZeroFlatIndex(forIndex index: Int, keyArgumentFlags: [Bool]) -> Int? {
        guard index >= 0, index < keyArgumentFlags.count, keyArgumentFlags[index] else { return nil }
        return keyArgumentFlags[0..<index].lazy.filter { $0 }.count
    }

    private func genericParameterDepthAndIndex(of node: Node) -> (depth: Int, index: Int)? {
        let children = Array(node.children)
        guard children.count == 2,
              let depthValue = children[0].index,
              let indexValue = children[1].index
        else { return nil }
        return (Int(depthValue), Int(indexValue))
    }

    private func innerTypeNode(of node: Node) -> Node {
        if node.kind == .type, let firstChild = node.firstChild {
            return firstChild
        }
        return node
    }

    private func nodeContainsDependentReference(_ node: Node) -> Bool {
        switch node.kind {
        case .dependentGenericParamType, .dependentMemberType, .dependentAssociatedTypeRef:
            return true
        default:
            return node.children.contains { nodeContainsDependentReference($0) }
        }
    }
}
