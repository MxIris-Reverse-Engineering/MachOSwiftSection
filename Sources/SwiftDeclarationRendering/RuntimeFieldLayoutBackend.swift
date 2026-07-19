import Foundation
import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import SwiftLayout
import Utilities
@_spi(Internals) import SwiftInspection

/// `MachOImage` renders field comments from **in-process runtime metadata**.
extension MachOImage: FieldLayoutRenderable {
    public static func makeStaticFieldLayoutProvider(machO: MachOImage, resolution: StaticLayoutDependencyResolution) -> (any StaticFieldLayoutProvider)? {
        // The in-process path renders from runtime metadata, not SwiftLayout.
        nil
    }

    public static func precomputedStaticAggregateFieldLayout(for type: TypeContextWrapper, machO: MachOImage, configuration: DeclarationRenderConfiguration) -> AggregateFieldLayout? {
        // The runtime path reads offsets from materialized metadata, not from a
        // statically-precomputed aggregate.
        nil
    }

    public static func renderFieldOffsets(_ state: FieldLayoutRenderState, machO: MachOImage) -> [Int]? {
        RuntimeFieldLayoutBackend(state, machO: machO).fieldOffsets
    }

    public static func renderStoredFieldComments(_ state: FieldLayoutRenderState, machO: MachOImage, forFieldAtIndex index: Int, mangledTypeName: MangledName, fieldOffsets: [Int]?) async -> SemanticString {
        await RuntimeFieldLayoutBackend(state, machO: machO).storedFieldComments(forFieldAtIndex: index, mangledTypeName: mangledTypeName, fieldOffsets: fieldOffsets)
    }

    public static func renderEnumLayout(_ state: FieldLayoutRenderState, machO: MachOImage) async -> EnumLayoutCalculator.LayoutResult? {
        await RuntimeFieldLayoutBackend(state, machO: machO).enumLayout
    }

