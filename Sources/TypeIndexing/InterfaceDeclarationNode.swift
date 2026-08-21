#if os(macOS)

/// One declaration node of a SourceKit-generated module interface, converted
/// out of the `editor.open.interface` response's `key.substructure` tree into
/// a plain value so extraction is a pure, testable function over it.
///
/// Only the declaration kinds the type-name extractor distinguishes are
/// modeled; everything else collapses to ``Kind/other`` and is never descended
/// into (nested types occur only inside type bodies and extensions).
@available(macOS 13.0, *)
package struct InterfaceDeclarationNode: Sendable, Equatable {
    package enum Kind: Sendable, Equatable {
        /// `struct`, `class`, `actor`, `enum`, or `protocol` — a declaration
        /// whose (qualified) name enters the index.
        case typeDeclaration
        /// `typealias` — enters the index by name but declares no members.
        case typeAlias
        /// An `extension` of some type: contributes its extended type name as
        /// a qualification prefix for nested declarations, but is not itself
        /// an indexed type.
        case `extension`
        /// Anything else (functions, properties, enum cases, parameters, …).
        case other
    }

    package let kind: Kind

    /// The declaration's name as SourceKit reports it. For an extension this
    /// is the extended type reference, which may already be dot-qualified
    /// (`extension Foo.Bar`).
    package let name: String?

    package let children: [InterfaceDeclarationNode]

    package init(kind: Kind, name: String?, children: [InterfaceDeclarationNode] = []) {
        self.kind = kind
        self.name = name
        self.children = children
    }

    /// Maps a SourceKit declaration-kind UID string
    /// (`source.lang.swift.decl.*`) onto the extractor's kind vocabulary.
    package static func kind(forUIDString uidString: String) -> Kind {
        switch uidString {
        case "source.lang.swift.decl.struct",
             "source.lang.swift.decl.class",
             "source.lang.swift.decl.actor",
             "source.lang.swift.decl.enum",
             "source.lang.swift.decl.protocol":
            return .typeDeclaration
        case "source.lang.swift.decl.typealias":
            return .typeAlias
        case "source.lang.swift.decl.extension",
             "source.lang.swift.decl.extension.struct",
             "source.lang.swift.decl.extension.class",
             "source.lang.swift.decl.extension.enum",
             "source.lang.swift.decl.extension.protocol":
            return .extension
        default:
            return .other
        }
    }
}

#endif
