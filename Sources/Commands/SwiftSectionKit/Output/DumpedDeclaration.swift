/// What one top-level piece of a `dump` or `objc dump` product declares.
///
/// Handed to ``SwiftSectionOutput/write(_:declaring:)`` beside the piece, so
/// that a host can file each declaration on its own — one file per type, say —
/// without indexing the binary a second time.
///
/// Built by the requests, not by a host: a later version may add a case, so do
/// not rely on switching over it exhaustively.
public enum DumpedDeclaration: Sendable, Hashable {
    /// A Swift declaration from `section`, named as the dump prints it. A
    /// protocol conformance and an associated type are named after the type
    /// they extend, as their `extension` line spells it — for a type the image
    /// declares, that type's own name, so the pieces of one type share it.
    /// `nil` when the name could not be rendered although the declaration
    /// itself was.
    case swift(DumpSection, name: String?)
    /// An Objective-C declaration of `kind`. A category is named
    /// `ClassName(CategoryName)`, as the index names it.
    case objc(ObjCDeclarationKind, name: String)
}
