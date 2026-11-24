import Semantic

/// The two names of a C-imported type: what Swift code calls it and what its C
/// declaration is called (evolution proposal `c-imported-type-name-spelling`).
public struct CImportedTypeNames: Sendable, Hashable {
    /// `AnyWeakAttribute`; dotted when a resolver spells a type imported as a
    /// member (`NSAttributedString.Key`).
    public let swiftName: String

    /// `AGWeakAttribute`, the name every mangled reference spells.
    public let cName: String

    public init(swiftName: String, cName: String) {
        self.swiftName = swiftName
        self.cName = cName
    }
}

extension AnnotationRegion.Kind {
    private static let cImportedTypeNamePrefix = "cImportedTypeName"

    /// In no Swift or C name, so a dotted Swift name passes through whole. Not
    /// a control character: swift-semantic-string rejects those in a kind,
    /// since its own markers are control characters.
    private static let cImportedTypeNameSeparator: Character = "|"

    /// The declared name of a C-imported type whose Swift and C names differ,
    /// marked when `SwiftDeclarationPrintConfiguration.marksCImportedTypeNames`
    /// is on. The region's text is the spelling printed; the kind carries both
    /// names, so a host can offer the other one without reading the text. Not a
    /// comment: a host drawing annotation regions as comments leaves these out.
    public static func cImportedTypeName(_ names: CImportedTypeNames) -> Self {
        let separator = String(cImportedTypeNameSeparator)
        return Self(cImportedTypeNamePrefix + separator + names.swiftName + separator + names.cName)
    }

    /// The names a ``cImportedTypeName(_:)`` kind carries; nil for any other
    /// kind.
    public var cImportedTypeNames: CImportedTypeNames? {
        let components = rawValue.split(separator: Self.cImportedTypeNameSeparator, omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == Self.cImportedTypeNamePrefix,
              !components[1].isEmpty,
              !components[2].isEmpty
        else { return nil }
        return CImportedTypeNames(swiftName: String(components[1]), cName: String(components[2]))
    }
}
