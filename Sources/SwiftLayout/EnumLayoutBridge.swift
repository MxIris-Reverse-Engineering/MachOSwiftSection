import MachOSwiftSection
import Demangling

/// Enum layout for the resolver: no-payload (tag-only) and single-payload
/// (including `Optional`) enums, with the size/extra-inhabitant formulas ported
/// from the Swift runtime's `EnumImpl`. Multi-payload enums are deferred and
/// surface as `unknown` for now.
extension StaticTypeLayoutResolver {
    func enumLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> TypeLayoutInfo {
        guard let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node) else {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }
        // `Optional<T>` is a single-payload enum whose descriptor lives in the
        // standard library (not this image); compute it directly from the
        // payload type rather than resolving a descriptor.
        if qualifiedTypeName == "Swift.Optional" {
            return try optionalLayout(forNode: node, in: originImage)
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
        return try memoizedNominalLayout(forQualifiedTypeName: qualifiedTypeName) {
            guard let resolved = imageUniverse.resolveType(byQualifiedTypeName: qualifiedTypeName) else {
                throw LayoutResolutionError.unknown(.typeDescriptorNotFound(qualifiedTypeName: qualifiedTypeName))
            }
            guard let enumDescriptor = resolved.descriptor.enum else {
                throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "non-enum:\(qualifiedTypeName)"))
            }
            return try computeEnumLayout(enumDescriptor, node: node, in: resolved.image)
        }
    }

    private func computeEnumLayout(
        _ descriptor: EnumDescriptor,
        node: Node,
        in image: ImageReference<MachO>
    ) throws -> TypeLayoutInfo {
        let payloadCaseCount = descriptor.numberOfPayloadCases
        let emptyCaseCount = descriptor.numberOfEmptyCases
        if payloadCaseCount == 0 {
            return Self.noPayloadEnumLayout(emptyCaseCount: emptyCaseCount)
        }
        if payloadCaseCount == 1 {
            let payload = try singlePayloadType(descriptor: descriptor, node: node, in: image)
            return Self.singlePayloadEnumLayout(payload: payload, emptyCaseCount: emptyCaseCount)
        }
        throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "multiPayloadEnum:\(payloadCaseCount)"))
    }

    /// `Optional<T>`: a single-payload enum with exactly one empty case
    /// (`.none`), its payload being the bound generic argument.
    private func optionalLayout(forNode node: Node, in image: ImageReference<MachO>) throws -> TypeLayoutInfo {
        guard
            let typeList = node.first(of: .typeList),
            let payloadType = typeList.first(of: .type)
        else {
            throw LayoutResolutionError.unknown(.genericParameterUnsubstituted)
        }
        let payload = try layout(forTypeNode: payloadType, in: image)
        return Self.singlePayloadEnumLayout(payload: payload, emptyCaseCount: 1)
    }

    /// Resolves the payload type of a single-payload enum. For a generic enum
    /// such as `Optional<T>` the payload is the bound generic argument (the
    /// field record only carries the dependent parameter); for a non-generic
    /// enum it is the single payload case's field-record type.
    private func singlePayloadType(
        descriptor: EnumDescriptor,
        node: Node,
        in image: ImageReference<MachO>
    ) throws -> TypeLayoutInfo {
        if node.kind == .boundGenericEnum,
           let typeList = node.first(of: .typeList),
           let firstArgument = typeList.first(of: .type) {
            return try layout(forTypeNode: firstArgument, in: image)
        }
        let fieldDescriptor = try descriptor.fieldDescriptor(in: image.machO)
        let records = try fieldDescriptor.records(in: image.machO)
        for record in records {
            if record.layout.flags.contains(.isIndirectCase) {
                return .pointerSized
            }
            let mangledTypeName = try record.mangledTypeName(in: image.machO)
            if !mangledTypeName.isEmpty {
                return try layout(forMangledTypeName: mangledTypeName, in: image)
            }
        }
        throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "singlePayloadNoType"))
    }

    // MARK: - Layout formulas (ported from the Swift runtime EnumImpl)

    /// A single-payload enum reuses the payload's extra inhabitants to encode
    /// empty cases; only the overflow needs extra tag bytes appended after the
    /// payload.
    static func singlePayloadEnumLayout(payload: TypeLayoutInfo, emptyCaseCount: Int) -> TypeLayoutInfo {
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
        return TypeLayoutInfo(
            size: size,
            stride: stride,
            alignmentMask: alignmentMask,
            extraInhabitantCount: remainingExtraInhabitants,
            isBitwiseTakable: payload.isBitwiseTakable
        )
    }

    /// A no-payload enum is a plain tag occupying the fewest bytes that can
    /// represent every case.
    static func noPayloadEnumLayout(emptyCaseCount: Int) -> TypeLayoutInfo {
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
        } else if size >= 4 {
            totalRepresentableValues = Int(UInt32.max)
        } else {
            totalRepresentableValues = 1 << (size * 8)
        }
        let extraInhabitantCount = max(0, totalRepresentableValues - emptyCaseCount)
        return TypeLayoutInfo(
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
