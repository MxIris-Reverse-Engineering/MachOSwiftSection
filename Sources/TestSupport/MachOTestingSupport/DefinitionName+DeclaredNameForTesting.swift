import Demangling
import SwiftDeclaration

extension DefinitionName {
    /// The declaration's own name, read from its node: `Int` for `Swift.Int`,
    /// `Inner` for `Outer.Inner`, `MemberKey` for a type declared in a
    /// function body. What a test compares against when it looks a definition
    /// up by its short name.
    ///
    /// Tests must not use `currentName` for that. It is the display name dump
    /// and interface print in a declaration header, taken as the last
    /// dot-separated component of the printed name — and a function-local
    /// type prints as `MemberKey #1 in Module.f() -> Swift.Int`, so its
    /// `currentName` is the tail of the enclosing function's signature. The
    /// indexer sees such types whenever it indexes the test binary itself: a
    /// local `Hashable` enum in a function returning `Int` read as a second
    /// `Int` candidate, and whichever of the two a `Set` put first decided
    /// what a specialization test specialized (ReviewAdjudications A52).
    ///
    /// A node of a shape not handled here answers the full printed `name`,
    /// so a short-name comparison against it fails rather than matching the
    /// wrong definition.
    package var declaredNameForTesting: String {
        var declarationNode = node
        while declarationNode.kind == .type, let wrappedNode = declarationNode.children.first {
            declarationNode = wrappedNode
        }
        guard let nameNode = declarationNode.children.at(1) else { return name }
        switch nameNode.kind {
        case .identifier:
            return nameNode.text ?? name
        case .localDeclName, .privateDeclName:
            return nameNode.children.last { $0.kind == .identifier }?.text ?? name
        default:
            return name
        }
    }
}
