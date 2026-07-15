import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// Enum layout for the resolver: no-payload (tag-only), single-payload
/// (including `Optional`), and multi-payload enums, with the size formulas
/// ported from the Swift runtime's `EnumImpl`. Multi-payload enums are computed
/// structurally by reusing `SwiftInspection.EnumLayoutCalculator` (the
/// reference port of `GenEnum.cpp` / `TypeLowering.cpp`) — the fallback when no
/// `__swift5_builtin` whole-type descriptor is available.
extension StaticTypeLayoutResolver {
    func enumLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> StaticTypeLayout {
        guard let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node) else {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }
        // `Optional<T>` is a single-payload enum whose descriptor lives in the
        // standard library (not this image); compute it directly from the
        // payload type rather than resolving a descriptor.
        if qualifiedTypeName == "Swift.Optional" {
            return try optionalLayout(forNode: node, in: originImage)
        }
        // A frozen stdlib enum whose layout is argument-independent resolves by
        // its bare name through the frozen table — checked before the generic
        // instantiation cache key (below) can bypass it.
        if let known = KnownLayoutTable.layout(forFullyQualifiedTypeName: qualifiedTypeName) {
            return known
        }
        // An enum whose layout reflection cannot derive structurally —
        // multi-payload, indirect, `@objc` raw — carries its whole-type layout
        // in the using image's `__swift5_builtin` descriptor. Restricted to
        // non-generic enums (the builtin key is generic-argument-free, so a
        // generic node must not match it). Single-/no-payload enums the engine
        // computes itself emit no builtin descriptor and fall through below.
        if node.kind == .enum,
           let builtinLayout = originImage.builtinLayoutIndex.layout(forTypeName: qualifiedTypeName) {
            return builtinLayout
        }
        // For a concrete bound-generic instantiation (`MyEnum<Int>`) capture the
        // depth-0 arguments; payload field records reference these by
        // `dependentGenericParamType` and are substituted during payload reading.
        let environment = GenericArgumentEnvironment.make(forBoundGenericNode: node)
        let compute: () throws -> StaticTypeLayout = {
            guard let resolved = self.imageUniverse.resolveType(byQualifiedTypeName: qualifiedTypeName) else {
                throw LayoutResolutionError.unknown(.typeDescriptorNotFound(qualifiedTypeName: qualifiedTypeName))
            }
            guard let enumDescriptor = resolved.descriptor.enum else {
                throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "non-enum:\(qualifiedTypeName)"))
            }
            return try self.computeEnumLayout(enumDescriptor, node: node, in: resolved.image, environment: environment)
        }
        if environment.isEmpty {
            return try memoizedNominalLayout(forQualifiedTypeName: qualifiedTypeName, compute: compute)
        }
        return try memoizedInstantiationLayout(
            forInstantiationKey: Self.instantiationKey(of: node, qualifiedTypeName: qualifiedTypeName),
            compute: compute
        )
    }

    private func computeEnumLayout(
        _ descriptor: EnumDescriptor,
        node: Node,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment = .empty
    ) throws -> StaticTypeLayout {
        let payloadCaseCount = descriptor.numberOfPayloadCases
        let emptyCaseCount = descriptor.numberOfEmptyCases
        if payloadCaseCount == 0 {
            return Self.noPayloadEnumLayout(emptyCaseCount: emptyCaseCount)
        }
        if payloadCaseCount == 1 {
            let payload = try singlePayloadType(descriptor: descriptor, node: node, in: image, environment: environment)
            return Self.singlePayloadEnumLayout(payload: payload, emptyCaseCount: emptyCaseCount)
        }
        return try multiPayloadEnumLayout(descriptor, node: node, in: image, environment: environment)
    }

    /// Computes a multi-payload enum's whole-type layout structurally — the
    /// fallback reached when `enumLayout` found no `__swift5_builtin` whole-type
    /// descriptor (the primary, compiler-exact source). Reuses
    /// `EnumLayoutCalculator` (the `GenEnum.cpp` / `TypeLowering.cpp` port): the
    /// payload area is the largest payload case, tags are encoded in the common
    /// spare bits (from the enum's `MultiPayloadEnumDescriptor`) or, failing
    /// that, in appended extra tag bytes.
    ///
    /// Only whole-type `size`/`stride`/`alignment` are derived — all an
    /// aggregate needs to place the enum as a field. Extra inhabitants are
    /// reported as 0 (a conservative under-count; the builtin path supplies the
    /// exact value when present). A payload type that cannot be resolved (a
    /// generic parameter) propagates as `.unknown`, degrading the field.
    func multiPayloadEnumLayout(
        _ descriptor: EnumDescriptor,
        node: Node,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment = .empty
    ) throws -> StaticTypeLayout {
        let payloadCaseCount = descriptor.numberOfPayloadCases
        let emptyCaseCount = descriptor.numberOfEmptyCases

        // The payload area is the largest payload case; alignment and
        // bitwise-takability are the maxima/conjunction over all payload cases.
        var payloadSize = 0
        var payloadAlignmentMask = 0
        var isBitwiseTakable = true
        let records = try descriptor.fieldDescriptor(in: image.machO).records(in: image.machO)
        for record in records {
            let isIndirect = record.layout.flags.contains(.isIndirectCase)
            let mangledTypeName = try record.mangledTypeName(in: image.machO)
            guard isIndirect || !mangledTypeName.isEmpty else { continue } // empty case
            // An indirect case boxes its payload behind a single heap pointer.
            // The payload type is read through the generic environment so a
            // concrete `MyEnum<Int>` substitutes its payload parameters.
            let payloadLayout = isIndirect
                ? StaticTypeLayout.pointerSized
                : try layout(forMangledTypeName: mangledTypeName, in: image, environment: environment)
            payloadSize = max(payloadSize, payloadLayout.size)
            payloadAlignmentMask = max(payloadAlignmentMask, payloadLayout.alignmentMask)
            isBitwiseTakable = isBitwiseTakable && payloadLayout.isBitwiseTakable
        }

        let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node)
        let result: EnumLayoutCalculator.LayoutResult
        if
            let qualifiedTypeName,
            let multiPayloadDescriptor = multiPayloadEnumDescriptor(forQualifiedTypeName: qualifiedTypeName, in: image),
            multiPayloadDescriptor.usesPayloadSpareBits
        {
            // Spare-bits strategy: the descriptor carries the common spare-bit
            // mask the compiler computed across all payloads.
            let spareBytes = try multiPayloadDescriptor.payloadSpareBits(in: image.machO)
            let spareBytesOffset = Int(try multiPayloadDescriptor.payloadSpareBitMaskByteOffset(in: image.machO))
            result = EnumLayoutCalculator.calculateMultiPayload(
                payloadSize: payloadSize,
                spareBytes: spareBytes,
                spareBytesOffset: spareBytesOffset,
                numPayloadCases: payloadCaseCount,
                numEmptyCases: emptyCaseCount
            )
        } else {
            // No common spare bits (or no descriptor): tags occupy appended
            // extra tag bytes.
            result = EnumLayoutCalculator.calculateTaggedMultiPayload(
                payloadSize: payloadSize,
                numPayloadCases: payloadCaseCount,
                numEmptyCases: emptyCaseCount
            )
        }

        // `LayoutResult` exposes no size/stride: derive them. Extra tag bytes (if
        // any) are the tag region that begins at/after the payload area; tags
        // encoded purely in spare bits leave a region *within* the payload.
        var extraTagByteCount = 0
        if let tagRegion = result.tagRegion, tagRegion.range.lowerBound >= payloadSize {
            extraTagByteCount = tagRegion.range.upperBound - payloadSize
        }
        let size = payloadSize + extraTagByteCount
        let stride = max(1, (size + payloadAlignmentMask) & ~payloadAlignmentMask)
        return StaticTypeLayout(
            size: size,
            stride: stride,
            alignmentMask: payloadAlignmentMask,
            extraInhabitantCount: 0,
            isBitwiseTakable: isBitwiseTakable
        )
    }

    /// Finds the `MultiPayloadEnumDescriptor` (`__swift5_mpenum`) for an enum by
    /// matching its mangled type name to `qualifiedTypeName`. Scanned on demand
    /// because this is a rare fallback path; an absent section yields `nil`.
    private func multiPayloadEnumDescriptor(
        forQualifiedTypeName qualifiedTypeName: String,
        in image: ImageReference<MachO>
    ) -> MultiPayloadEnumDescriptor? {
        guard let descriptors = try? image.machO.swift.multiPayloadEnumDescriptors else { return nil }
        for descriptor in descriptors {
            guard
                let mangledTypeName = try? descriptor.mangledTypeName(in: image.machO),
                let node = try? MetadataReader.demangleType(for: mangledTypeName, in: image.machO),
                NodeTypeNaming.nominalQualifiedName(of: node) == qualifiedTypeName
            else { continue }
            return descriptor
        }
        return nil
    }

    /// `Optional<T>`: a single-payload enum with exactly one empty case
    /// (`.none`), its payload being the bound generic argument.
    private func optionalLayout(forNode node: Node, in image: ImageReference<MachO>) throws -> StaticTypeLayout {
        guard
            let typeList = node.first(of: .typeList),
            let payloadType = typeList.first(of: .type)
        else {
            throw LayoutResolutionError.unknown(.genericParameterUnsubstituted)
        }
        let payload = try layout(forTypeNode: payloadType, in: image)
        return Self.singlePayloadEnumLayout(payload: payload, emptyCaseCount: 1)
    }

    /// Resolves the payload type of a single-payload enum from its field
    /// record, substituting the enum's generic arguments via `environment`.
    /// So `enum Box<A> { case some(A) }` instantiated `Box<Int>` reads the
    /// record's `A` and substitutes `Int`; `enum E<First, Second> { case a(Second) }`
    /// correctly picks `Second` — unlike the previous shortcut, which blindly
    /// took the *first* bound-generic argument regardless of which parameter the
    /// payload used.
    private func singlePayloadType(
        descriptor: EnumDescriptor,
        node: Node,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment = .empty
    ) throws -> StaticTypeLayout {
        let fieldDescriptor = try descriptor.fieldDescriptor(in: image.machO)
        let records = try fieldDescriptor.records(in: image.machO)
        for record in records {
            if record.layout.flags.contains(.isIndirectCase) {
                return .pointerSized
            }
            let mangledTypeName = try record.mangledTypeName(in: image.machO)
            if !mangledTypeName.isEmpty {
                return try layout(forMangledTypeName: mangledTypeName, in: image, environment: environment)
            }
        }
        throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "singlePayloadNoType"))
    }

    // MARK: - Layout formulas (ported from the Swift runtime EnumImpl)

    /// A single-payload enum reuses the payload's extra inhabitants to encode
    /// empty cases; only the overflow needs extra tag bytes appended after the
    /// payload.
    static func singlePayloadEnumLayout(payload: StaticTypeLayout, emptyCaseCount: Int) -> StaticTypeLayout {
        let payloadExtraInhabitants = payload.extraInhabitantCount
        let size: Int
        let usedExtraInhabitants: Int
        if emptyCaseCount <= payloadExtraInhabitants {
            size = payload.size
            usedExtraInhabitants = emptyCaseCount
        } else {
            let spilledCaseCount = emptyCaseCount - payloadExtraInhabitants
            let tagCounts = enumTagCounts(payloadSize: payload.size, emptyCaseCount: spilledCaseCount, payloadCaseCount: 1)
            size = payload.size + tagCounts.numTagBytes
            usedExtraInhabitants = payloadExtraInhabitants
        }
        let alignmentMask = payload.alignmentMask
        let stride = max(1, (size + alignmentMask) & ~alignmentMask)
        let remainingExtraInhabitants = max(0, payloadExtraInhabitants - usedExtraInhabitants)
        return StaticTypeLayout(
            size: size,
            stride: stride,
            alignmentMask: alignmentMask,
            extraInhabitantCount: remainingExtraInhabitants,
            isBitwiseTakable: payload.isBitwiseTakable
        )
    }

    /// A no-payload enum is a plain tag occupying the fewest bytes that can
    /// represent every case.
    static func noPayloadEnumLayout(emptyCaseCount: Int) -> StaticTypeLayout {
        let size: Int
        if emptyCaseCount <= 1 {
            size = 0
        } else if emptyCaseCount <= 0x100 {
            size = 1
        } else if emptyCaseCount <= 0x1_0000 {
            size = 2
        } else {
            size = 4
        }
        let alignmentMask = max(0, size - 1)
        let stride = max(1, size)
        let totalRepresentableValues: Int
        if size == 0 {
            totalRepresentableValues = 1
        } else {
            totalRepresentableValues = 1 << (size * 8)
        }
        let extraInhabitantCount = max(0, totalRepresentableValues - emptyCaseCount)
        return StaticTypeLayout(
            size: size,
            stride: stride,
            alignmentMask: alignmentMask,
            extraInhabitantCount: extraInhabitantCount,
            isBitwiseTakable: true
        )
    }

    /// Ported from the runtime's `getEnumTagCounts`: how many tag bytes are
    /// needed to distinguish `payloadCaseCount + (spilled) empty cases` given a
    /// payload of `payloadSize` bytes.
    static func enumTagCounts(
        payloadSize: Int,
        emptyCaseCount: Int,
        payloadCaseCount: Int
    ) -> (numTagBytes: Int, numTags: Int) {
        var numTags = payloadCaseCount
        if emptyCaseCount > 0 {
            if payloadSize >= 4 {
                numTags += 1
            } else {
                let bitCount = payloadSize * 8
                let casesPerTagBitValue = 1 << bitCount
                numTags += (emptyCaseCount + (casesPerTagBitValue - 1)) >> bitCount
            }
        }
        let numTagBytes: Int
        if numTags <= 1 {
            numTagBytes = 0
        } else if numTags < 256 {
            numTagBytes = 1
        } else if numTags < 65536 {
            numTagBytes = 2
        } else {
            numTagBytes = 4
        }
        return (numTagBytes, numTags)
    }
}
