/// The importer-provided identity a C-imported type context descriptor carries
/// after its name.
///
/// IRGen writes a type context descriptor's name as the type's user-facing
/// Swift name. When the type was imported from C and its identity differs
/// from that name, it appends further NUL-terminated strings right after the
/// name and terminates the sequence with an empty string
/// (`TypeContextDescriptorBuilderBase::computeIdentity` / `addName`,
/// `lib/IRGen/GenMeta.cpp`); `TypeContextDescriptorFlags.hasImportInfo`
/// announces their presence. Each string starts with a component tag
/// (`swift/ABI/TypeIdentity.h`):
///
/// - `N`: the ABI name, the C declaration's own name when a `swift_name`
///   attribute or a typedef gave the Swift type a different one
///   (`NSRange`'s tag is `_NSRange`; `CGColor` is the `CGColorRef` typedef;
///   `Decimal` is `NSDecimal`).
/// - `S`: the symbol namespace. The only value the compiler emits is
///   ``cTypedefSymbolNamespace``, marking a C typedef promoted to its own
///   nominal type (`swift_wrapper` typedefs, CF types, typedefs of anonymous
///   tags). Manglings spell such a type as a `typeAlias`.
/// - `R`: the related-entity name of an importer-synthesized type, such as
///   the error struct synthesized for an `NS_ERROR_ENUM` (`e`). The ABI name
///   then names the original C declaration, and the mangling wraps the name
///   in a `relatedEntityDeclName`.
///
/// The runtime parses the same sequence in `ParsedTypeIdentity::parse`
/// (`stdlib/public/runtime/MetadataLookup.cpp`).
public struct TypeImportInfo: Hashable, Sendable {
    /// The `S` component value marking a C typedef imported as a distinct
    /// nominal type (`TypeImportSymbolNamespace::CTypedef`).
    public static let cTypedefSymbolNamespace = "t"

    /// The `N` component, or `nil` when the ABI name equals the user-facing name.
    public let abiName: String?

    /// The `S` component, or `nil` when the type sits in the namespace its
    /// kind implies (tag for structs and enums, ordinary for classes).
    public let symbolNamespace: String?

    /// The `R` component, or `nil` for a type that is not a related entity.
    public let relatedEntityName: String?

    /// Whether the type is a C typedef promoted to a nominal type, which
    /// manglings spell as a `typeAlias`.
    public var isCTypedef: Bool {
        symbolNamespace == Self.cTypedefSymbolNamespace
    }

    /// Whether the type is an importer-synthesized related entity of another
    /// C declaration.
    public var isRelatedEntity: Bool {
        guard let relatedEntityName else { return false }
        return !relatedEntityName.isEmpty
    }

    init(abiName: String?, symbolNamespace: String?, relatedEntityName: String?) {
        self.abiName = abiName
        self.symbolNamespace = symbolNamespace
        self.relatedEntityName = relatedEntityName
    }

    /// Parses the tagged component strings that follow a descriptor's name.
    ///
    /// Mirrors `TypeImportInfo::collect` in the non-asserting mode the remote
    /// reader uses: a component with an unknown tag or an empty value is
    /// ignored rather than rejected, so a newer compiler's extra components
    /// degrade to "not understood" instead of failing the whole name.
    init(components: [String]) {
        var abiName: String?
        var symbolNamespace: String?
        var relatedEntityName: String?
        for component in components {
            guard let tag = component.first else { continue }
            let value = String(component.dropFirst())
            guard !value.isEmpty else { continue }
            switch tag {
            case "N":
                abiName = value
            case "S":
                symbolNamespace = value
            case "R":
                relatedEntityName = value
            default:
                continue
            }
        }
        self.init(abiName: abiName, symbolNamespace: symbolNamespace, relatedEntityName: relatedEntityName)
    }
}
