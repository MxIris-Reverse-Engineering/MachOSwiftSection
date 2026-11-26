/// How a print spells the types a mangling places in the Clang importer's
/// modules (`__C`, `__C_Synthesized`): imported C structs, enums, typedefs,
/// CF types and Objective-C classes (evolution proposal
/// `c-imported-type-name-spelling`).
///
/// A type imported from C has two names. Its descriptor carries the one Swift
/// code uses (`AnyWeakAttribute`), while every mangled reference to it carries
/// the C declaration's own (`__C.AGWeakAttribute`), because the compiler
/// mangles Clang declarations by their Clang names. A print picks one of the
/// two for declarations, member types, extension headers and the types the
/// field layout comments name alike (evolution proposal
/// `consistent-c-imported-type-spelling`).
public enum CImportedTypeNameSpelling: String, Sendable, Hashable, CaseIterable {
    /// The name Swift code uses. A type whose module a registered resolver
    /// finds prints under it (`CoreFoundation.CGRect`,
    /// `UIKit.__UICellConfigurationState`); a type the image's own
    /// descriptors name prints under that name alone, renamed
    /// (`AnyWeakAttribute`) or imported under its C name
    /// (`AGDescriptionOption`); any other keeps its mangled spelling
    /// (`__C.AGFoo`): the image has no descriptor for it, or its
    /// descriptor's name may be only the leaf of a member import
    /// (`NSAttributedStringKey`'s says `Key`).
    case swiftName

    /// The C declaration's own name, exactly as the mangling spells it:
    /// `__C.AGWeakAttribute` in a reference, `AGWeakAttribute` on its
    /// declaration. No resolver is asked for what it prints, not even for the
    /// module: a C name under the Swift module (`UIKit.UICellConfigurationState`)
    /// could read as a Swift type of the same name. A print marking declared
    /// names (`marksCImportedTypeNames`) still asks for the Swift name the mark
    /// carries.
    case cName
}
