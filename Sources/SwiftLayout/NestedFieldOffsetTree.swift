import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// One node of the static expanded nested-field-offset tree: a stored field of
/// some nested aggregate, its absolute byte offset, its printable type name, and
/// the further sub-fields nested inside it.
///
/// This is the static (offline) counterpart of the runtime nested walk in
/// `SwiftDeclarationRendering`'s `FieldLayoutRenderer` (which materialises
/// in-process metadata). The renderer formats this tree into `// ├──`-style
/// comments; the offset/context-heavy work (resolving each field type to its
/// defining image, recomputing offsets, substituting generic arguments) stays
/// here, where the `ImageUniverse` and per-image readers live.
public struct NestedFieldOffset: Sendable {
    /// The stored property's (or enum payload's) name.
    public let fieldName: String
    /// The field type's printable name (e.g. `Swift.Int`, `MyModule.Box<Int>`).
    public let typeName: String
    /// The field's absolute byte offset from the start of the outermost type.
    public let offset: Int
    /// Sub-fields nested inside this field's type (empty for a leaf, a class
    /// reference, or an aggregate the engine could not expand).
    public let children: [NestedFieldOffset]

    public init(fieldName: String, typeName: String, offset: Int, children: [NestedFieldOffset]) {
        self.fieldName = fieldName
        self.typeName = typeName
        self.offset = offset
        self.children = children
    }
}

extension StaticLayoutCalculator {
    /// Builds the expanded nested-field-offset tree for a field whose type is
    /// `mangledTypeName`, placed at `baseOffset`. Returns the field type's own
    /// stored fields (struct) or payload fields (enum), each with offsets
    /// relative to the outermost type, recursing up to `depthLimit` levels.
    ///
    /// Mirrors the runtime walk's reach: it descends into nested structs and
    /// enum payloads but stops at class references (a single pointer) and at any
    /// type it cannot resolve — yielding a shallower tree rather than failing.
    public func nestedFieldOffsetTree(
        forMangledTypeName mangledTypeName: MangledName,
        baseOffset: Int,
        depthLimit: Int
    ) -> [NestedFieldOffset] {
        guard let node = try? MetadataReader.demangleType(for: mangledTypeName, in: imageUniverse.rootImage.machO) else {
            return []
        }
        return nestedChildren(
            forTypeNode: node,
            typeDisplayName: node.print(using: .default),
            in: imageUniverse.rootImage,
            baseOffset: baseOffset,
            depth: 0,
            depthLimit: depthLimit,
            enclosingTypeNames: []
        )
    }

    /// Recurses into a (possibly `.type`-wrapped, possibly bound-generic) type
    /// node, returning its sub-fields. `image` is the image the node's mangled
    /// names are read against; recursion switches it to a nested type's defining
    /// image when that type lives in a dependency.
    ///
    /// `enclosingTypeNames` holds the types already open on the **current path**
    /// down to this node, keyed by printed name so that two specializations of
    /// one generic (`Box<Int>` vs `Box<String>`) stay distinct. Re-entering a
    /// type that is still open above us is a cycle, and it is cut here — the
    /// static counterpart of the runtime walk's `enclosingMetatypes` guard, and
    /// for the same reason: the depth limit bounds how *deep* a walk goes, but a
    /// cycle explodes the number of *paths*, which no depth limit can bound.
    ///
    /// Path-scoped, not global: a type legitimately reached through two
    /// different fields must expand under both.
    private func nestedChildren(
        forTypeNode typeNode: Node,
        typeDisplayName: String,
        in image: ImageReference<MachO>,
        baseOffset: Int,
        depth: Int,
        depthLimit: Int,
        enclosingTypeNames: Set<String>
    ) -> [NestedFieldOffset] {
        guard depth < depthLimit else { return [] }
        guard !typeDisplayName.isEmpty, !enclosingTypeNames.contains(typeDisplayName) else { return [] }
        let nestedEnclosingTypeNames = enclosingTypeNames.union([typeDisplayName])
        let node = (typeNode.kind == .type ? typeNode.firstChild : typeNode) ?? typeNode
        switch NodeTypeNaming.nominalCategory(of: node) {
        case .structure:
            return structChildren(forNode: node, baseOffset: baseOffset, depth: depth, depthLimit: depthLimit, enclosingTypeNames: nestedEnclosingTypeNames)
        case .enum:
            return enumPayloadChildren(forNode: node, baseOffset: baseOffset, depth: depth, depthLimit: depthLimit, enclosingTypeNames: nestedEnclosingTypeNames)
        case .class, .none:
            // A class field is a reference (a single pointer); a non-nominal
            // type (tuple, existential, …) has no statically-walkable nested
            // field layout here. Either way: a leaf.
            return []
        }
    }

