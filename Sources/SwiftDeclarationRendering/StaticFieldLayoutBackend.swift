import Foundation
import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import SwiftLayout
import Utilities
@_spi(Internals) import SwiftInspection

/// `MachOFile` renders field comments **statically** through the `SwiftLayout`
/// engine — no process, no metadata accessor.
extension MachOFile: FieldLayoutRenderable {
    public static func makeStaticFieldLayoutProvider(machO: MachOFile, resolution: StaticLayoutDependencyResolution) -> (any StaticFieldLayoutProvider)? {
        MachOFileStaticFieldLayoutProvider(machOFile: machO, resolution: resolution)
    }

    public static func precomputedStaticAggregateFieldLayout(for type: TypeContextWrapper, machO: MachOFile, configuration: DeclarationRenderConfiguration) -> AggregateFieldLayout? {
        // Only when a layout-bearing flag is on and a provider was injected;
        // enums (no field-offset vector) compute their layout lazily instead.
        guard configuration.printFieldOffset || configuration.printTypeLayout || configuration.printExpandedFieldOffsets,
              let provider = configuration.staticFieldLayoutProvider else {
            return nil
        }
        let descriptorWrapper: TypeContextDescriptorWrapper
        switch type {
        case .struct(let structType):
            descriptorWrapper = .struct(structType.descriptor)
        case .class(let classType):
            descriptorWrapper = .class(classType.descriptor)
        case .enum:
            return nil
        }
        return provider.aggregateFieldLayout(forDescriptor: descriptorWrapper)
    }

    public static func renderFieldOffsets(_ state: FieldLayoutRenderState, machO: MachOFile) -> [Int]? {
        StaticFieldLayoutBackend(state, machO: machO).fieldOffsets
    }

    public static func renderStoredFieldComments(_ state: FieldLayoutRenderState, machO: MachOFile, forFieldAtIndex index: Int, mangledTypeName: MangledName, fieldOffsets: [Int]?) async -> SemanticString {
        await StaticFieldLayoutBackend(state, machO: machO).storedFieldComments(forFieldAtIndex: index, mangledTypeName: mangledTypeName, fieldOffsets: fieldOffsets)
    }

    public static func renderEnumLayout(_ state: FieldLayoutRenderState, machO: MachOFile) async -> EnumLayoutCalculator.LayoutResult? {
        await StaticFieldLayoutBackend(state, machO: machO).enumLayout
    }

    public static func renderEnumPrefixComments(_ state: FieldLayoutRenderState, machO: MachOFile, enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString {
        await StaticFieldLayoutBackend(state, machO: machO).enumPrefixComments(enumLayout: enumLayout)
    }

    public static func renderEnumCaseComments(_ state: FieldLayoutRenderState, machO: MachOFile, forCaseAtIndex index: Int, mangledTypeName: MangledName, enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString {
        await StaticFieldLayoutBackend(state, machO: machO).enumCaseComments(forCaseAtIndex: index, mangledTypeName: mangledTypeName, enumLayout: enumLayout)
    }
}

/// The **static** (offline) backend, used when the Mach-O reader is a
/// `MachOFile`. It computes field offsets / type layouts / the expanded nested
/// tree / enum layouts from the binary via the `SwiftLayout` engine — never
/// loading the process — through an injected `StaticFieldLayoutProvider`.
///
/// With no provider injected (or when SwiftLayout cannot resolve a type), each
/// entry point yields nothing, which is how the renderer behaved for a
/// `MachOFile` before SwiftLayout was wired in (offline metadata is unavailable,
/// so the runtime path produced no comments either).
struct StaticFieldLayoutBackend {
    let state: FieldLayoutRenderState
    let machO: MachOFile

    init(_ state: FieldLayoutRenderState, machO: MachOFile) {
        self.state = state
        self.machO = machO
    }

    private var configuration: DeclarationRenderConfiguration { state.configuration }
    private var enumValue: Enum? { state.enumValue }
    private var staticAggregateFieldLayout: AggregateFieldLayout? { state.staticAggregateFieldLayout }

    // MARK: - Field offsets (struct / class)

    /// The statically-computed field-offset vector, truncated at the first field
    /// SwiftLayout could not resolve (so a degraded field and everything after it
    /// emit no offset comment rather than a wrong one).
    var fieldOffsets: [Int]? {
        guard configuration.printFieldOffset else { return nil }
        return staticAggregateFieldLayout?.computedFieldOffsets
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
            } else if let fieldLayout = staticAggregateFieldLayout?.fields[safe: index]?.layout {
                // The last field has no "next offset"; use its own type size as
                // the end. Available statically for every field via SwiftLayout.
                endOffset = startOffset + fieldLayout.size
            } else {
                endOffset = nil
            }
            configuration.fieldOffsetComment(startOffset: startOffset, endOffset: endOffset)

            if configuration.printExpandedFieldOffsets {
                expandedFieldOffsets(for: mangledTypeName, baseOffset: startOffset)
            }
        } else if
            configuration.printFieldOffset,
            case .unknown(let reason)? = staticAggregateFieldLayout?.fields[safe: index]?.resolution
        {
            // The offset could not be computed: say why, instead of silently
            // omitting the comment (an unresolved generic parameter reads very
            // differently from a disabled flag). The field's own type layout —
            // often still resolvable — renders below as usual.
            configuration.unknownFieldOffsetComment(reasonDescription: Self.shortDescription(of: reason))
        }

        if configuration.printTypeLayout, let fieldLayout = staticAggregateFieldLayout?.fields[safe: index]?.layout {
            configuration.staticTypeLayoutComment(fieldLayout)
        }
    }

