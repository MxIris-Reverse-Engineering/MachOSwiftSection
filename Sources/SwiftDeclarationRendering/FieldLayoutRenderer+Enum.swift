import Foundation
import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import Utilities
@_spi(Internals) import SwiftInspection

/// Enum-layout machinery shared by `SwiftDump.EnumDumper` and
/// `SwiftPrinting.SwiftDeclarationPrinter`. Lifted out of `EnumDumper` so the
/// model-driven printer can emit the same `Enum Layout` strategy / per-case /
/// spare-bit comments. Behaviour-preserving; the only structural change is the
/// multi-payload descriptor lookup, which is done inline here (gated on
/// `printEnumLayout` / `printSpareBitAnalysis`) instead of through the
/// `SwiftDump`-local `SharedCache`, so `SwiftDeclarationRendering` needn't pull
/// in `MachOCaches`.
extension FieldLayoutRenderer {
    /// The dumped type as an `Enum`, or `nil` for struct/class.
    private var enumValue: Enum? {
        if case .enum(let enumType) = type { return enumType }
        return nil
    }

    /// The enum's own value-witness type layout. Resolved with the `machO`
    /// context (matching the former `EnumDumper.typeLayout`): the enum metadata
    /// came from `…resolve(in: machO)`, so its value-witness table must be read
    /// back through the same reader — the no-argument `valueWitnessTable()`
    /// misinterprets that offset and segfaults. Used by single-payload layout.
    private var enumTypeLayout: TypeLayout? {
        try? metadata?.valueWitnessTable(in: machO).typeLayout
    }

    /// Computes the enum's layout strategy projection. Returns `nil` when layout
    /// printing is disabled, the type is generic, or the enum is neither single-
    /// nor multi-payload (mirrors `EnumDumper.enumLayout`).
    package var enumLayout: EnumLayoutCalculator.LayoutResult? {
        get async {
            guard configuration.printEnumLayout,
                  let enumValue,
                  !enumValue.descriptor.isGeneric,
                  let machOImage = machO.asMachOImage else { return nil }
            return try? await computeEnumLayout(enumValue, in: machOImage)
        }
    }

    private func computeEnumLayout(_ enumValue: Enum, in machOImage: MachOImage) async throws -> EnumLayoutCalculator.LayoutResult? {
        let payloadSize = try enumPayloadSize(enumValue.descriptor, in: machOImage)
        let numberOfPayloadCases = enumValue.numberOfPayloadCases
        let numberOfEmptyCases = enumValue.numberOfEmptyCases
        if enumValue.isMultiPayload {
            let node = try MetadataReader.demangleContext(for: .type(.enum(enumValue.descriptor)), in: machOImage)
            if let multiPayloadEnumDescriptor = try multiPayloadEnumDescriptor(for: node, in: machOImage), multiPayloadEnumDescriptor.usesPayloadSpareBits {
                let spareBytes = try multiPayloadEnumDescriptor.payloadSpareBits(in: machOImage)
                let spareBytesOffset = try multiPayloadEnumDescriptor.payloadSpareBitMaskByteOffset(in: machOImage)
                return EnumLayoutCalculator.calculateMultiPayload(payloadSize: payloadSize.cast(), spareBytes: spareBytes, spareBytesOffset: spareBytesOffset.cast(), numPayloadCases: numberOfPayloadCases.cast(), numEmptyCases: numberOfEmptyCases.cast())
            } else {
                return EnumLayoutCalculator.calculateTaggedMultiPayload(payloadSize: payloadSize.cast(), numPayloadCases: numberOfPayloadCases.cast(), numEmptyCases: numberOfEmptyCases.cast())
            }
        } else if enumValue.isSinglePayload, let typeLayout = enumTypeLayout {
            let payloadXI = try enumPayloadExtraInhabitantCount(enumValue.descriptor, in: machOImage)
            return EnumLayoutCalculator.calculateSinglePayload(size: typeLayout.size.cast(), payloadSize: payloadSize.cast(), numEmptyCases: numberOfEmptyCases.cast(), numExtraInhabitants: payloadXI)
        } else {
            return nil
        }
    }

    /// Type-level enum comments emitted once before the case list: the
    /// `Enum Layout` strategy line and the spare-bit summary. Mirrors the
    /// prologue of `EnumDumper.fields`.
    @SemanticStringBuilder
    package func enumPrefixComments(enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString {
        if configuration.printEnumLayout, let enumLayout {
            BreakLine()
            configuration.enumLayoutComment(layoutResult: enumLayout)
        }

        if configuration.printSpareBitAnalysis,
           let enumValue, !enumValue.descriptor.isGeneric, enumValue.isMultiPayload,
           let machOImage = machO.asMachOImage,
           let analysis = spareBitAnalysis(for: enumValue, in: machOImage) {
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
                return nil
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
