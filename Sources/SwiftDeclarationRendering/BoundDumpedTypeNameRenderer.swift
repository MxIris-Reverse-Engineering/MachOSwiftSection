import Semantic
import Demangling

/// Static home of the recursive walk that renders a *bound* generic type name
/// (`Foo<Int>`, `Phase<PanEvent>.Value`) so that the type's qualified "spine"
/// (everything that is part of the declaration's own name) carries declaration
/// styling, while type arguments inside `<...>` keep regular `.name` styling —
/// matching how every other type reference (field types, parameter types, …)
/// is rendered.
///
/// Why bother: `replacingTypeNameOrOtherToTypeDeclaration()` is a blanket
/// walk — applied to a whole bound generic node it converts every nested
/// `.type(_, .name)` into `.type(_, .declaration)`, including modules,
/// separators, and the inner type names themselves. For
/// `SwiftUI.HStack<SwiftUI.ColorPickerStyleConfiguration.Label>` that means
/// the inner `Label` (and its module path) end up tagged as declarations,
/// which is wrong: only the outer `HStack` is the declaration. The recursive
/// walk below keeps every typeList argument subtree on the normal reference
/// path while only the spine identifiers pick up declaration styling.
///
/// Three Node shapes are handled (each may recurse into the others):
///
///   1. Top-level bound generic — `Foo<X>`:
///      ```
///      Type
///      └── BoundGenericStructure | BoundGenericClass | BoundGenericEnum
///          ├── Type           ← unbound head, may be nested
///          └── TypeList
///              └── Type, …    ← type-argument subtrees
///      ```
///   2. Nested non-generic type whose parent chain has bound generics —
///      `Foo<X>.Bar` (the symptom that motivated the recursive walk:
///      a specialized `EventListenerPhase<PanEvent>.Value` was losing
///      the inner `SwiftUI.PanEvent` reference styling):
///      ```
///      Type
///      └── Structure | Class | Enum
///          ├── Type
///          │   └── BoundGenericStructure(Foo, TypeList(X))
///          └── Identifier("Bar")
///      ```
///   3. Anything else (Module-wrapped contexts, builtins, type
///      aliases) — falls through to
///      `replacingTypeNameOrOtherToTypeDeclaration()`, which is
///      correct because nothing inside has typeList args worth
///      preserving as references at this position.
///
/// Recursive descent through (1)+(2) handles arbitrary nesting like
/// `Outer<X>.Mid<Y>.Inner.Leaf<Z>` — every spine identifier renders
/// as a declaration, every `X`/`Y`/`Z` renders as a reference.
///
/// The algorithm only depends on a `DemangleResolver` — no dumper-specific
/// state — so the test suite can exercise it directly with synthetic Node
/// trees without standing up a real `Metadata`/`Dumped`/`MachO` triple.
/// Historically it lived in `SwiftDump` next to `TypedDumper`
/// (`resolveBoundDumpedTypeName` still forwards here); it moved down into
/// `SwiftDeclarationRendering` so the model-driven interface printer
/// (`SwiftPrinting`, which must not depend on `SwiftDump`) can render bound
/// specialized headers with the exact same walk. A case-less enum (vs. a free
/// function) keeps the namespacing tight: callers must say
/// `BoundDumpedTypeNameRenderer.render(...)`.
package enum BoundDumpedTypeNameRenderer {
    @SemanticStringBuilder
    package static func render(
        _ boundNode: Node,
        using resolver: DemangleResolver
    ) async throws -> SemanticString {
        // Unwrap the outer `.type` wrapper so the switch can match the
        // actual nominal kind underneath. Bare nodes (no `.type` wrap)
        // are passed through unchanged for recursive calls that already
        // descended past their wrapper.
        let inner: Node
        if boundNode.kind == .type, let firstChild = boundNode.firstChild {
            inner = firstChild
        } else {
            inner = boundNode
        }

        // Result-builder context: no `guard … return` early-exits — they
        // disable the builder for the rest of the function. Branch with
        // if/else (which the builder lowers via `buildEither`) instead.
        switch inner.kind {
        case .boundGenericStructure, .boundGenericClass, .boundGenericEnum:
            if inner.children.count >= 2 {
                let unboundType = inner.children[0]
                let typeList = inner.children[1]
                // Recurse on the unbound head: it may itself be a
                // nested Structure whose parent contains another
                // BoundGeneric whose typeList args also need to stay
                // references (e.g. `Phase<X>.Value<Y>`).
                try await render(unboundType, using: resolver)
                Standard("<")
                for (argumentIndex, argumentType) in typeList.children.enumerated() {
                    if argumentIndex > 0 {
                        Standard(", ")
                    }
                    // Argument subtree → plain reference styling, same
                    // as a field type reference rendered elsewhere in
                    // the dump.
                    try await resolver.resolve(for: argumentType)
                }
                Standard(">")
            } else {
                // Malformed bound-generic: fall back to blanket
                // replacement so the head still picks up declaration
                // styling.
                try await resolver.resolve(for: boundNode).replacingTypeNameOrOtherToTypeDeclaration()
            }

        case .structure, .class, .enum:
            // The bug fix: when the outer node is a non-generic nested
            // Structure/Class/Enum whose parent chain contains a
            // BoundGeneric (e.g. `Phase<PanEvent>.Value`), recurse into
            // the parent so its typeList args stay as references, then
            // emit the trailing identifier as a declaration.
            if inner.children.count >= 2, let identifierText = inner.children[1].text {
                let parent = inner.children[0]
                try await render(parent, using: resolver)
                Standard(".")
                TypeDeclaration(kind: nominalTypeKind(of: inner.kind), identifierText)
            } else {
                // Missing identifier text (privateDeclName-only nodes,
                // etc.) — fall back to blanket replacement so the head
                // still picks up declaration styling; inner pieces lose
                // granularity but it's a graceful degradation.
                try await resolver.resolve(for: boundNode).replacingTypeNameOrOtherToTypeDeclaration()
            }

        default:
            // Module wrappers, builtins, type aliases not covered
            // above. No typeList args inside → blanket replacement is
            // safe and matches the existing `_name` declaration
            // styling exactly.
            try await resolver.resolve(for: boundNode).replacingTypeNameOrOtherToTypeDeclaration()
        }
    }

    /// Map a demangler nominal `Node.Kind` to its corresponding semantic
    /// `TypeKind`. Defaults to `.other` for kinds outside the
    /// structure/class/enum trio that `render` actually dispatches to —
    /// the default is reachable only via a programming error (caller
    /// passed a non-nominal `Node.Kind`).
    private static func nominalTypeKind(of kind: Node.Kind) -> SemanticType.TypeKind {
        switch kind {
        case .structure: return .struct
        case .class: return .class
        case .enum: return .enum
        default: return .other
        }
    }
}
