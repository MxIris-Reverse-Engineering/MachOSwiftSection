/// How a print spells the types a mangling places in the Clang importer's
/// modules (`__C`, `__C_Synthesized`): imported C structs, enums, typedefs,
/// CF types and Objective-C classes (evolution proposal
/// `c-imported-type-name-spelling`).
///
/// A type imported from C has two names. Its descriptor carries the one Swift
/// code uses (`AnyWeakAttribute`), while every mangled reference to it carries
/// the C declaration's own (`__C.AGWeakAttribute`), because the compiler
/// mangles Clang declarations by their Clang names. A print picks one of the
/// two for declarations, member types and extension headers alike.
public enum CImportedTypeNameSpelling: String, Sendable, Hashable, CaseIterable {
    /// The name Swift code uses. A type whose module a registered resolver
    /// finds prints under it (`CoreFoundation.CGRect`,
    /// `UIKit.__UICellConfigurationState`); a type the image's own
    /// descriptors rename prints under that name alone (`AnyWeakAttribute`);
    /// any other keeps its mangled spelling (`__C.AGFoo`).
    case swiftName

    /// The C declaration's own name, exactly as the mangling spells it:
    /// `__C.AGWeakAttribute` in a reference, `AGWeakAttribute` on its
    /// declaration. No resolver is asked, not even for the module: a C name
    /// under the Swift module (`UIKit.UICellConfigurationState`) could read as
    /// a Swift type of the same name.
    case cName
}
