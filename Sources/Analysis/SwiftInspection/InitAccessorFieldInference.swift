@_spi(Internals) import Demangling

/// What a SE-0400 init accessor initializes, as far as an image tells
/// (evolution proposal `init-accessor-recovery`).
///
/// The source lists them in `@storageRestrictions(initializes:accesses:)`,
/// and no image records the attribute: the compiler lowers each
/// `initializes:` entry to an indirect result and each `accesses:` entry to
/// an `inout` parameter, pointers straight at the storage, so the init
/// accessor's code does not say which fields they are either. What is left is
/// the naming convention the `@Observable` macro, property wrappers and
/// hand-written storage share: a stored property `_x` with the type of the
/// property `x` is the storage `x`'s init accessor initializes. The type must
/// match — SwiftData's `@Model` keeps a placeholder of another type in `_x`,
/// and its init accessor initializes the value elsewhere.
///
/// Shared by the declaration model and the dump, which reads no model.
package enum InitAccessorFieldInference {
    /// A stored property of the type that declares the init accessor.
    package struct StoredField {
        package let name: String

        /// The field record's type, `weak` / `unowned` storage included.
        package let typeNode: Node

        package init(name: String, typeNode: Node) {
            self.name = name
            self.typeNode = typeNode
        }
    }

    /// The fields the init accessor `symbolNode` names is inferred to
    /// initialize, by the property name and type its own symbol spells. That
    /// type need not be the getter's: SwiftUICore keeps
    /// `_GeometryActionModifier2.value`'s getter and setter under the mangling
    /// from before the type became `@Sendable` (`@_silgen_name`), and only
    /// the init accessor spells the type its field `_value` has. Like every
    /// declaration's own mangling it leaves `sending` out, which the
    /// comparison sets aside. `nil` when `symbolNode` is no init accessor of
    /// a variable.
    package static func initializedFieldNames(
        ofInitAccessorSymbol symbolNode: NodeReference,
        fieldNamed: (String) -> StoredField?
    ) -> [String]? {
        guard let initAccessorNode = symbolNode.children.first(where: { $0.kind == .initAccessor }),
              let variableNode = initAccessorNode.children.first, variableNode.kind == .variable,
              let propertyName = variableNode.identifier,
              let declaredTypeNode = variableNode.children.first(where: { $0.kind == .type })?.materialize()
        else { return nil }
        return initializedFieldNames(ofPropertyNamed: propertyName, declaredTypeNode: declaredTypeNode, fieldNamed: fieldNamed)
    }

    /// The fields the init accessor of the property `propertyName`, of
    /// `declaredTypeNode`, is inferred to initialize: `["_<propertyName>"]`
    /// when the type has that field with the property's type — compared the
    /// way `StoredTypeMatching` compares a declaration with its storage,
    /// `weak` / `unowned` and `sending` set aside — `nil` when nothing
    /// tells. Never lists `accesses:`.
    ///
    /// - Parameter fieldNamed: the type's stored field of a given name, asked
    ///   for `_<propertyName>` only — a caller holding field records
    ///   materializes one type node, not every field's.
    package static func initializedFieldNames(
        ofPropertyNamed propertyName: String,
        declaredTypeNode: Node,
        fieldNamed: (String) -> StoredField?
    ) -> [String]? {
        let backingFieldName = "_" + propertyName
        guard let backingField = fieldNamed(backingFieldName),
              StoredTypeMatching.declaredType(declaredTypeNode, matchesStoredType: StoredTypeMatching.referencedTypeNode(ofStoredType: backingField.typeNode))
        else { return nil }
        return [backingFieldName]
    }
}
