import Foundation
import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import SwiftLayout
import Utilities
@_spi(Internals) import SwiftInspection

/// The **static** (offline) `FieldLayoutRenderer` implementation, used when the
/// Mach-O reader is a `MachOFile`. It computes field offsets / type layouts / the
/// expanded nested tree / enum layouts from the binary via the `SwiftLayout`
/// engine — never loading the process or calling a metadata accessor — through an
/// injected `StaticFieldLayoutProvider`.
///
/// With no provider injected (or when SwiftLayout cannot resolve a type), each
/// entry point yields nothing, which is exactly how the renderer behaved for a
/// `MachOFile` before SwiftLayout was wired in (offline metadata is unavailable,
/// so the runtime path produced no offsets either). The runtime counterpart
/// lives in `FieldLayoutRenderer+MachOImage.swift`.
extension FieldLayoutRenderer where MachO == MachOFile {
    // MARK: - Field offsets (struct / class)

    /// The statically-computed field-offset vector, truncated at the first field
    /// SwiftLayout could not resolve (so a degraded field and everything after it
    /// emit no offset comment rather than a wrong one).
    var staticFieldOffsets: [Int]? {
        guard configuration.printFieldOffset else { return nil }
        return staticAggregateFieldLayout?.computedFieldOffsets
    }

    @SemanticStringBuilder
    func fileStoredFieldComments(
        forFieldAtIndex index: Int,
        mangledTypeName: MangledName,
        fieldOffsets: [Int]?
    ) -> SemanticString {
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
                fileExpandedFieldOffsets(for: mangledTypeName, baseOffset: startOffset)
            }
        }

        if configuration.printTypeLayout, let fieldLayout = staticAggregateFieldLayout?.fields[safe: index]?.layout {
            configuration.staticTypeLayoutComment(fieldLayout)
        }
    }

    // MARK: - Expanded nested field offsets

    @SemanticStringBuilder
    private func fileExpandedFieldOffsets(for mangledTypeName: MangledName, baseOffset: Int) -> SemanticString {
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
    func fileEnumCaseComments(
        forCaseAtIndex index: Int,
        mangledTypeName: MangledName,
        enumLayout: EnumLayoutCalculator.LayoutResult?
    ) -> SemanticString {
        var isTypeLayoutPrinted = false

        if !mangledTypeName.isEmpty,
           configuration.printTypeLayout,
           let provider = configuration.staticFieldLayoutProvider,
           let payloadTypeLayout = provider.typeLayout(forMangledTypeName: mangledTypeName) {
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

    var fileEnumLayout: EnumLayoutCalculator.LayoutResult? {
        guard configuration.printEnumLayout,
              let enumValue,
              !enumValue.descriptor.isGeneric,
              let provider = configuration.staticFieldLayoutProvider else { return nil }
        return try? computeStaticEnumLayout(enumValue, provider: provider)
    }

    private func computeStaticEnumLayout(_ enumValue: Enum, provider: any StaticFieldLayoutProvider) throws -> EnumLayoutCalculator.LayoutResult? {
        let payloadSize = try staticEnumPayloadSize(enumValue.descriptor, provider: provider)
        let numberOfPayloadCases = enumValue.numberOfPayloadCases
        let numberOfEmptyCases = enumValue.numberOfEmptyCases
        if enumValue.isMultiPayload {
            let node = try MetadataReader.demangleContext(for: .type(.enum(enumValue.descriptor)), in: machO)
            if let multiPayloadEnumDescriptor = try staticMultiPayloadEnumDescriptor(for: node), multiPayloadEnumDescriptor.usesPayloadSpareBits {
                let spareBytes = try multiPayloadEnumDescriptor.payloadSpareBits(in: machO)
                let spareBytesOffset = try multiPayloadEnumDescriptor.payloadSpareBitMaskByteOffset(in: machO)
                return EnumLayoutCalculator.calculateMultiPayload(payloadSize: payloadSize, spareBytes: spareBytes, spareBytesOffset: spareBytesOffset.cast(), numPayloadCases: numberOfPayloadCases, numEmptyCases: numberOfEmptyCases)
            } else {
                return EnumLayoutCalculator.calculateTaggedMultiPayload(payloadSize: payloadSize, numPayloadCases: numberOfPayloadCases, numEmptyCases: numberOfEmptyCases)
            }
        } else if enumValue.isSinglePayload {
            // The single-payload formula refines its result with the enum's own
            // total size; compute it statically (the enum bridge derives the same
            // size structurally).
            guard let enumTypeLayout = provider.typeLayout(forDescriptor: .enum(enumValue.descriptor)) else { return nil }
            let payloadExtraInhabitantCount = try staticEnumPayloadExtraInhabitantCount(enumValue.descriptor, provider: provider)
            return EnumLayoutCalculator.calculateSinglePayload(size: enumTypeLayout.size, payloadSize: payloadSize, numEmptyCases: numberOfEmptyCases, numExtraInhabitants: payloadExtraInhabitantCount)
        } else {
            return nil
        }
    }

    @SemanticStringBuilder
    func fileEnumPrefixComments(enumLayout: EnumLayoutCalculator.LayoutResult?) -> SemanticString {
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

    private func staticEnumPayloadSize(_ descriptor: EnumDescriptor, provider: any StaticFieldLayoutProvider) throws -> Int {
        guard descriptor.hasPayloadCases else { return .zero }
        let records = try descriptor.fieldDescriptor(in: machO).records(in: machO)
        guard !records.isEmpty else { return .zero }
        var payloadSize = 0
        let indirectPayloadSize = MemoryLayout<StoredPointer>.size
        for record in records {
            if record.flags.contains(.isIndirectCase) {
                payloadSize = max(payloadSize, indirectPayloadSize)
                continue
            }
            let mangledTypeName = try record.mangledTypeName(in: machO)
            guard !mangledTypeName.isEmpty else { continue }
            guard let typeLayout = provider.typeLayout(forMangledTypeName: mangledTypeName) else { continue }
            payloadSize = max(payloadSize, typeLayout.size)
        }
        return payloadSize
    }

    private func staticEnumPayloadExtraInhabitantCount(_ descriptor: EnumDescriptor, provider: any StaticFieldLayoutProvider) throws -> Int? {
        guard descriptor.hasPayloadCases else { return nil }
        let records = try descriptor.fieldDescriptor(in: machO).records(in: machO)
        guard !records.isEmpty else { return nil }
        for record in records {
            if record.flags.contains(.isIndirectCase) {
                return nil
            }
            let mangledTypeName = try record.mangledTypeName(in: machO)
            guard !mangledTypeName.isEmpty else { continue }
            guard let typeLayout = provider.typeLayout(forMangledTypeName: mangledTypeName) else { continue }
            return typeLayout.extraInhabitantCount
        }
        return nil
    }
}