    /// A one-line human-readable rendering of a layout degradation reason,
    /// used in the `Field offset: unknown (…)` comment.
    static func shortDescription(of reason: LayoutUnknownReason) -> String {
        switch reason {
        case .resilientFieldUnresolved:
            return "resilient field type unresolved"
        case .missingDependencyImage(let installName):
            return "missing dependency image \(installName)"
        case .objCAncestorUnresolved(let className):
            return "Objective-C ancestor \(className) unresolved"
        case .unsupportedTypeKind(let nodeKindName):
            return "unsupported type kind \(nodeKindName)"
        case .typeDescriptorNotFound(let qualifiedTypeName):
            return "type descriptor not found for \(qualifiedTypeName)"
        case .genericParameterUnsubstituted:
            return "generic parameter not substituted"
        case .cyclicLayout:
            return "cyclic layout"
        case .demangleFailure:
            return "mangled type name did not demangle"
        case .precedingFieldUnresolved:
            return "preceding field unresolved"
        }
    }

    // MARK: - Expanded nested field offsets

    @SemanticStringBuilder
    private func expandedFieldOffsets(for mangledTypeName: MangledName, baseOffset: Int) -> SemanticString {
        if let provider = configuration.staticFieldLayoutProvider {
            let tree = provider.nestedFieldOffsetTree(
                forMangledTypeName: mangledTypeName,
                baseOffset: baseOffset,
                depthLimit: nestedFieldOffsetExpansionDepthLimit
            )
            renderNestedFieldOffsetTree(tree, ancestors: [])
        }
    }

    @SemanticStringBuilder
    private func renderNestedFieldOffsetTree(_ nodes: [NestedFieldOffset], ancestors: [Bool]) -> SemanticString {
        for (index, node) in nodes.enumerated() {
            let isLast = index == nodes.count - 1
            configuration.expandedFieldOffsetComment(fieldName: node.fieldName, typeName: node.typeName, offset: node.offset, baseIndentation: configuration.indentation, ancestors: ancestors, isLast: isLast)
            renderNestedFieldOffsetTree(node.children, ancestors: ancestors + [isLast])
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
           let provider = configuration.staticFieldLayoutProvider,
           let payloadTypeLayout = payloadTypeLayout(for: mangledTypeName, provider: provider) {
            configuration.staticTypeLayoutComment(payloadTypeLayout)
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

    // MARK: - Enum layout (static)

    /// The enum's per-case projection layout, computed by the SwiftLayout
    /// engine from the descriptor. Generic enums are included: the engine
    /// resolves class-bound payload parameters without arguments and takes the
    /// tagged multi-payload strategy for every generic descriptor; an enum
    /// whose payload genuinely needs an argument yields `nil` (no comment) as
    /// before.
    var enumLayout: EnumLayoutCalculator.LayoutResult? {
        get async {
            guard configuration.printEnumLayout,
                  let enumValue,
                  let provider = configuration.staticFieldLayoutProvider else { return nil }
            return provider.enumCaseLayoutResult(forDescriptor: .enum(enumValue.descriptor))
        }
    }

    /// A payload case's own type layout, resolved in the enum descriptor's
    /// context so a generic enum's parameter-typed payloads (`Element` under a
    /// class-bound constraint) still resolve.
    private func payloadTypeLayout(for mangledTypeName: MangledName, provider: any StaticFieldLayoutProvider) -> StaticTypeLayout? {
        if let enumValue {
            return provider.typeLayout(forMangledTypeName: mangledTypeName, inContextOfDescriptor: .enum(enumValue.descriptor))
        }
        return provider.typeLayout(forMangledTypeName: mangledTypeName)
    }

    @SemanticStringBuilder
    func enumPrefixComments(enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString {
        if configuration.printEnumLayout, let enumLayout {
            BreakLine()
            configuration.enumLayoutComment(layoutResult: enumLayout)
        }

        if configuration.printSpareBitAnalysis,
           let enumValue, !enumValue.descriptor.isGeneric, enumValue.isMultiPayload,
           let analysis = staticSpareBitAnalysis(for: enumValue) {
            BreakLine()
            configuration.spareBitAnalysisComment(analysis: analysis)
        }
    }

    private func staticSpareBitAnalysis(for enumValue: Enum) -> SpareBitAnalyzer.Analysis? {
        try? {
            let node = try MetadataReader.demangleContext(for: .type(.enum(enumValue.descriptor)), in: machO)
            guard let multiPayloadEnumDescriptor = try staticMultiPayloadEnumDescriptor(for: node),
                  multiPayloadEnumDescriptor.usesPayloadSpareBits else { return nil }
            let spareBytes = try multiPayloadEnumDescriptor.payloadSpareBits(in: machO)
            let spareBytesOffset = try multiPayloadEnumDescriptor.payloadSpareBitMaskByteOffset(in: machO)
            return SpareBitAnalyzer.analyze(bytes: spareBytes, startOffset: spareBytesOffset.cast())
        }()
    }

    /// Matches the target enum's demangled type node against the binary's
    /// `__swift5_mpenum` descriptors — a section read that works directly on a
    /// `MachOFile` (no in-process realization needed).
    private func staticMultiPayloadEnumDescriptor(for node: Node) throws -> MultiPayloadEnumDescriptor? {
        for multiPayloadEnumDescriptor in try machO.swift.multiPayloadEnumDescriptors {
            let mangledTypeName = try multiPayloadEnumDescriptor.mangledTypeName(in: machO)
            let descriptorNode = try MetadataReader.demangleType(for: mangledTypeName, in: machO)
            if descriptorNode == node {
                return multiPayloadEnumDescriptor
            }
        }
        return nil
    }

}
