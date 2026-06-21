import MachOSwiftSection

/// A per-image index of the `__swift5_builtin` section's `BuiltinTypeDescriptor`
/// records, keyed by the builtin type's printed name (e.g. `"Builtin.Int64"`),
/// each carrying the statically embedded `(size, stride, alignment, extra
/// inhabitants)`.
///
/// Builtin descriptors are emitted per image, so this index is built per image.
/// It backs the resolver's `.builtinTypeName` dispatch as a supplement to the
/// hard-coded `KnownLayoutTable`.
public struct BuiltinTypeLayoutIndex: Sendable {
    private let layoutsByTypeName: [String: TypeLayoutInfo]

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(machO: MachO) throws {
        var index: [String: TypeLayoutInfo] = [:]
        for descriptor in try machO.swift.builtinTypeDescriptors {
            guard let typeName = try descriptor.typeName(in: machO) else { continue }
            let layout = TypeLayoutInfo(
                size: Int(descriptor.layout.size),
                stride: Int(descriptor.layout.stride),
                alignmentMask: max(0, descriptor.alignment - 1),
                extraInhabitantCount: Int(descriptor.layout.numExtraInhabitants),
                isBitwiseTakable: descriptor.isBitwiseTakable
            )
            index[typeName.typeString] = layout
        }
        self.layoutsByTypeName = index
    }

    /// Returns the embedded layout for a builtin type's printed name, or `nil`
    /// if this image does not emit a descriptor for it.
    public func layout(forTypeName typeName: String) -> TypeLayoutInfo? {
        layoutsByTypeName[typeName]
    }
}