    public static func renderEnumPrefixComments(_ state: FieldLayoutRenderState, machO: MachOImage, enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString {
        await RuntimeFieldLayoutBackend(state, machO: machO).enumPrefixComments(enumLayout: enumLayout)
    }

    public static func renderEnumCaseComments(_ state: FieldLayoutRenderState, machO: MachOImage, forCaseAtIndex index: Int, mangledTypeName: MangledName, enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString {
        await RuntimeFieldLayoutBackend(state, machO: machO).enumCaseComments(forCaseAtIndex: index, mangledTypeName: mangledTypeName, enumLayout: enumLayout)
    }
}

/// The **runtime** (in-process) backend, used when the Mach-O reader is a
/// `MachOImage`. It materializes metadata in-process — `StructMetadata.createInProcess`,
/// value-witness tables, and `RuntimeFunctions.getTypeByMangledNameInContext` —
/// so it works only for an image loaded into the running process (e.g.
/// RuntimeViewer). Behaviour is the pre-split implementation, verbatim; the
/// convenience forwarders below let the method bodies reference `machO` /
/// `metadata` / `type` / `configuration` / `isGeneric` / `enumValue` unchanged.
struct RuntimeFieldLayoutBackend {
    let state: FieldLayoutRenderState
    let machO: MachOImage

    init(_ state: FieldLayoutRenderState, machO: MachOImage) {
        self.state = state
        self.machO = machO
    }

    private var type: TypeContextWrapper { state.type }
    private var metadata: MetadataWrapper? { state.metadata }
    private var configuration: DeclarationRenderConfiguration { state.configuration }
    private var isGeneric: Bool { state.isGeneric }
    private var enumValue: Enum? { state.enumValue }

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
    var fieldOffsets: [Int]? {
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

    @SemanticStringBuilder
    func storedFieldComments(
        forFieldAtIndex index: Int,
        mangledTypeName: MangledName,
        fieldOffsets: [Int]?
    ) async -> SemanticString {
        if let fieldOffsets, let startOffset = fieldOffsets[safe: index] {
            let endOffset: Int?
            if let nextFieldOffset = fieldOffsets[safe: index + 1] {
                endOffset = nextFieldOffset
            } else if let metatype = resolveFieldMetatype(for: mangledTypeName, in: machO),
                      let typeLayout = try? StructMetadata.createInProcess(metatype).asMetadataWrapper().valueWitnessTable().typeLayout {
                endOffset = startOffset + Int(typeLayout.size)
            } else {
                endOffset = nil
            }
            configuration.fieldOffsetComment(startOffset: startOffset, endOffset: endOffset)

            if configuration.printExpandedFieldOffsets {
                expandedFieldOffsets(for: mangledTypeName, baseOffset: startOffset, baseIndentation: configuration.indentation, ancestors: [], in: machO)
            }
        }

        if configuration.printTypeLayout,
           let resolvedMetatype = resolveFieldMetatype(for: mangledTypeName, in: machO),
           let resolvedMetadata = try? StructMetadata.createInProcess(resolvedMetatype) {
            try? await resolvedMetadata.asMetadataWrapper().dumpTypeLayout(using: configuration)
        }
    }

    // MARK: - Enum cases

    @SemanticStringBuilder
    func enumCaseComments(
        forCaseAtIndex index: Int,
        mangledTypeName: MangledName,
        enumLayout: EnumLayoutCalculator.LayoutResult?
    ) async -> SemanticString {
        var isTypeLayoutPrinted = false

        if !mangledTypeName.isEmpty,
           configuration.printTypeLayout,
           let resolvedMetatype = resolveFieldMetatype(for: mangledTypeName, in: machO),
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
    func resolveFieldMetatype(for mangledTypeName: MangledName, in machOImage: MachOImage) -> Any.Type? {
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
    func expandedFieldOffsets(for mangledTypeName: MangledName, baseOffset: Int, baseIndentation: Int, ancestors: [Bool], in machO: MachOImage?) -> SemanticString {
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

    /// Upper bound on a variadic pack's element count when statically reading it
    /// from metadata. A well-formed pack is tiny; a larger value almost
    /// certainly means a misread word, so we bail to the unbound placeholder
    /// rather than drive an unbounded element loop.
    private var packElementCountLimit: Int { 256 }

    /// Depth-0 generic-argument layout facts for `parentMetadata`'s nominal
    /// type, sufficient to locate any key-argument slot in its inline
    /// generic-argument vector.
    ///
    /// Per the Swift ABI (`swift/include/swift/ABI/GenericContext.h`) and the
    /// runtime reader `SubstGenericParametersFromMetadata::getMetadata`, the
    /// vector is `[<numShapeClasses pack-length words>][<one word per
    /// hasKeyArgument parameter, in declaration order — metadata pointer,
    /// metadata-pack pointer, or value, all kinds interleaved>][<witness
    /// tables>]`. So a depth-0 parameter at `index` lives at
    /// `numShapeClasses + (count of hasKeyArgument parameters before index)`,
    /// regardless of kind; a `.typePack` parameter's pack-pointer slot and its
    /// length slot are named directly by its `GenericPackShapeDescriptor`.
    private struct TopLevelGenericLayout {
        let parameters: [GenericParamDescriptor]
        let keyArgumentFlags: [Bool]
        let numShapeClasses: Int
        /// Total size of the key-argument area (shape classes + per-parameter
        /// key arguments + witness tables), used as the slot bounds check.
        let totalKeyArguments: Int
        /// Metadata-kind pack-shape descriptors only (witness-table packs are
        /// excluded and, by ABI, ordered after metadata packs); the k-th entry
        /// describes the k-th `.typePack` key-argument parameter.
        let metadataPackShapeDescriptors: [GenericPackShapeDescriptor]
    }

    private func substitutedNestedTypeNode<ParentMetadata: ValueMetadataProtocol>(for mangledTypeName: MangledName, parentMetadata: ParentMetadata) -> Node? {
        guard let node = try? MetadataReader.demangleTypeUncached(for: mangledTypeName) else { return nil }
        guard let layout = topLevelGenericLayout(of: parentMetadata) else { return node }
        return substitutingGenericParameters(in: node, parentMetadata: parentMetadata, layout: layout)
    }

    private func staticallyBoundMetatype<ParentMetadata: ValueMetadataProtocol>(for mangledTypeName: MangledName, parentMetadata: ParentMetadata) -> Any.Type? {
        guard let node = try? MetadataReader.demangleTypeUncached(for: mangledTypeName) else { return nil }
        let typeNode = innerTypeNode(of: node)
        guard typeNode.kind == .dependentGenericParamType,
              let (depthValue, indexValue) = genericParameterDepthAndIndex(of: typeNode),
              depthValue == 0,
              let layout = topLevelGenericLayout(of: parentMetadata),
              indexValue < layout.parameters.count,
              // A bare field type that *is* a generic parameter can only be
              // recursed into when it resolves to a nominal type — i.e. a
              // `.type` parameter. `.value` / `.typePack` parameters have no
              // statically-walkable nested field layout (and their key-argument
              // slots are not metadata pointers), so they never recurse here.
              layout.parameters[indexValue].kind == .type,
              let flatIndex = depthZeroFlatIndex(forIndex: indexValue, keyArgumentFlags: layout.keyArgumentFlags)
        else { return nil }
        return boundGenericArgumentType(atSlot: layout.numShapeClasses + flatIndex, totalKeyArguments: layout.totalKeyArguments, of: parentMetadata)
    }

    /// Recursively substitutes every depth-0 generic-parameter reference in a
    /// nested field's demangled type node against `parentMetadata`'s specialized
    /// in-process generic arguments, so the rendered type name shows concrete
    /// arguments instead of unbound `A`/`B` placeholders. Each key-argument
    /// parameter kind reads the right slot of the metadata's inline
    /// generic-argument vector (see `TopLevelGenericLayout`):
    /// - `.type`     → resolve the metadata pointer to its mangled name and
    ///   splice in the demangled node (the original PAC-fault-avoiding path).
    /// - `.value`    → read the raw integer and splice in an `integer` /
    ///   `negativeInteger` literal (SE-0452, e.g. `InlineArray<3, UInt8>`).
    /// - `.typePack` → read the metadata pack and splice in a `pack` node of the
    ///   element type names (variadic generics).
    ///
    /// Any read failing its bounds / alignment / kind guards falls through to
    /// the unbound placeholder rather than risking a bad dereference.
    ///
    /// The replacement node takes the place of the matched bare
    /// `dependentGenericParamType`, whose enclosing `.type` wrapper is preserved
    /// by the recursion — so `.value` yields the canonical `type(integer)` shape
    /// and `.type` the canonical `type(<nominal>)`, exactly as the demangler
    /// would. The result is print-only (`nestedTypeName` →
    /// `printSemantic(using: .default)`); it is never remangled, so a bare
    /// `pack` child (printed as `Pack{…}`) needs no further wrapping.
    private func substitutingGenericParameters<ParentMetadata: ValueMetadataProtocol>(in node: Node, parentMetadata: ParentMetadata, layout: TopLevelGenericLayout) -> Node {
        if #available(macOS 11, iOS 14, tvOS 14, watchOS 7, *),
           node.kind == .dependentGenericParamType,
           let (depthValue, indexValue) = genericParameterDepthAndIndex(of: node),
           depthValue == 0,
           indexValue < layout.parameters.count,
           layout.parameters[indexValue].hasKeyArgument,
           let flatIndex = depthZeroFlatIndex(forIndex: indexValue, keyArgumentFlags: layout.keyArgumentFlags) {
            let slot = layout.numShapeClasses + flatIndex
            switch layout.parameters[indexValue].kind {
            case .type:
                if let argumentType = boundGenericArgumentType(atSlot: slot, totalKeyArguments: layout.totalKeyArguments, of: parentMetadata),
                   let argumentMangledString = _mangledTypeName(argumentType),
                   let argumentNode = try? demangleAsNode(argumentMangledString, isType: true) {
                    return innerTypeNode(of: argumentNode)
                }
            case .value:
                if let valueNode = substitutedValueNode(atSlot: slot, totalKeyArguments: layout.totalKeyArguments, of: parentMetadata) {
                    return valueNode
                }
            case .typePack:
                if let packNode = substitutedPackNode(forParameterAtIndex: indexValue, layout: layout, of: parentMetadata) {
                    return packNode
                }
            case .max:
                break
            }
        }
        let substitutedChildren = node.children.map {
            substitutingGenericParameters(in: $0, parentMetadata: parentMetadata, layout: layout)
        }
        return Node.create(kind: node.kind, contents: node.contents, children: Array(substitutedChildren))
    }

    /// Resolves a `.type` key-argument slot to its concrete `Any.Type`.
    private func boundGenericArgumentType<ParentMetadata: ValueMetadataProtocol>(atSlot slot: Int, totalKeyArguments: Int, of parentMetadata: ParentMetadata) -> Any.Type? {
        guard let word = genericArgumentWord(atSlot: slot, totalKeyArguments: totalKeyArguments, of: parentMetadata) else { return nil }
        // The slot must hold a pointer-aligned metadata pointer. Reject a null
        // or misaligned word defensively: a stray non-pointer value reaching
        // here would otherwise be bit-cast to a bogus `Any.Type` and trap the
        // runtime inside `_mangledTypeName`.
        guard word != 0,
              word % UInt(MemoryLayout<UnsafeRawPointer>.alignment) == 0,
              let argumentPointer = UnsafeRawPointer(bitPattern: word) else { return nil }
        return unsafeBitCast(argumentPointer, to: Any.Type.self)
    }

    /// Builds an `integer` / `negativeInteger` literal node for a `.value`
    /// (SE-0452) key-argument slot, which stores the raw `Int` value inline.
    private func substitutedValueNode<ParentMetadata: ValueMetadataProtocol>(atSlot slot: Int, totalKeyArguments: Int, of parentMetadata: ParentMetadata) -> Node? {
        guard let word = genericArgumentWord(atSlot: slot, totalKeyArguments: totalKeyArguments, of: parentMetadata) else { return nil }
        let value = Int(bitPattern: word)
        if value >= 0 {
            return Node.create(kind: .integer, contents: .index(UInt64(value)))
        } else {
            return Node.create(kind: .negativeInteger, contents: .index(UInt64(value.magnitude)))
        }
    }

    /// Builds a `pack` node of element type names for a `.typePack` key-argument
    /// slot, which stores a `MetadataPackPointer` (its low bit is the on-heap
    /// lifetime flag). The pack length lives in the leading shape-class slot
    /// named by the parameter's metadata pack-shape descriptor.
    private func substitutedPackNode<ParentMetadata: ValueMetadataProtocol>(forParameterAtIndex parameterIndex: Int, layout: TopLevelGenericLayout, of parentMetadata: ParentMetadata) -> Node? {
        guard #available(macOS 11, iOS 14, tvOS 14, watchOS 7, *) else { return nil }
        guard parameterIndex < layout.parameters.count else { return nil }
        // The k-th metadata pack-shape descriptor describes the k-th `.typePack`
        // key-argument parameter.
        var packOrdinal = 0
        for earlierIndex in 0..<parameterIndex {
            let earlierParameter = layout.parameters[earlierIndex]
            if earlierParameter.hasKeyArgument, earlierParameter.kind == .typePack {
                packOrdinal += 1
            }
        }
        guard packOrdinal < layout.metadataPackShapeDescriptors.count else { return nil }
        let packShapeDescriptor = layout.metadataPackShapeDescriptors[packOrdinal]
        let packSlot = Int(packShapeDescriptor.layout.index)
        let shapeClassSlot = Int(packShapeDescriptor.layout.shapeClass)

        // Pack length: stored in the leading shape-class slot.
        guard let countWord = genericArgumentWord(atSlot: shapeClassSlot, totalKeyArguments: layout.totalKeyArguments, of: parentMetadata) else { return nil }
        let elementCount = Int(bitPattern: countWord)
        guard elementCount >= 0, elementCount <= packElementCountLimit else { return nil }
        if elementCount == 0 { return Node.create(kind: .pack, children: []) }

        // Pack pointer: low bit is the on-heap lifetime flag — strip it.
        guard let packWord = genericArgumentWord(atSlot: packSlot, totalKeyArguments: layout.totalKeyArguments, of: parentMetadata) else { return nil }
        let elementsBitPattern = packWord & ~UInt(1)
        guard elementsBitPattern != 0,
              elementsBitPattern % UInt(MemoryLayout<UnsafeRawPointer>.alignment) == 0,
              let elementsBase = UnsafeRawPointer(bitPattern: elementsBitPattern) else { return nil }

        var elementNodes: [Node] = []
        for elementIndex in 0..<elementCount {
            let elementWord = elementsBase.load(fromByteOffset: elementIndex * MemoryLayout<UInt>.size, as: UInt.self)
            guard elementWord != 0,
                  elementWord % UInt(MemoryLayout<UnsafeRawPointer>.alignment) == 0,
                  let elementPointer = UnsafeRawPointer(bitPattern: elementWord) else { return nil }
            let elementType = unsafeBitCast(elementPointer, to: Any.Type.self)
            guard let elementMangledString = _mangledTypeName(elementType),
                  let elementNode = try? demangleAsNode(elementMangledString, isType: true) else { return nil }
            elementNodes.append(elementNode)
        }
        return Node.create(kind: .pack, children: elementNodes)
    }

    /// Reads the raw word at an absolute slot of `parentMetadata`'s inline
    /// generic-argument vector, bounds-checked against the key-argument area.
    private func genericArgumentWord<ParentMetadata: ValueMetadataProtocol>(atSlot slot: Int, totalKeyArguments: Int, of parentMetadata: ParentMetadata) -> UInt? {
        guard slot >= 0, slot < totalKeyArguments, let metadataPointer = try? parentMetadata.asPointer else { return nil }
        let genericArgumentsBase = metadataPointer.advanced(by: MemoryLayout<ParentMetadata.Layout>.size)
        return genericArgumentsBase.load(fromByteOffset: slot * MemoryLayout<UInt>.size, as: UInt.self)
    }

    private func topLevelGenericLayout<ParentMetadata: ValueMetadataProtocol>(of parentMetadata: ParentMetadata) -> TopLevelGenericLayout? {
        guard let descriptor = try? parentMetadata.descriptor(),
              let genericContext = try? descriptor.genericContext(),
              let topLevelParameters = genericContext.allParameters.first
        else { return nil }
        return TopLevelGenericLayout(
            parameters: topLevelParameters,
            keyArgumentFlags: topLevelParameters.map(\.hasKeyArgument),
            numShapeClasses: Int(genericContext.typePackHeader?.layout.numShapeClasses ?? 0),
            totalKeyArguments: Int(genericContext.header.numKeyArguments),
            metadataPackShapeDescriptors: genericContext.typePacks.filter { $0.kind == .metadata }
        )
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

    // MARK: - Enum layout (runtime)

    /// The enum's own value-witness type layout. Resolved with the `machO`
    /// context (matching the former `EnumDumper.typeLayout`): the enum metadata
    /// came from `…resolve(in: machO)`, so its value-witness table must be read
    /// back through the same reader — the no-argument `valueWitnessTable()`
    /// misinterprets that offset and segfaults. Used by single-payload layout.
    private var enumTypeLayout: TypeLayout? {
        try? metadata?.valueWitnessTable(in: machO).typeLayout
    }

    var enumLayout: EnumLayoutCalculator.LayoutResult? {
        get async {
            guard configuration.printEnumLayout,
                  let enumValue,
                  !enumValue.descriptor.isGeneric else { return nil }
            return try? await computeEnumLayout(enumValue, in: machO)
        }
    }

    private func computeEnumLayout(_ enumValue: Enum, in machOImage: MachOImage) async throws -> EnumLayoutCalculator.LayoutResult? {
        let payloadSize = try enumPayloadSize(enumValue.descriptor, in: machOImage)
        let numberOfPayloadCases = enumValue.numberOfPayloadCases
        let numberOfEmptyCases = enumValue.numberOfEmptyCases
        var layoutResult: EnumLayoutCalculator.LayoutResult
        if enumValue.isMultiPayload {
            let node = try MetadataReader.demangleContext(for: .type(.enum(enumValue.descriptor)), in: machOImage)
            if let multiPayloadEnumDescriptor = try multiPayloadEnumDescriptor(for: node, in: machOImage), multiPayloadEnumDescriptor.usesPayloadSpareBits {
                let spareBytes = try multiPayloadEnumDescriptor.payloadSpareBits(in: machOImage)
                let spareBytesOffset = try multiPayloadEnumDescriptor.payloadSpareBitMaskByteOffset(in: machOImage)
                layoutResult = EnumLayoutCalculator.calculateMultiPayload(payloadSize: payloadSize.cast(), spareBytes: spareBytes, spareBytesOffset: spareBytesOffset.cast(), numPayloadCases: numberOfPayloadCases.cast(), numEmptyCases: numberOfEmptyCases.cast())
            } else {
                layoutResult = EnumLayoutCalculator.calculateTaggedMultiPayload(payloadSize: payloadSize.cast(), numPayloadCases: numberOfPayloadCases.cast(), numEmptyCases: numberOfEmptyCases.cast())
            }
        } else if enumValue.isSinglePayload, let typeLayout = enumTypeLayout {
            let enumSize: Int = typeLayout.size.cast()
            let payloadXI = try enumPayloadExtraInhabitantCount(enumValue.descriptor, in: machOImage)
                ?? Self.inferredSinglePayloadExtraInhabitantCount(
                    enumSize: enumSize,
                    payloadSize: payloadSize.cast(),
                    emptyCaseCount: numberOfEmptyCases.cast(),
                    enumExtraInhabitantCount: typeLayout.extraInhabitantCount.cast()
                )
            // Without the payload's extra-inhabitant count the XI/overflow
            // split is unknowable and any layout we produced would be a guess
            // presented as fact — degrade to "no layout" instead.
            guard let payloadXI else { return nil }
            layoutResult = EnumLayoutCalculator.calculateSinglePayload(payloadSize: payloadSize.cast(), numEmptyCases: numberOfEmptyCases.cast(), numExtraInhabitants: payloadXI)
            // The formula knows only how many extra inhabitants the payload
            // has, not which bytes they occupy (that is a per-payload-type
            // detail: a class reference's low invalid addresses, `String`'s
            // reserved discriminator patterns, …). The metadata is live in
            // this process, so replace the unresolved patterns with the exact
            // bytes the enum's own value witnesses write.
            if let exactCasePatterns = projectedExactCasePatterns(
                numberOfPayloadCases: numberOfPayloadCases.cast(),
                totalCases: layoutResult.cases.count
            ) {
                layoutResult = layoutResult.applyingExactCasePatterns(exactCasePatterns)
            }
        } else {
            return nil
        }
        // Cross-check against the authoritative value-witness size: the
        // formulas run on *derived* inputs (payload size from resolving each
        // payload type, spare bytes from `__swift5_mpenum`), and a resolution
        // gap would otherwise surface as a confidently-wrong layout — tag
        // regions past the end of the value, cases described by a mechanism
        // the enum does not use. When the check cannot run (no metadata for a
        // multi-payload enum) the formula output stands on descriptor data
        // alone, which does not depend on per-payload resolution succeeding.
        if let typeLayout = enumTypeLayout {
            let impliedSize = layoutResult.impliedTotalSize(payloadAreaSize: payloadSize.cast())
            guard impliedSize == typeLayout.size.cast() else { return nil }
        }
        if let declaredCaseNames = declaredEnumCaseNames(of: enumValue.descriptor, in: machOImage) {
            layoutResult = layoutResult.attachingDeclaredCaseNames(declaredCaseNames)
        }
        return layoutResult
    }

    /// Recovers the payload's extra-inhabitant count from the enum's *own*
    /// value-witness layout when the payload type itself could not be resolved.
    /// When the enum is payload-sized (no extra tag bytes were appended) the
    /// runtime computed `enumXI = payloadXI - emptyCases`
    /// (`swift_initEnumMetadataSinglePayload`), so
    /// `payloadXI = enumXI + emptyCases` — exact, not a guess. In the overflow
    /// layout (`enumSize > payloadSize`) the enum's XI count is always zero
    /// and the payload's count cannot be recovered, so callers must degrade.
    static func inferredSinglePayloadExtraInhabitantCount(
        enumSize: Int,
        payloadSize: Int,
        emptyCaseCount: Int,
        enumExtraInhabitantCount: Int
    ) -> Int? {
        guard enumSize == payloadSize else { return nil }
        return min(enumExtraInhabitantCount + emptyCaseCount, EnumLayoutCalculator.maximumExtraInhabitantCount)
    }

    /// The enum metadata's absolute in-process address. A non-generic enum's
    /// metadata wrapper was resolved through `machO` (see `enumTypeLayout`),
    /// so its `offset` is relative to the image base; specialized generic
    /// metadata resolves through `InProcessContext`, where the offset already
    /// is the absolute address.
    private var inProcessEnumMetadataPointer: UnsafeRawPointer? {
        guard let enumMetadata = metadata?.enum ?? metadata?.optional else { return nil }
        if isGeneric {
            return UnsafeRawPointer(bitPattern: enumMetadata.offset)
        }
        return machO.ptr + enumMetadata.offset
    }

    /// Exact per-case fixed-byte patterns projected through the enum's own
    /// value witnesses (`RuntimeEnumCaseProjector`), keyed by tag-order case
    /// index. `nil` degrades the caller to the formula-derived patterns.
    private func projectedExactCasePatterns(numberOfPayloadCases: Int, totalCases: Int) -> [Int: [Int: UInt8]]? {
        guard let enumMetadataPointer = inProcessEnumMetadataPointer else { return nil }
        guard let casePatterns = RuntimeEnumCaseProjector.projectCasePatterns(
            enumMetadataPointer: enumMetadataPointer,
            payloadCaseCount: numberOfPayloadCases,
            caseCount: totalCases
        ) else { return nil }
        return Dictionary(uniqueKeysWithValues: casePatterns.map { ($0.caseIndex, $0.fixedBytes) })
    }

    /// The source-level case names in tag order (field records store payload
    /// cases first, then empty cases — the same order the layout's projections
    /// use).
    private func declaredEnumCaseNames(of descriptor: EnumDescriptor, in machOImage: MachOImage) -> [String]? {
        guard let records = try? descriptor.fieldDescriptor(in: machOImage).records(in: machOImage) else { return nil }
        return try? records.map { try $0.fieldName(in: machOImage) }
    }

    @SemanticStringBuilder
    func enumPrefixComments(enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString {
        if configuration.printEnumLayout, let enumLayout {
            BreakLine()
            configuration.enumLayoutComment(layoutResult: enumLayout)
        }

        if configuration.printSpareBitAnalysis,
           let enumValue, !enumValue.descriptor.isGeneric, enumValue.isMultiPayload,
           let analysis = spareBitAnalysis(for: enumValue, in: machO) {
            BreakLine()
            configuration.spareBitAnalysisComment(analysis: analysis)
        }
    }

    private func spareBitAnalysis(for enumValue: Enum, in machOImage: MachOImage) -> SpareBitAnalyzer.Analysis? {
        try? {
            let node = try MetadataReader.demangleContext(for: .type(.enum(enumValue.descriptor)), in: machOImage)
            guard let multiPayloadEnumDescriptor = try multiPayloadEnumDescriptor(for: node, in: machOImage),
                  multiPayloadEnumDescriptor.usesPayloadSpareBits else { return nil }
            let spareBytes = try multiPayloadEnumDescriptor.payloadSpareBits(in: machOImage)
            let spareBytesOffset = try multiPayloadEnumDescriptor.payloadSpareBitMaskByteOffset(in: machOImage)
            return SpareBitAnalyzer.analyze(bytes: spareBytes, startOffset: spareBytesOffset.cast())
        }()
    }

    /// Inline multi-payload-descriptor lookup: matches the target enum's
    /// demangled type node against the binary's `__swift5_mpenum` descriptors.
    /// Gated callers only invoke this when layout/spare-bit printing is on, so
    /// the linear scan is acceptable without the `SharedCache` used by the dump
    /// path.
    private func multiPayloadEnumDescriptor(for node: Node, in machOImage: MachOImage) throws -> MultiPayloadEnumDescriptor? {
        for multiPayloadEnumDescriptor in try machOImage.swift.multiPayloadEnumDescriptors {
            let mangledTypeName = try multiPayloadEnumDescriptor.mangledTypeName(in: machOImage)
            let descriptorNode = try MetadataReader.demangleType(for: mangledTypeName, in: machOImage)
            if descriptorNode == node {
                return multiPayloadEnumDescriptor
            }
        }
        return nil
    }

    private func enumPayloadSize(_ descriptor: EnumDescriptor, in machOImage: MachOImage) throws -> Int {
        guard descriptor.hasPayloadCases else { return .zero }
        let records = try descriptor.fieldDescriptor(in: machOImage).records(in: machOImage)
        guard !records.isEmpty else { return .zero }
        var payloadSize = 0
        let indirectPayloadSize = MemoryLayout<StoredPointer>.size
        for record in records {
            if record.flags.contains(.isIndirectCase) {
                payloadSize = max(payloadSize, indirectPayloadSize)
                continue
            }
            let mangledTypeName = try record.mangledTypeName(in: machOImage)
            guard !mangledTypeName.isEmpty else { continue }
            guard let metatype = try RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, genericContext: nil, genericArguments: nil, in: machOImage) else { continue }
            let typeLayout = try StructMetadata.createInProcess(metatype).asMetadataWrapper().valueWitnessTable().typeLayout
            payloadSize = max(payloadSize, typeLayout.size.cast())
        }
        return payloadSize
    }

    private func enumPayloadExtraInhabitantCount(_ descriptor: EnumDescriptor, in machOImage: MachOImage) throws -> Int? {
        guard descriptor.hasPayloadCases else { return nil }
        let records = try descriptor.fieldDescriptor(in: machOImage).records(in: machOImage)
        guard !records.isEmpty else { return nil }
        for record in records {
            if record.flags.contains(.isIndirectCase) {
                // An indirect case stores a `Builtin.NativeObject` box
                // reference regardless of its declared payload type, so the
                // payload's extra inhabitants are the heap-object ones (empty
                // cases ride the small invalid pointer values — the enum stays
                // payload-sized with no extra tag bytes).
                return EnumLayoutCalculator.heapObjectExtraInhabitantCount
            }
            let mangledTypeName = try record.mangledTypeName(in: machOImage)
            guard !mangledTypeName.isEmpty else { continue }
            guard let metatype = try RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, genericContext: nil, genericArguments: nil, in: machOImage) else { continue }
            let typeLayout = try StructMetadata.createInProcess(metatype).asMetadataWrapper().valueWitnessTable().typeLayout
            return typeLayout.extraInhabitantCount.cast()
        }
        return nil
    }
}
