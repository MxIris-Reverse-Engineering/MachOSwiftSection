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
        return nestedChildren(forTypeNode: node, in: imageUniverse.rootImage, baseOffset: baseOffset, depth: 0, depthLimit: depthLimit)
    }

    /// Recurses into a (possibly `.type`-wrapped, possibly bound-generic) type
    /// node, returning its sub-fields. `image` is the image the node's mangled
    /// names are read against; recursion switches it to a nested type's defining
    /// image when that type lives in a dependency.
    private func nestedChildren(
        forTypeNode typeNode: Node,
        in image: ImageReference<MachO>,
        baseOffset: Int,
        depth: Int,
        depthLimit: Int
    ) -> [NestedFieldOffset] {
        guard depth < depthLimit else { return [] }
        let node = (typeNode.kind == .type ? typeNode.firstChild : typeNode) ?? typeNode
        switch NodeTypeNaming.nominalCategory(of: node) {
        case .structure:
            return structChildren(forNode: node, baseOffset: baseOffset, depth: depth, depthLimit: depthLimit)
        case .enum:
            return enumPayloadChildren(forNode: node, baseOffset: baseOffset, depth: depth, depthLimit: depthLimit)
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
        depthLimit: Int
    ) -> [NestedFieldOffset] {
        guard
            let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node),
            let resolved = imageUniverse.resolveType(byQualifiedTypeName: qualifiedTypeName),
            let structDescriptor = resolved.descriptor.struct
        else { return [] }
        let environment = GenericArgumentEnvironment.make(forBoundGenericNode: node)
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
                depthLimit: depthLimit
            ))
        }
        return children
    }

    private func enumPayloadChildren(
        forNode node: Node,
        baseOffset: Int,
        depth: Int,
        depthLimit: Int
    ) -> [NestedFieldOffset] {
        guard
            let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node),
            let resolved = imageUniverse.resolveType(byQualifiedTypeName: qualifiedTypeName),
            let enumDescriptor = resolved.descriptor.enum,
            enumDescriptor.hasPayloadCases,
            let records = try? enumDescriptor.fieldDescriptor(in: resolved.image.machO).records(in: resolved.image.machO)
        else { return [] }
        let environment = GenericArgumentEnvironment.make(forBoundGenericNode: node)
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
                depthLimit: depthLimit
            ))
        }
        return children
    }

    /// Builds a `NestedFieldOffset` for one field/payload record: substitutes the
    /// enclosing type's generic arguments into the record's type, prints its name,
    /// and recurses into it.
    private func makeNode(
        forFieldRecord record: FieldRecord,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment,
        fallbackFieldName: String,
        absoluteOffset: Int,
        depth: Int,
        depthLimit: Int
    ) -> NestedFieldOffset {
        let fieldName = ((try? record.fieldName(in: image.machO)).flatMap { $0.isEmpty ? nil : $0 }) ?? fallbackFieldName
        let fieldTypeNode: Node? = (try? record.mangledTypeName(in: image.machO)).flatMap { mangledTypeName in
            (try? MetadataReader.demangleType(for: mangledTypeName, in: image.machO)).map { environment.substituting(in: $0) }
        }
        let typeName = fieldTypeNode?.print(using: .default) ?? ""
        let children = fieldTypeNode.map {
            nestedChildren(forTypeNode: $0, in: image, baseOffset: absoluteOffset, depth: depth + 1, depthLimit: depthLimit)
        } ?? []
        return NestedFieldOffset(fieldName: fieldName, typeName: typeName, offset: absoluteOffset, children: children)
    }
}
