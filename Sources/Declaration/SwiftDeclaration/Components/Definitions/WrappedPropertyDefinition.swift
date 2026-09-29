import Demangling
import MachOSymbols

/// A property the source declared with a property wrapper (`@Wrapper var x: T`),
/// recovered at index time from what the compiler synthesized for it: the
/// backing-storage field `_x` of the wrapper type and, when the wrapper
/// projects, the computed `$x`.
///
/// The model keeps `_x` in `TypeDefinition.fields` and `$x` in `variables`
/// untouched — they are what the binary has, and the ABI diff / snapshot
/// records are built from them — and adds this description on top for the
/// interface printer, which renders the declaration the source wrote instead.
/// dump ignores it.
public struct WrappedPropertyDefinition: Sendable {
    /// Where the printable declaration of `x` comes from.
    public enum Origin: Sendable {
        /// `x`'s own accessor symbols are in the image, so the member
        /// variable already in `variables` renders — with the wrapper as its
        /// attribute.
        case declaredMember

        /// `x`'s accessors are stripped (an internal property in a
        /// release build, the norm for OS frameworks and shipped apps), so
        /// no member variable carries the declaration. It is synthesized
        /// from `_x` and the wrapper's `wrappedValue`: the declared type is
        /// the wrapper's `wrappedValue` type with the wrapper's generic
        /// arguments substituted (`EnvironmentObject<Model>.wrappedValue: A`
        /// gives `Model`), and `hasSetter` follows the wrapper's
        /// `wrappedValue` accessors.
        case synthesized(declaredTypeNode: NodeReference, hasSetter: Bool)
    }

    /// The property's name (`x`).
    public let name: String

    /// The compiler-synthesized backing field (`_x`), a member of
    /// `TypeDefinition.fields`.
    public let backingFieldName: String

    /// The compiler-synthesized projection (`$x`); present in `variables`
    /// only when the wrapper declares a `projectedValue` and the accessor
    /// survived stripping.
    public let projectionName: String

    /// The wrapper type to print as the attribute: bare (`@State`) when the
    /// wrapper takes exactly one generic argument and that argument is the
    /// wrapped property's own type — the case the compiler infers — and
    /// with its arguments otherwise (`@Tagged<String, Int>`). Both are valid
    /// source; the binary records only the backing field's full type.
    public let attributeTypeNode: NodeReference

    public let origin: Origin

    public init(name: String, backingFieldName: String, projectionName: String, attributeTypeNode: NodeReference, origin: Origin) {
        self.name = name
        self.backingFieldName = backingFieldName
        self.projectionName = projectionName
        self.attributeTypeNode = attributeTypeNode
        self.origin = origin
    }
}
