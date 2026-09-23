@_spi(Internals) import Demangling
import MachOKit
import MachOSwiftSection

/// Runtime-metadata-driven node substitution for *specialized* type
/// definitions rendered by the model-driven interface path.
///
/// Restores the pre-leaf-migration behavior that lived on
/// `SwiftDump.TypedDumper` (`resolveFieldMetatype` / `boundDumpedMetatype` /
/// `fieldDemangledTypeNode` / `boundDumpedTypeNode`): when a definition
/// carries a specialized in-process metadata, its own name renders in the
/// bound form (`Box<A>` → `Box<Int>`) and each field's type node resolves
/// through the runtime with the generic parameters substituted
/// (`var value: A` → `var value: Int`). The dump path keeps its own copy of
/// this machinery on `TypedDumper`; this type is the `SwiftDump`-free mirror
/// consumed by `SwiftPrinting`.
///
/// Everything is best-effort by design: any failure (runtime cannot resolve
/// the mangled name, metadata kind outside struct/enum/class, pre-`_mangledTypeName`
/// runtimes) returns `nil` and callers fall back to the unbound
/// representation — exactly the old dumper contract.
package enum SpecializedMetadataNodeSubstitution {
    /// Resolves a field's mangled type name against the specialized
    /// in-process metadata and returns the demangled node of the resolved
    /// concrete type — i.e. the field's type with every generic-parameter
    /// reference substituted by its bound argument. Mirrors
    /// `TypedDumper.fieldDemangledTypeNode(for:)`'s substituted branch.
    package static func substitutedFieldTypeNode(
        for mangledTypeName: MangledName,
        metadata: MetadataWrapper,
        in machOImage: MachOImage
    ) -> Node? {
        guard let metatype = resolveFieldMetatype(for: mangledTypeName, metadata: metadata, in: machOImage) else {
            return nil
        }
        return RuntimeTypeNameDemangling.node(forMetatype: metatype)
    }

    /// Returns a demangled node for the *specialized type itself*, with its
    /// generic parameters bound to the concrete arguments carried by the
    /// specialized in-process metadata. Mirrors
    /// `TypedDumper.boundDumpedTypeNode()`.
    package static func boundTypeNode(for metadata: MetadataWrapper) -> Node? {
        guard let metadataPointer = specializedMetadataPointer(of: metadata) else { return nil }
        // Specialized in-process metadata pointers and `Any.Type` are
        // representationally identical — bitcasting recovers the metatype
        // we'd get from `Foo<Int>.self`.
        let metatype = unsafeBitCast(metadataPointer, to: Any.Type.self)
        return RuntimeTypeNameDemangling.node(forMetatype: metatype)
    }

    /// Mirrors the constrained `TypedDumper.resolveFieldMetatype`
    /// implementations (identical for value and class metadata) and
    /// `RuntimeFieldLayoutBackend.resolveFieldMetatype`, restricted to the
    /// specialized case — the non-generic bare-name resolution stays with
    /// the layout backend, which is the only caller that needs it.
    private static func resolveFieldMetatype(
        for mangledTypeName: MangledName,
        metadata: MetadataWrapper,
        in machOImage: MachOImage
    ) -> Any.Type? {
        if let structMetadata = metadata.struct {
            return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, specializedFrom: structMetadata, in: machOImage)
        }
        if let enumMetadata = metadata.enum ?? metadata.optional {
            return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, specializedFrom: enumMetadata, in: machOImage)
        }
        if let classMetadata = metadata.class {
            return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, specializedFrom: classMetadata, in: machOImage)
        }
        return nil
    }

    private static func specializedMetadataPointer(of metadata: MetadataWrapper) -> UnsafeRawPointer? {
        if let structMetadata = metadata.struct {
            return try? structMetadata.asPointer
        }
        if let enumMetadata = metadata.enum ?? metadata.optional {
            return try? enumMetadata.asPointer
        }
        if let classMetadata = metadata.class {
            return try? classMetadata.asPointer
        }
        return nil
    }
}
