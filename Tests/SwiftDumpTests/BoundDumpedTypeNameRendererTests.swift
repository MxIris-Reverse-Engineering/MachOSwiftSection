import Foundation
import Testing
import Demangling
import Semantic
@testable import SwiftDump

// MARK: - Helpers

/// Build `Type → Structure(parent=Module(module), Identifier(name))`.
private func makeStructureTypeNode(module: String, name: String) -> Node {
    let moduleNode = Node.create(kind: .module, text: module)
    let identifierNode = Node.create(kind: .identifier, text: name)
    let structureNode = Node.create(kind: .structure, children: [moduleNode, identifierNode])
    return Node.create(kind: .type, children: [structureNode])
}

/// Build `Type → BoundGenericStructure(unboundType, TypeList(typeArguments))`.
private func makeBoundGenericStructureTypeNode(
    unboundType: Node,
    typeArguments: [Node]
) -> Node {
    let typeListNode = Node.create(kind: .typeList, children: typeArguments)
    let boundGenericNode = Node.create(
        kind: .boundGenericStructure,
        children: [unboundType, typeListNode]
    )
    return Node.create(kind: .type, children: [boundGenericNode])
}

/// Build `Type → Structure(parent=parentTypeNode, Identifier(name))` so the
/// resulting node represents `<parent>.<name>` — used to model a nested
/// non-generic type whose parent already carries its own generic
/// substitution (e.g. `EventListenerPhase<PanEvent>.Value`).
private func makeNestedStructureTypeNode(parent: Node, name: String) -> Node {
    let identifierNode = Node.create(kind: .identifier, text: name)
    let structureNode = Node.create(kind: .structure, children: [parent, identifierNode])
    return Node.create(kind: .type, children: [structureNode])
}

/// Assert that the `SemanticString` contains a component whose string
/// equals `target` and whose semantic type satisfies the predicate. The
/// `description` shows up in the failure message when no match is found.
private func expectComponent(
    _ string: SemanticString,
    matching target: String,
    description: String,
    where predicate: (SemanticType) -> Bool
) {
    let matched = string.components.first { component in
        component.string == target && predicate(component.type)
    }
    #expect(
        matched != nil,
        "expected \(description) for substring \"\(target)\"; got components: \(string.components.map { "\($0.string)→\($0.type)" })"
    )
}

// MARK: - Tests

/// Regression coverage for `BoundDumpedTypeNameRenderer.render(_:using:)`.
///
/// The function powers the `name` of every specialized dumper
/// (`StructDumper.name` / `EnumDumper.name` / `ClassDumper.name`) when
/// the in-process specialized metatype is available. It must split the
/// declaration head (rendered as `.type(_, .declaration)`) from the
/// type-argument subtree (rendered as `.type(_, .name)` — i.e. a
/// jump-to-type reference) — including the case where the head is a
/// nested non-generic type whose parent chain contains the bound
/// generic.
///
/// Before the recursive walk, the nested case fell through to a blanket
/// `replacingTypeNameOrOtherToTypeDeclaration()` call that rewrote every
/// inner `.type(_, .name)` and `.other` token into a declaration, losing
/// the inner type's module/reference semantics (e.g.
/// `EventListenerPhase<SwiftUI.PanEvent>.Value` had `SwiftUI` and
/// `PanEvent` tagged as declarations, breaking jump-to-type).
@Suite("BoundDumpedTypeNameRenderer preserves inner type-argument references")
struct BoundDumpedTypeNameRendererTests {
    private let resolver = DemangleResolver.options(.default)

    // MARK: - Case 1: top-level bound generic, simple unbound head.

    /// `TestModule.Box<TestModule.Int>`:
    /// - Outer `Box` → `.type(.struct, .declaration)`
    /// - Inner `Int` → `.type(.struct, .name)` (reference)
    @Test("simple bound generic: head is declaration, arg is reference")
    func simpleBoundGeneric() async throws {
        let boxUnbound = makeStructureTypeNode(module: "TestModule", name: "Box")
        let intArgument = makeStructureTypeNode(module: "TestModule", name: "Int")
        let node = makeBoundGenericStructureTypeNode(
            unboundType: boxUnbound,
            typeArguments: [intArgument]
        )

        let rendered = try await BoundDumpedTypeNameRenderer.render(node, using: resolver)

        // Head: `Box` ends up as a struct declaration; `<…>` brackets are
        // plain `.standard` content.
        expectComponent(rendered, matching: "Box",
                        description: "outer struct head as declaration") {
            $0 == .type(.struct, .declaration)
        }
        // The bracket characters land in `.standard` slots — sanity-check
        // that the spine wrap is emitted at all.
        expectComponent(rendered, matching: "<",
                        description: "opening generic bracket") {
            $0 == .standard
        }
        // Inner argument `Int` retains a reference role. This is the
        // *whole point* of the function — without it, the user can't
        // navigate from the bound name back to the argument type.
        expectComponent(rendered, matching: "Int",
                        description: "type-argument as reference (jump-to-type)") {
            $0 == .type(.struct, .name)
        }
        // Inner argument's module stays on the `.other` slot used for
        // module references — *not* promoted to `.declaration`.
        expectComponent(rendered, matching: "TestModule",
                        description: "argument's module reference (.other)") {
            $0 == .other
        }
    }

