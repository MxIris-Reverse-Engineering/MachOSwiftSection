#if os(macOS)

/// Extracts the fully-qualified type names a SourceKit-generated module
/// interface declares, from its ``InterfaceDeclarationNode`` tree.
///
/// Qualification follows the node parent chain: a type nested in a type
/// prefixes the outer name, and a type nested in an extension prefixes the
/// *extended* type's (possibly already dot-qualified) name — so
/// `extension Foo.Bar { public struct Baz }` yields `Foo.Bar.Baz`. The
/// extension node itself is never an indexed name.
///
/// Only type declarations, type aliases, and extensions are descended into;
/// nothing nested in a function or accessor is reachable in a generated
/// interface, and descending into ``InterfaceDeclarationNode/Kind/other``
/// nodes would only surface generic parameters and locals.
@available(macOS 13.0, *)
package enum InterfaceTypeNameExtractor {
    package static func fullyQualifiedTypeNames(in declarations: [InterfaceDeclarationNode]) -> [String] {
        var typeNames: [String] = []
        for declaration in declarations {
            appendTypeNames(of: declaration, qualificationPrefix: nil, into: &typeNames)
        }
        return typeNames
    }

    private static func appendTypeNames(
        of declaration: InterfaceDeclarationNode,
        qualificationPrefix: String?,
        into typeNames: inout [String]
    ) {
        switch declaration.kind {
        case .typeDeclaration, .typeAlias:
            guard let name = declaration.name, !name.isEmpty else { return }
            let qualifiedName = qualificationPrefix.map { "\($0).\(name)" } ?? name
            typeNames.append(qualifiedName)
            for child in declaration.children {
                appendTypeNames(of: child, qualificationPrefix: qualifiedName, into: &typeNames)
            }
        case .extension:
            // Not itself an indexed name; its extended-type name (already
            // qualified when SourceKit prints `extension Foo.Bar`) qualifies
            // the nested declarations.
            guard let extendedTypeName = declaration.name, !extendedTypeName.isEmpty else { return }
            for child in declaration.children {
                appendTypeNames(of: child, qualificationPrefix: extendedTypeName, into: &typeNames)
            }
        case .other:
            return
        }
    }
}

#endif
