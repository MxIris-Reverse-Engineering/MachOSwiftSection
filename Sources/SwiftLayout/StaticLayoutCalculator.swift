import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

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
        try fieldLayout(of: typeDescriptor, in: imageUniverse.rootImage, environment: .empty)
    }

    /// Computes the per-field layout of a *concrete generic instantiation* of
    /// `typeDescriptor` (e.g. `Foo<Int>`), substituting the type's depth-0
    /// generic parameters with `genericArguments`.
    ///
    /// `genericArguments` are the concrete type arguments as demangled,
    /// `.type`-wrapped `Node`s, in declaration order. Arguments that cannot be
    /// modelled statically (value / pack arguments, or a count that does not
    /// cover a referenced parameter) degrade the dependent fields to `.unknown`
    /// rather than yield a wrong offset — matching the engine's per-field
    /// degradation. An enum descriptor reports no fields (enums carry no
    /// field-offset vector); use `typeLayout(...)` for an enum's whole-type
    /// size.
    public func fieldLayout(
        of typeDescriptor: TypeContextDescriptorWrapper,
        genericArguments: [Node]
    ) throws -> AggregateFieldLayout {
        let environment = GenericArgumentEnvironment.make(forDepthZeroTypeArguments: genericArguments)
        return try fieldLayout(of: typeDescriptor, in: imageUniverse.rootImage, environment: environment)
    }

    /// Computes the per-field layout of a concrete generic instantiation given
    /// its bound-generic mangled name (e.g. a `Foo<Int>` type reference read
    /// from a binary). The instantiation's type descriptor is resolved by
    /// qualified name within the image universe — so a cross-module
    /// instantiation lays out against its defining image — and its depth-0
    /// arguments are captured from the bound-generic node. Throws `unknown` for
    /// a name that does not demangle, is not a bound-generic nominal type, or
    /// whose descriptor cannot be found.
    public func fieldLayout(forInstantiationMangledName mangledTypeName: MangledName) throws -> AggregateFieldLayout {
        let typeNode: Node
        do {
            typeNode = try MetadataReader.demangleType(for: mangledTypeName, in: imageUniverse.rootImage.machO)
        } catch {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }
        let node = typeNode.kind == .type ? (typeNode.firstChild ?? typeNode) : typeNode
        guard let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node) else {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }
        guard let resolved = imageUniverse.resolveType(byQualifiedTypeName: qualifiedTypeName) else {
            throw LayoutResolutionError.unknown(.typeDescriptorNotFound(qualifiedTypeName: qualifiedTypeName))
        }
        let environment = GenericArgumentEnvironment.make(forInstantiatedTypeNode: node)
        return try fieldLayout(of: resolved.descriptor, in: resolved.image, environment: environment)
    }

    /// The resolved whole-type layout of a struct field type. Convenience for
    /// callers that want size/stride rather than per-field offsets.
    public func typeLayout(ofStruct structDescriptor: StructDescriptor) throws -> StaticTypeLayout {
        // Foreign (C-imported) structs: the builtin whole-type record is
        // authoritative; the structural path cannot see C bitfields/padding.
        if structDescriptor.hasForeignMetadataInitialization,
           let builtinLayout = foreignBuiltinLayout(of: structDescriptor, in: imageUniverse.rootImage) {
            return builtinLayout
        }
        return try resolver.computeStructLayout(structDescriptor, in: imageUniverse.rootImage).asStaticTypeLayout()
    }

    /// The resolved whole-type layout of any field type given by its mangled
    /// name (struct/class/enum/tuple/…), as the resolver would lay it out when
    /// reached as a stored field. Used by renderers that need a field type's
    /// size/extra-inhabitants (e.g. enum payload sizing) without a descriptor in
    /// hand.
    public func typeLayout(forMangledTypeName mangledTypeName: MangledName) throws -> StaticTypeLayout {
        try resolver.layout(forMangledTypeName: mangledTypeName, in: imageUniverse.rootImage)
    }

    /// The resolved whole-type layout of any struct/class/enum descriptor, as the
    /// resolver would lay it out. Demangles the descriptor's context to a node and
    /// resolves it (a class yields a single pointer). Used for enum whole-type
    /// sizing in renderers that hold a descriptor rather than a mangled name.
    public func typeLayout(forDescriptor typeDescriptor: TypeContextDescriptorWrapper) throws -> StaticTypeLayout {
        let node = try MetadataReader.demangleContext(for: typeDescriptor.asContextDescriptorWrapper, in: imageUniverse.rootImage.machO)
        return try resolver.layout(forTypeNode: node, in: imageUniverse.rootImage)
    }

    /// The resolved whole-type layout of a field type given by its mangled
    /// name, lowered **in the context of** `contextDescriptor` — the descriptor
    /// whose field/payload record carries that mangled name. The context
    /// supplies what the bare mangled name alone cannot: the requirement
    /// signature's class-bound parameters (an unsubstituted `Element` payload of
    /// `enum Content<Element: AnyObject>` resolves as one object reference) and
    /// concrete same-type pins (`Value == Date`). For a non-generic descriptor
    /// this is exactly `typeLayout(forMangledTypeName:)`.
    public func typeLayout(
        forMangledTypeName mangledTypeName: MangledName,
        inContextOfDescriptor contextDescriptor: TypeContextDescriptorWrapper
    ) throws -> StaticTypeLayout {
        let image = imageUniverse.rootImage
        let environment = GenericArgumentEnvironment.empty.augmented(
            withRequirementFacts: ClassBoundGenericParameterAnalysis.layoutFacts(
                of: contextDescriptor.typeContextDescriptor,
                in: image,
                imageUniverse: imageUniverse
            )
        )
        return try resolver.layout(forMangledTypeName: mangledTypeName, in: image, environment: environment)
    }

    /// The per-case projection layout of an enum descriptor (payload/tag
    /// regions and per-case tag values), computed statically — including for
    /// generic enums whose layout is determined without arguments (class-bound
    /// payload parameters, or payloads not using any parameter). Returns `nil`
    /// for a non-enum descriptor, a no-payload enum, or an enum whose payload
    /// types cannot be resolved.
    public func enumCaseLayoutResult(forDescriptor typeDescriptor: TypeContextDescriptorWrapper) -> EnumLayoutCalculator.LayoutResult? {
        guard let enumDescriptor = typeDescriptor.enum else { return nil }
        return try? resolver.enumCaseLayoutResult(of: enumDescriptor, in: imageUniverse.rootImage)
    }

    // MARK: - Descriptor dispatch

    private func fieldLayout(
        of typeDescriptor: TypeContextDescriptorWrapper,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment
    ) throws -> AggregateFieldLayout {
        if let structDescriptor = typeDescriptor.struct {
            return try fieldLayout(ofStruct: structDescriptor, in: image, environment: environment)
        }
        if let classDescriptor = typeDescriptor.class {
            return try fieldLayout(ofClass: classDescriptor, in: image, environment: environment)
        }
        // Enums carry no field-offset vector; report no fields.
        return AggregateFieldLayout(fields: [], size: 0, stride: 1, alignment: 1, extraInhabitantCount: 0)
    }

    // MARK: - Struct

    private func fieldLayout(
        ofStruct descriptor: StructDescriptor,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment
    ) throws -> AggregateFieldLayout {
        // Class-bound parameters lay out as one object reference even without
        // a substitution, so an unspecialized dump still resolves their fields.
        let environment = environment.augmented(
            withRequirementFacts: ClassBoundGenericParameterAnalysis.layoutFacts(of: descriptor, in: image, imageUniverse: imageUniverse)
        )
        let records = try descriptor.fieldDescriptor(in: image.machO).records(in: image.machO)
        let structural = try accumulateFieldLayout(
            records: records,
            startOffset: 0,
            startAlignmentMask: 0,
            in: image,
            environment: environment
        )
        // A C-imported (foreign) struct's Swift field records omit C-only
        // layout (bitfields, padding), so the structural accumulation is only
        // trustworthy when it reproduces the compiler-embedded
        // `__swift5_builtin` whole-type record — the same record the
        // field-type resolution path consults before ever accumulating. On
        // contradiction the builtin wins and every field degrades: a confident
        // wrong offset (`__C.Decimal._mantissa` at 0, really 4; `__C.PathData`
        // as a size-0 aggregate) is worse than an honest unknown. Without a
        // builtin record there is nothing to check against and the structural
        // result stands.
        if descriptor.hasForeignMetadataInitialization,
           let builtinLayout = foreignBuiltinLayout(of: descriptor, in: image) {
            let structuralMatchesBuiltin = structural.size == builtinLayout.size
                && structural.stride == builtinLayout.stride
                && structural.alignment == builtinLayout.alignment
            guard structuralMatchesBuiltin else {
                let degradedFields = structural.fields.map { field in
                    FieldLayoutEntry(
                        fieldName: field.fieldName,
                        offset: 0,
                        typeMangledName: field.typeMangledName,
                        layout: field.layout,
                        resolution: .unknown(reason: .foreignTypeFieldOffsetsUnavailable)
                    )
                }
                return AggregateFieldLayout(
                    fields: degradedFields,
                    size: builtinLayout.size,
                    stride: builtinLayout.stride,
                    alignment: builtinLayout.alignment,
                    extraInhabitantCount: builtinLayout.extraInhabitantCount
                )
            }
            // Agreement: the records are complete, keep the per-field offsets;
            // the extra-inhabitant count still comes from the builtin record
            // (the authoritative value for a C type).
            return AggregateFieldLayout(
                fields: structural.fields,
                size: structural.size,
                stride: structural.stride,
                alignment: structural.alignment,
                extraInhabitantCount: builtinLayout.extraInhabitantCount
            )
        }
        return structural
    }

    /// The `__swift5_builtin` whole-type layout of a foreign (C-imported)
    /// struct, keyed by its demangled qualified name in the image that carries
    /// the descriptor. `nil` when the image embeds no builtin record for it.
    private func foreignBuiltinLayout(of descriptor: StructDescriptor, in image: ImageReference<MachO>) -> StaticTypeLayout? {
        guard
            let node = try? MetadataReader.demangleContext(
                for: TypeContextDescriptorWrapper.struct(descriptor).asContextDescriptorWrapper,
                in: image.machO
            ),
            let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node)
        else { return nil }
        return image.builtinLayoutIndex.layout(forTypeName: qualifiedTypeName)
    }

    // MARK: - Class

    private func fieldLayout(
        ofClass descriptor: ClassDescriptor,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment
    ) throws -> AggregateFieldLayout {
        // Class-bound parameters lay out as one object reference even without
        // a substitution — applied before the superclass computation so
        // `class Sub<Element: AnyObject>: Base<Element>` resolves its start.
        let environment = environment.augmented(
            withRequirementFacts: ClassBoundGenericParameterAnalysis.layoutFacts(of: descriptor, in: image, imageUniverse: imageUniverse)
        )
        let records = try descriptor.fieldDescriptor(in: image.machO).records(in: image.machO)
        do {
            let start = try resolver.superclassStartLayout(of: descriptor, in: image, environment: environment)
            // The maximum own-field alignment drives the ObjC ivar-slide
            // rounding (see `classFieldStartOffset`). Unresolvable fields are
            // skipped — their offsets degrade below anyway, so an understated
            // mask only affects an already-degraded region.
            let ownFieldAlignmentMask = records.reduce(into: 0) { mask, record in
                guard
                    let mangledTypeName = try? record.mangledTypeName(in: image.machO),
                    let fieldLayout = try? resolver.layout(forMangledTypeName: mangledTypeName, in: image, environment: environment)
                else { return }
                mask = max(mask, fieldLayout.alignmentMask)
            }
            let startOffset = resolver.classFieldStartOffset(
                of: descriptor,
                in: image,
                superclassInstanceSize: start.instanceSize,
                ownFieldAlignmentMask: ownFieldAlignmentMask
            )
            return try accumulateFieldLayout(
                records: records,
                startOffset: startOffset,
                startAlignmentMask: start.alignmentMask,
                in: image,
                environment: environment
            )
        } catch let LayoutResolutionError.unknown(reason) {
            // The superclass instance size is unknown, so no field offset in
            // this class is trustworthy: mark them all unknown. Each field's
            // *own* type layout is still resolved where possible — offsets need
            // the superclass start, per-type size/stride does not.
            let unresolvedFields = try records.map { record in
                let mangledTypeName = try record.mangledTypeName(in: image.machO)
                return FieldLayoutEntry(
                    fieldName: (try? record.fieldName(in: image.machO)) ?? "",
                    offset: 0,
                    typeMangledName: mangledTypeName.typeString,
                    layout: try? resolver.layout(forMangledTypeName: mangledTypeName, in: image, environment: environment),
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
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment
    ) throws -> AggregateFieldLayout {
        var offsetAccumulator = startOffset
        var alignmentMask = startAlignmentMask
        var isBitwiseTakable = true
        var extraInhabitantCount = 0
        var entries: [FieldLayoutEntry] = []
        entries.reserveCapacity(records.count)
        var accumulatorIsTrustworthy = true

        for record in records {
            let fieldName = (try? record.fieldName(in: image.machO)) ?? ""
            let mangledTypeName = try record.mangledTypeName(in: image.machO)
            let typeNameString = mangledTypeName.typeString

            guard accumulatorIsTrustworthy else {
                // The offset is untrustworthy, but the field's *own* type
                // layout usually is not — resolve it so renderers can still
                // report the type's size/stride behind an unresolved field.
                entries.append(FieldLayoutEntry(
                    fieldName: fieldName,
                    offset: offsetAccumulator,
                    typeMangledName: typeNameString,
                    layout: try? resolver.layout(forMangledTypeName: mangledTypeName, in: image, environment: environment),
                    resolution: .unknown(reason: .precedingFieldUnresolved)
                ))
                continue
            }

            do {
                let fieldLayout = try resolver.layout(forMangledTypeName: mangledTypeName, in: image, environment: environment)
                let fieldAlignmentMask = fieldLayout.alignmentMask
                let alignedOffset = (offsetAccumulator + fieldAlignmentMask) & ~fieldAlignmentMask
                // A zero-sized field occupies no storage, and the
                // compiler-emitted field-offset vector reports 0 for it (IRGen
                // `ElementLayout::completeEmpty` zeroes the reported
                // `ByteOffset`, tracking the running layout position
                // separately) — mirror that rather than the accumulator
                // position. Runtime-instantiated metadata
                // (`performBasicLayout`) would report the accumulator instead;
                // the difference is inert for a field without storage.
                let reportedOffset = fieldLayout.size == 0 ? 0 : alignedOffset
                entries.append(FieldLayoutEntry(
                    fieldName: fieldName,
                    offset: reportedOffset,
                    typeMangledName: typeNameString,
                    layout: fieldLayout,
                    resolution: .computed
                ))
                offsetAccumulator = alignedOffset + fieldLayout.size
                alignmentMask = max(alignmentMask, fieldAlignmentMask)
                isBitwiseTakable = isBitwiseTakable && fieldLayout.isBitwiseTakable
                // Value-aggregate rule: extra inhabitants come from the field
                // with the most (`swift_initStructMetadata`).
                extraInhabitantCount = max(extraInhabitantCount, fieldLayout.extraInhabitantCount)
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
            extraInhabitantCount: extraInhabitantCount
        )
    }
}
