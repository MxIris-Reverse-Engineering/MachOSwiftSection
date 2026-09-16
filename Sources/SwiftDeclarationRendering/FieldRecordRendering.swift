/// Spellings shared by the dump and interface paths for the two field-record
/// shapes a Swift 6.4 compiler emits that are not stored properties or
/// ordinary enum cases, so both paths say the same thing.
public enum FieldRecordRendering {
    /// The name of the artificial field record a `@_rawLayout(like: T)` struct
    /// carries (Swift 6.4): the like type `T`, emitted so offline tools can
    /// size the struct. It is not a stored property.
    public static let rawLayoutStorageFieldName = "_rawLayout"

    /// Whether a field record is that storage description. Both conditions
    /// matter: an actor's `$defaultActor` storage is artificial too and keeps
    /// rendering as a field, and nothing stops a stored property from being
    /// named `_rawLayout`.
    public static func isRawLayoutStorageRecord(name: String, isArtificial: Bool) -> Bool {
        isArtificial && name == rawLayoutStorageFieldName
    }

    /// The comment the dump path prints above that record, which it keeps
    /// rendering because dump shows what the record literally says.
    public static let artificialRawLayoutRecordComment = "artificial record: the @_rawLayout(like:) storage description, not a stored property"

    /// The line printed in place of an enum element whose record carries no
    /// name: the element is unavailable at run time (Swift 6.4 emits neither
    /// its name nor its payload type) but keeps its tag, so the case count
    /// and layout still include it.
    public static let namelessEnumCaseComment = "case (unavailable at run time; the compiler emitted no name)"
}
