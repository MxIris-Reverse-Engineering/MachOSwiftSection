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

    /// The fields the init accessor of the property `propertyName`, of
    /// `declaredTypeNode`, is inferred to initialize: `["_<propertyName>"]`
    /// when `storedFields` has that field with the property's type, `nil`
    /// when nothing tells. Never lists `accesses:`.
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
              referencedTypeNode(ofStoredType: backingField.typeNode) == declaredTypeNode
        else { return nil }
        return [backingFieldName]
    }

    /// The type a stored property's accessors traffic in: its field type
    /// without the `weak` / `unowned` / `unowned(unsafe)` storage around it,
    /// with the `type` node around it — the shape a member variable's
    /// declared type has. The `@Observable` expansion recovery compares a
    /// tracked property's storage the same way.
    package static func referencedTypeNode(ofStoredType storedTypeNode: Node) -> Node {
        var node = storedTypeNode
        while node.kind == .type, let referenceStorage = node.firstChild,
              referenceStorage.kind == .weak || referenceStorage.kind == .unowned || referenceStorage.kind == .unmanaged,
              let referencedTypeNode = referenceStorage.firstChild {
            node = referencedTypeNode
        }
        return node
    }
}
