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
    private let imageUniverse: ImageUniverse<MachO>
    private let resolver: StaticTypeLayoutResolver<MachO>

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
        let environment = GenericArgumentEnvironment.make(forBoundGenericNode: node)
        return try fieldLayout(of: resolved.descriptor, in: resolved.image, environment: environment)
    }

    /// The resolved whole-type layout of a struct field type. Convenience for
    /// callers that want size/stride rather than per-field offsets.
    public func typeLayout(ofStruct structDescriptor: StructDescriptor) throws -> TypeLayoutInfo {
        try resolver.computeStructLayout(structDescriptor, in: imageUniverse.rootImage).typeLayoutInfo()
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
        let records = try descriptor.fieldDescriptor(in: image.machO).records(in: image.machO)
        return try accumulateFieldLayout(
            records: records,
            startOffset: 0,
            startAlignmentMask: 0,
            in: image,
            environment: environment
        )
    }

    // MARK: - Class

    private func fieldLayout(
        ofClass descriptor: ClassDescriptor,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment
    ) throws -> AggregateFieldLayout {
        let records = try descriptor.fieldDescriptor(in: image.machO).records(in: image.machO)
        do {
            let start = try resolver.superclassStartLayout(of: descriptor, in: image, environment: environment)
            return try accumulateFieldLayout(
                records: records,
                startOffset: start.instanceSize,
                startAlignmentMask: start.alignmentMask,
                in: image,
                environment: environment
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
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment
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
                let fieldLayout = try resolver.layout(forMangledTypeName: mangledTypeName, in: image, environment: environment)
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
