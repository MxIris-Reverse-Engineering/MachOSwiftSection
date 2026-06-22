import MachOSwiftSection
@_spi(Internals) import SwiftInspection

/// The public entry point: computes Swift struct/class stored-property field
/// offsets statically from a Mach-O file, without loading the process or
/// calling the runtime.
///
/// Resolution degrades per field: a field whose type cannot be resolved (a
/// cross-module resilient type, an unsupported kind, an unsubstituted generic
/// parameter) is reported as `unknown` rather than failing the whole type, so
/// callers (e.g. ABI diffing) can still consume the offsets that *are* known.
public struct StaticLayoutCalculator<MachO: MachOSwiftSectionRepresentableWithCache> {
    let imageUniverse: ImageUniverse<MachO>
    let resolver: StaticTypeLayoutResolver<MachO>

    /// Builds a single-image calculator over `machO`.
    public init(machO: MachO) throws {
        let universe = try ImageUniverse.singleImage(machO)
        self.imageUniverse = universe
        self.resolver = StaticTypeLayoutResolver(imageUniverse: universe)
    }

    /// Builds a calculator over an existing image universe (used by later
    /// dependency-closure phases).
    public init(imageUniverse: ImageUniverse<MachO>) {
        self.imageUniverse = imageUniverse
        self.resolver = StaticTypeLayoutResolver(imageUniverse: imageUniverse)
    }

    /// Computes the per-field layout of a struct or class type. Enums (which
    /// have no stored-property field-offset vector) return an empty field list.
    public func fieldLayout(of typeDescriptor: TypeContextDescriptorWrapper) throws -> AggregateFieldLayout {
        if let structDescriptor = typeDescriptor.struct {
            return try fieldLayout(ofStruct: structDescriptor, in: imageUniverse.rootImage)
        }
        if let classDescriptor = typeDescriptor.class {
            return try fieldLayout(ofClass: classDescriptor, in: imageUniverse.rootImage)
        }
        // Enums carry no field-offset vector; report no fields.
        return AggregateFieldLayout(fields: [], size: 0, stride: 1, alignment: 1, extraInhabitantCount: 0)
    }

    /// The resolved whole-type layout of a struct field type. Convenience for
    /// callers that want size/stride rather than per-field offsets.
    public func typeLayout(ofStruct structDescriptor: StructDescriptor) throws -> TypeLayoutInfo {
        try resolver.computeStructLayout(structDescriptor, in: imageUniverse.rootImage).typeLayoutInfo()
    }

    /// The resolved whole-type layout of any field type given by its mangled
    /// name (struct/class/enum/tuple/…), as the resolver would lay it out when
    /// reached as a stored field. Used by renderers that need a field type's
    /// size/extra-inhabitants (e.g. enum payload sizing) without a descriptor in
    /// hand.
    public func typeLayout(forMangledTypeName mangledTypeName: MangledName) throws -> TypeLayoutInfo {
        try resolver.layout(forMangledTypeName: mangledTypeName, in: imageUniverse.rootImage)
    }

    /// The resolved whole-type layout of any struct/class/enum descriptor, as the
    /// resolver would lay it out. Demangles the descriptor's context to a node and
    /// resolves it (a class yields a single pointer). Used for enum whole-type
    /// sizing in renderers that hold a descriptor rather than a mangled name.
    public func typeLayout(forDescriptor typeDescriptor: TypeContextDescriptorWrapper) throws -> TypeLayoutInfo {
        let node = try MetadataReader.demangleContext(for: typeDescriptor.asContextDescriptorWrapper, in: imageUniverse.rootImage.machO)
        return try resolver.layout(forTypeNode: node, in: imageUniverse.rootImage)
    }

    // MARK: - Struct

    private func fieldLayout(ofStruct descriptor: StructDescriptor, in image: ImageReference<MachO>) throws -> AggregateFieldLayout {
        let records = try descriptor.fieldDescriptor(in: image.machO).records(in: image.machO)
        return try accumulateFieldLayout(
            records: records,
            startOffset: 0,
            startAlignmentMask: 0,
            in: image
        )
    }

    // MARK: - Class

    private func fieldLayout(ofClass descriptor: ClassDescriptor, in image: ImageReference<MachO>) throws -> AggregateFieldLayout {
        let records = try descriptor.fieldDescriptor(in: image.machO).records(in: image.machO)
        do {
            let start = try resolver.superclassStartLayout(of: descriptor, in: image)
            return try accumulateFieldLayout(
                records: records,
                startOffset: start.instanceSize,
                startAlignmentMask: start.alignmentMask,
                in: image
            )
        } catch let LayoutResolutionError.unknown(reason) {
            // The superclass instance size is unknown, so no field offset in
            // this class is trustworthy: mark them all unknown.
            let unresolvedFields = try records.map { record in
                FieldLayoutEntry(
                    fieldName: (try? record.fieldName(in: image.machO)) ?? "",
                    offset: 0,
                    typeMangledName: (try record.mangledTypeName(in: image.machO)).typeString,
                    layout: nil,
                    resolution: .unknown(reason: reason)
                )
            }
            return AggregateFieldLayout(fields: unresolvedFields, size: 0, stride: 1, alignment: 1, extraInhabitantCount: 0)
        }
    }

    // MARK: - Shared accumulation with per-field degradation

    private func accumulateFieldLayout(
        records: [FieldRecord],
        startOffset: Int,
        startAlignmentMask: Int,
        in image: ImageReference<MachO>
    ) throws -> AggregateFieldLayout {
        var offsetAccumulator = startOffset
        var alignmentMask = startAlignmentMask
        var isBitwiseTakable = true
        var entries: [FieldLayoutEntry] = []
        entries.reserveCapacity(records.count)
        var accumulatorIsTrustworthy = true

        for record in records {
            let fieldName = (try? record.fieldName(in: image.machO)) ?? ""
            let mangledTypeName = try record.mangledTypeName(in: image.machO)
            let typeNameString = mangledTypeName.typeString

            guard accumulatorIsTrustworthy else {
                entries.append(FieldLayoutEntry(
                    fieldName: fieldName,
                    offset: offsetAccumulator,
                    typeMangledName: typeNameString,
                    layout: nil,
                    resolution: .unknown(reason: .precedingFieldUnresolved)
                ))
                continue
            }

            do {
                let fieldLayout = try resolver.layout(forMangledTypeName: mangledTypeName, in: image)
                let fieldAlignmentMask = fieldLayout.alignmentMask
                let alignedOffset = (offsetAccumulator + fieldAlignmentMask) & ~fieldAlignmentMask
                entries.append(FieldLayoutEntry(
                    fieldName: fieldName,
                    offset: alignedOffset,
                    typeMangledName: typeNameString,
                    layout: fieldLayout,
                    resolution: .computed
                ))
                offsetAccumulator = alignedOffset + fieldLayout.size
                alignmentMask = max(alignmentMask, fieldAlignmentMask)
                isBitwiseTakable = isBitwiseTakable && fieldLayout.isBitwiseTakable
            } catch let LayoutResolutionError.unknown(reason) {
                accumulatorIsTrustworthy = false
                entries.append(FieldLayoutEntry(
                    fieldName: fieldName,
                    offset: offsetAccumulator,
                    typeMangledName: typeNameString,
                    layout: nil,
                    resolution: .unknown(reason: reason)
                ))
            }
        }

        let size = offsetAccumulator
        let stride = max(1, (size + alignmentMask) & ~alignmentMask)
        return AggregateFieldLayout(
            fields: entries,
            size: size,
            stride: stride,
            alignment: alignmentMask + 1,
            extraInhabitantCount: 0
        )
    }
}
