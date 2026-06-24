import MachOSwiftSection
@_spi(Internals) import SwiftInspection

/// A per-image index of the `__swift5_builtin` section's `BuiltinTypeDescriptor`
/// records, keyed by the type's fully-qualified name (e.g. `"__C.CGRect"`,
/// `"SymbolTestsCore.Enums.MultiPayloadEnumTests"`), each carrying the statically
/// embedded `(size, stride, alignment, extra inhabitants)`.
///
/// The compiler emits a builtin descriptor for a type whose layout the
/// reflection reader cannot derive structurally — imported C value types and
/// multi-payload enums in particular — recording the layout Clang / IRGen
/// computed at compile time. The descriptor is emitted in *every image that
/// references the type reflectively* (e.g. as a stored field), so the using
/// image carries it. This is the authoritative whole-type layout for those
/// types, which the resolver consults before its structural paths.
///
/// The descriptor's `typeName` is a **symbolic reference** (a relative pointer
/// to the type's context descriptor), so its raw string is empty; the name is
/// recovered by demangling, then keyed with the same `nominalQualifiedName`
/// formatting the resolver looks types up by.
public struct BuiltinTypeLayoutIndex: Sendable {
    private let layoutsByQualifiedName: [String: TypeLayoutInfo]

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(machO: MachO) throws {
        var index: [String: TypeLayoutInfo] = [:]
        // A missing `__swift5_builtin` section is a normal state — most images
        // emit no builtin descriptors — so it yields an empty index rather than
        // failing. This matters for dependency-closure images (a sibling
        // framework, a pure-ObjC/C dylib) that have no builtin section at all.
        let builtinTypeDescriptors: [BuiltinTypeDescriptor]
        do {
            builtinTypeDescriptors = try machO.swift.builtinTypeDescriptors
        } catch let MachOSwiftSectionError.sectionNotFound(section, _) where section == .__swift5_builtin {
            builtinTypeDescriptors = []
        }
        for descriptor in builtinTypeDescriptors {
            guard let mangledTypeName = try descriptor.typeName(in: machO) else { continue }
            guard let qualifiedName = Self.qualifiedName(of: mangledTypeName, in: machO) else { continue }
            let layout = TypeLayoutInfo(
                size: Int(descriptor.layout.size),
                stride: Int(descriptor.layout.stride),
                alignmentMask: max(0, descriptor.alignment - 1),
                extraInhabitantCount: Int(descriptor.layout.numExtraInhabitants),
                isBitwiseTakable: descriptor.isBitwiseTakable
            )
            // First writer wins: non-generic qualified names are unique, so this
            // only matters for the (resolver-unread) generic-instantiation entries.
            if index[qualifiedName] == nil {
                index[qualifiedName] = layout
            }
        }
        self.layoutsByQualifiedName = index
    }

    /// Recovers a builtin descriptor's fully-qualified type name by demangling
    /// its (symbolic-reference) mangled name, falling back to the raw string for
    /// any plain-named entry.
    private static func qualifiedName<MachO: MachOSwiftSectionRepresentableWithCache>(
        of mangledTypeName: MangledName,
        in machO: MachO
    ) -> String? {
        if let node = try? MetadataReader.demangleType(for: mangledTypeName, in: machO),
           let qualifiedName = NodeTypeNaming.nominalQualifiedName(of: node) {
            return qualifiedName
        }
        let rawName = mangledTypeName.typeString
        return rawName.isEmpty ? nil : rawName
    }

    /// Returns the embedded whole-type layout for a fully-qualified type name, or
    /// `nil` if this image emits no builtin descriptor for it.
    public func layout(forTypeName qualifiedTypeName: String) -> TypeLayoutInfo? {
        layoutsByQualifiedName[qualifiedTypeName]
    }
}