    // MARK: - Case 2: nested non-generic type with bound-generic parent.

    /// `SwiftUI.EventListenerPhase<SwiftUI.PanEvent>.Value`:
    ///   - Outer `EventListenerPhase` → `.type(.struct, .declaration)`
    ///   - Trailing `Value` → `.type(.struct, .declaration)`
    ///   - Inner `PanEvent` → `.type(.struct, .name)` (reference)
    ///   - Inner `SwiftUI` (module of the argument) → `.other`
    ///     (reference), **not** promoted to declaration.
    ///
    /// Pre-fix behavior tagged both `PanEvent` and the `SwiftUI` next to
    /// it as declarations because the outer Structure shape fell into
    /// the blanket-replacement fallback.
    @Test("nested non-generic with bound-generic parent: inner arg stays a reference")
    func nestedNonGenericWithBoundGenericParent() async throws {
        // Build the shape the demangler produces for
        // `EventListenerPhase<PanEvent>.Value` after `_mangledTypeName +
        // demangleAsNode` on the specialized in-process metatype:
        //
        //   Type
        //   └── Structure                                ← outer "Value"
        //       ├── Type
        //       │   └── BoundGenericStructure            ← Phase<PanEvent>
        //       │       ├── Type → Structure (Phase)
        //       │       └── TypeList
        //       │           └── Type → Structure (PanEvent in SwiftUI)
        //       └── Identifier("Value")
        let phaseUnbound = makeStructureTypeNode(module: "SwiftUI", name: "EventListenerPhase")
        let panEventArgument = makeStructureTypeNode(module: "SwiftUI", name: "PanEvent")
        let boundParent = makeBoundGenericStructureTypeNode(
            unboundType: phaseUnbound,
            typeArguments: [panEventArgument]
        )
        let node = makeNestedStructureTypeNode(parent: boundParent, name: "Value")

        let rendered = try await BoundDumpedTypeNameRenderer.render(node, using: resolver)

        // The spine identifiers ("EventListenerPhase" and "Value") are
        // declarations — the whole `Phase<PanEvent>.Value` name is being
        // declared at this site.
        expectComponent(rendered, matching: "EventListenerPhase",
                        description: "spine head as declaration") {
            $0 == .type(.struct, .declaration)
        }
        expectComponent(rendered, matching: "Value",
                        description: "trailing identifier as declaration") {
            $0 == .type(.struct, .declaration)
        }

        // The argument `PanEvent` and its `SwiftUI` module must keep
        // reference roles so the UI can wire jump-to-type / module
        // navigation off them. This is the regression the fix addresses.
        expectComponent(rendered, matching: "PanEvent",
                        description: "inner type-argument as reference") {
            $0 == .type(.struct, .name)
        }

        // The argument's `SwiftUI` module must surface at least once as
        // `.other` (module reference), so the UI can wire module
        // navigation off it. Note: another `SwiftUI` component also
        // appears earlier as the spine's parent module — that one
        // *does* legitimately go through declaration promotion since
        // it's part of the qualified head being declared. The
        // pre-fix symptom was the *argument's* `SwiftUI` losing its
        // `.other` role, which this expectation pins.
        expectComponent(rendered, matching: "SwiftUI",
                        description: "argument's module reference (.other)") {
            $0 == .other
        }
    }

    // MARK: - Case 3: blanket-replacement fallback shape stays correct.

    /// A plain non-generic type `TestModule.Box` (no bound generics
    /// anywhere) falls into Case 2's recursion which itself falls back
    /// to blanket replacement on the module-only parent. The whole head
    /// should render as a declaration, matching the pre-fix
    /// `_name`-without-`boundDumpedTypeNode` path.
    @Test("non-generic plain type renders entirely as declaration")
    func plainNonGenericHead() async throws {
        let node = makeStructureTypeNode(module: "TestModule", name: "Box")

        let rendered = try await BoundDumpedTypeNameRenderer.render(node, using: resolver)

        expectComponent(rendered, matching: "Box",
                        description: "head identifier as declaration") {
            $0 == .type(.struct, .declaration)
        }
        // The module portion gets blanket-promoted to a declaration too
        // because there's nothing inside that needed reference styling —
        // matches the existing `replacingTypeNameOrOtherToTypeDeclaration`
        // shape applied to a plain qualified name in `_name`.
        expectComponent(rendered, matching: "TestModule",
                        description: "module on the spine as declaration") {
            $0 == .type(.other, .declaration)
        }
    }
}
