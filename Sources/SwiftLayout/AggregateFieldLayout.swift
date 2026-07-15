/// The per-field static layout of a struct or class, plus the aggregate's own
/// size/stride/alignment.
///
/// Fields are returned in declaration order. Each field reports whether its
/// offset was `computed` or left `unknown`; once one field is unknown the
/// running offset is no longer trustworthy, so every following field is also
/// `unknown` (its `offset` is best-effort, not authoritative).
public struct AggregateFieldLayout: Sendable {
    public let fields: [FieldLayoutEntry]
    public let size: Int
    public let stride: Int
    public let alignment: Int
    public let extraInhabitantCount: Int

    public init(fields: [FieldLayoutEntry], size: Int, stride: Int, alignment: Int, extraInhabitantCount: Int) {
        self.fields = fields
        self.size = size
        self.stride = stride
        self.alignment = alignment
        self.extraInhabitantCount = extraInhabitantCount
    }

    /// The byte offsets of the fields whose layout was successfully computed,
    /// in declaration order, stopping at the first unresolved field. This is
    /// the directly comparable counterpart to a runtime field-offset vector.
    public var computedFieldOffsets: [Int] {
        var offsets: [Int] = []
        for field in fields {
            guard case .computed = field.resolution else { break }
            offsets.append(field.offset)
        }
        return offsets
    }
}

/// One stored property's resolved placement.
public struct FieldLayoutEntry: Sendable {
    public let fieldName: String
    public let offset: Int
    public let typeMangledName: String
    /// The field type's own layout, or `nil` when unresolved.
    public let layout: StaticTypeLayout?
    public let resolution: FieldResolution

    public init(
        fieldName: String,
        offset: Int,
        typeMangledName: String,
        layout: StaticTypeLayout?,
        resolution: FieldResolution
    ) {
        self.fieldName = fieldName
        self.offset = offset
        self.typeMangledName = typeMangledName
        self.layout = layout
        self.resolution = resolution
    }
}

/// Whether a field's offset was computed or why it could not be.
public enum FieldResolution: Sendable, Hashable {
    case computed
    case unknown(reason: LayoutUnknownReason)
}
