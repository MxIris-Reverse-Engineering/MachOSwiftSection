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
        // For a concrete generic instantiation (`MyEnum<Int>`, or a nested
        // `Parent<Int>.Inner` whose arguments ride the parent chain) capture
        // the per-level arguments; payload field records reference these by
        // `dependentGenericParamType` and are substituted during payload
        // reading. Built before the builtin check so an instantiated node
        // (whose layout is argument-dependent) can never match the
        // generic-argument-free builtin key.
        let environment = GenericArgumentEnvironment.make(forInstantiatedTypeNode: node)
        // An enum whose layout reflection cannot derive structurally —
        // multi-payload, indirect, `@objc` raw — carries its whole-type layout
        // in the using image's `__swift5_builtin` descriptor. Restricted to
        // non-instantiated enums (the builtin key is generic-argument-free).
        // Single-/no-payload enums the engine computes itself emit no builtin
        // descriptor and fall through below.
        if node.kind == .enum, environment.isEmpty,
           let builtinLayout = originImage.builtinLayoutIndex.layout(forTypeName: qualifiedTypeName) {
            return builtinLayout
        }
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
        // Class-bound parameters lay out as one object reference even without
        // a substitution.
        let environment = environment.augmented(
            withRequirementFacts: ClassBoundGenericParameterAnalysis.layoutFacts(of: descriptor, in: image, imageUniverse: imageUniverse)
        )
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
    /// Whole-type `size`/`stride`/`alignment` are derived here; the extra
    /// inhabitants come exact from `LayoutResult` (unused tag values, per
    /// strategy — see `LayoutResult.extraInhabitantCount`), so an
    /// `Optional<MPE>` wrapper spends an inhabitant instead of appending a tag
    /// byte even on this fallback path. Note the official offline
    /// implementation (RemoteInspection `TypeLowering.cpp`) never derives
    /// spare-bits XI structurally — without the builtin descriptor it falls
    /// back to the tagged formula outright. A payload type that cannot be
    /// resolved (a generic parameter) propagates as `.unknown`, degrading the
    /// field.
    func multiPayloadEnumLayout(
        _ descriptor: EnumDescriptor,
        node: Node,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment = .empty
    ) throws -> StaticTypeLayout {
        let payloadCaseCount = descriptor.numberOfPayloadCases
        let emptyCaseCount = descriptor.numberOfEmptyCases
        let payloadArea = try multiPayloadArea(of: descriptor, in: image, environment: environment)
        let payloadSize = payloadArea.size
        let payloadAlignmentMask = payloadArea.alignmentMask
        let isBitwiseTakable = payloadArea.isBitwiseTakable

        let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node)
        let result: EnumLayoutCalculator.LayoutResult
        if
            // A generic enum never uses the spare-bits strategy: the runtime's
            // `swift_initEnumMetadataMultiPayload` always appends tag bytes (a
            // spare-bit layout requires compile-time payload knowledge), so a
            // generic descriptor — instantiated or not — takes the tagged
            // branch even when a `__swift5_mpenum` descriptor is present.
            !descriptor.isGeneric,
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
            extraInhabitantCount: result.extraInhabitantCount,
            isBitwiseTakable: isBitwiseTakable
        )
    }

    /// The payload area of a multi-payload enum: the largest payload case's
    /// size; alignment and bitwise-takability are the maxima/conjunction over
    /// all payload cases. An indirect case boxes its payload behind a single
    /// heap pointer. Payload types are read through the generic environment so
    /// a concrete `MyEnum<Int>` substitutes its payload parameters.
    func multiPayloadArea(
        of descriptor: EnumDescriptor,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment
    ) throws -> (size: Int, alignmentMask: Int, isBitwiseTakable: Bool) {
        var payloadSize = 0
        var payloadAlignmentMask = 0
        var isBitwiseTakable = true
        let records = try descriptor.fieldDescriptor(in: image.machO).records(in: image.machO)
        for record in records {
            let isIndirect = record.layout.flags.contains(.isIndirectCase)
            let mangledTypeName = try record.mangledTypeName(in: image.machO)
            guard isIndirect || !mangledTypeName.isEmpty else { continue } // empty case
            let payloadLayout = isIndirect
                ? StaticTypeLayout.pointerSized
                : try layout(forMangledTypeName: mangledTypeName, in: image, environment: environment)
            payloadSize = max(payloadSize, payloadLayout.size)
            payloadAlignmentMask = max(payloadAlignmentMask, payloadLayout.alignmentMask)
            isBitwiseTakable = isBitwiseTakable && payloadLayout.isBitwiseTakable
        }
        return (payloadSize, payloadAlignmentMask, isBitwiseTakable)
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
    /// (`.none`), its payload being the bound generic argument. The payload's
    /// metatype-thinness is decided by its own syntactic instance kind (a
    /// concrete `Int.Type` payload is thin ⇒ `Optional<Int.Type>` is 1 byte; a
    /// `T.Type` payload is thick ⇒ 8 bytes), so no special context is needed
    /// here.
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

    // MARK: - Case-projection layout (for renderers)

    /// The per-case projection layout (`EnumLayoutCalculator.LayoutResult`:
    /// payload/tag regions and per-case tag values) of an enum descriptor,
    /// computed statically — the renderer-facing counterpart of the whole-type
    /// `computeEnumLayout`. Returns `nil` for a no-payload enum (nothing to
    /// project) and throws when a payload type cannot be resolved.
    ///
    /// Works for generic enums too: class-bound parameters resolve through the
    /// requirement-signature analysis, and any generic descriptor takes the
    /// tagged multi-payload strategy (a generic instantiation never uses spare
    /// bits), so an unspecialized `enum Content<Element: AnyObject>` projects
    /// exactly like every one of its instantiations.
    func enumCaseLayoutResult(
        of descriptor: EnumDescriptor,
        in image: ImageReference<MachO>
    ) throws -> EnumLayoutCalculator.LayoutResult? {
        let environment = GenericArgumentEnvironment.empty.augmented(
            withRequirementFacts: ClassBoundGenericParameterAnalysis.layoutFacts(of: descriptor, in: image, imageUniverse: imageUniverse)
        )
        let payloadCaseCount = descriptor.numberOfPayloadCases
        let emptyCaseCount = descriptor.numberOfEmptyCases
        guard payloadCaseCount > 0 else { return nil }

        let node = try MetadataReader.demangleContext(for: .type(.enum(descriptor)), in: image.machO)
        let layoutResult: EnumLayoutCalculator.LayoutResult
        if payloadCaseCount == 1 {
            let payload = try singlePayloadType(descriptor: descriptor, node: node, in: image, environment: environment)
            layoutResult = EnumLayoutCalculator.calculateSinglePayload(
                payloadSize: payload.size,
                numEmptyCases: emptyCaseCount,
                numExtraInhabitants: payload.extraInhabitantCount
            )
        } else {
            let payloadArea = try multiPayloadArea(of: descriptor, in: image, environment: environment)
            if
                !descriptor.isGeneric,
                let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node),
                let multiPayloadDescriptor = multiPayloadEnumDescriptor(forQualifiedTypeName: qualifiedTypeName, in: image),
                multiPayloadDescriptor.usesPayloadSpareBits
            {
                let spareBytes = try multiPayloadDescriptor.payloadSpareBits(in: image.machO)
                let spareBytesOffset = Int(try multiPayloadDescriptor.payloadSpareBitMaskByteOffset(in: image.machO))
                layoutResult = EnumLayoutCalculator.calculateMultiPayload(
                    payloadSize: payloadArea.size,
                    spareBytes: spareBytes,
                    spareBytesOffset: spareBytesOffset,
                    numPayloadCases: payloadCaseCount,
                    numEmptyCases: emptyCaseCount
                )
            } else {
                layoutResult = EnumLayoutCalculator.calculateTaggedMultiPayload(
                    payloadSize: payloadArea.size,
                    numPayloadCases: payloadCaseCount,
                    numEmptyCases: emptyCaseCount
                )
            }
        }
        // Attach the source-level case names (field records store payload
        // cases first, then empty cases — the projections' tag order).
        if let records = try? descriptor.fieldDescriptor(in: image.machO).records(in: image.machO),
           let declaredCaseNames = try? records.map({ try $0.fieldName(in: image.machO) }) {
            return layoutResult.attachingDeclaredCaseNames(declaredCaseNames)
        }
        return layoutResult
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
        let extraInhabitantCount: Int
        if emptyCaseCount == 0 {
            // An uninhabited enum (zero cases — `Never`, or a caseless
            // namespace enum) is a `SingletonEnumImplStrategy` with no
            // singleton: `getFixedExtraInhabitantCount` returns 0 (GenEnum.cpp;
            // the runtime value-witness table agrees), not the `2^0 − 0 = 1`
            // the tag formula below would produce.
            extraInhabitantCount = 0
        } else {
            let totalRepresentableValues: Int
            if size == 0 {
                totalRepresentableValues = 1
            } else {
                totalRepresentableValues = 1 << (size * 8)
            }
            // NoPayloadEnumImplStrategy::getFixedExtraInhabitantCount saturates
            // at ValueWitnessFlags::MaxNumExtraInhabitants — relevant for the
            // 4-byte tag (> 65536 cases), where the raw count exceeds the cap.
            extraInhabitantCount = min(
                max(0, totalRepresentableValues - emptyCaseCount),
                EnumLayoutCalculator.maximumExtraInhabitantCount
            )
        }
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