    private func structChildren(
        forNode node: Node,
        baseOffset: Int,
        depth: Int,
        depthLimit: Int,
        enclosingTypeNames: Set<String>
    ) -> [NestedFieldOffset] {
        guard
            let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node),
            let resolved = imageUniverse.resolveType(byQualifiedTypeName: qualifiedTypeName),
            let structDescriptor = resolved.descriptor.struct
        else { return [] }
        let environment = GenericArgumentEnvironment.make(forInstantiatedTypeNode: node)
        guard
            let aggregate = try? resolver.computeStructLayout(structDescriptor, in: resolved.image, environment: environment),
            let records = try? structDescriptor.fieldDescriptor(in: resolved.image.machO).records(in: resolved.image.machO)
        else { return [] }

        var children: [NestedFieldOffset] = []
        for (index, record) in records.enumerated() {
            guard index < aggregate.fieldOffsets.count else { break }
            let absoluteOffset = baseOffset + aggregate.fieldOffsets[index]
            children.append(makeNode(
                forFieldRecord: record,
                in: resolved.image,
                environment: environment,
                fallbackFieldName: "",
                absoluteOffset: absoluteOffset,
                depth: depth,
                depthLimit: depthLimit,
                enclosingTypeNames: enclosingTypeNames,
                descendsIntoFieldType: true
            ))
        }
        return children
    }

    private func enumPayloadChildren(
        forNode node: Node,
        baseOffset: Int,
        depth: Int,
        depthLimit: Int,
        enclosingTypeNames: Set<String>
    ) -> [NestedFieldOffset] {
        guard
            let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node),
            let resolved = imageUniverse.resolveType(byQualifiedTypeName: qualifiedTypeName),
            let enumDescriptor = resolved.descriptor.enum,
            enumDescriptor.hasPayloadCases,
            let records = try? enumDescriptor.fieldDescriptor(in: resolved.image.machO).records(in: resolved.image.machO)
        else { return [] }
        let environment = GenericArgumentEnvironment.make(forInstantiatedTypeNode: node)
        let payloadRecords = records.prefix(enumDescriptor.numberOfPayloadCases)

        var children: [NestedFieldOffset] = []
        for record in payloadRecords {
            guard let mangledTypeName = try? record.mangledTypeName(in: resolved.image.machO), !mangledTypeName.isEmpty else { continue }
            // A payload occupies the enum's payload area, which begins at the
            // enum's own offset — every payload starts at `baseOffset`.
            children.append(makeNode(
                forFieldRecord: record,
                in: resolved.image,
                environment: environment,
                fallbackFieldName: "payload",
                absoluteOffset: baseOffset,
                depth: depth,
                depthLimit: depthLimit,
                enclosingTypeNames: enclosingTypeNames,
                // An indirect case stores a heap box reference, not the declared
                // payload laid out inline, so its fields are not at these
                // offsets. `EnumLayoutBridge` already reads the flag this way.
                descendsIntoFieldType: !record.layout.flags.contains(.isIndirectCase)
            ))
        }
        return children
    }

    /// Builds a `NestedFieldOffset` for one field/payload record: substitutes the
    /// enclosing type's generic arguments into the record's type, prints its name,
    /// and recurses into it.
    ///
    /// `descendsIntoFieldType` is `false` for a field whose storage is a pointer
    /// to the declared type rather than the type itself (an `indirect` enum
    /// case's boxed payload) — the node is still reported, it just has no
    /// children.
    private func makeNode(
        forFieldRecord record: FieldRecord,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment,
        fallbackFieldName: String,
        absoluteOffset: Int,
        depth: Int,
        depthLimit: Int,
        enclosingTypeNames: Set<String>,
        descendsIntoFieldType: Bool
    ) -> NestedFieldOffset {
        let fieldName = ((try? record.fieldName(in: image.machO)).flatMap { $0.isEmpty ? nil : $0 }) ?? fallbackFieldName
        let fieldTypeNode: Node? = (try? record.mangledTypeName(in: image.machO)).flatMap { mangledTypeName in
            (try? MetadataReader.demangleType(for: mangledTypeName, in: image.machO)).map { environment.substituting(in: $0) }
        }
        let typeName = fieldTypeNode?.print(using: .default) ?? ""
        let children = descendsIntoFieldType ? (fieldTypeNode.map {
            nestedChildren(
                forTypeNode: $0,
                typeDisplayName: typeName,
                in: image,
                baseOffset: absoluteOffset,
                depth: depth + 1,
                depthLimit: depthLimit,
                enclosingTypeNames: enclosingTypeNames
            )
        } ?? []) : []
        return NestedFieldOffset(fieldName: fieldName, typeName: typeName, offset: absoluteOffset, children: children)
    }
}
