import Foundation
import FoundationToolbox
import Semantic
import MachOSwiftSection
import MachOKit
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

/// Maximum recursion depth that `walkNestedExpandedFieldOffsets` (and its
/// per-kind helpers) will descend before bailing out. Real Swift type
/// nesting rarely exceeds 3-4 layers in practice, so 16 is a deliberately
/// generous bound that catches runaway recursion (pathological
/// self-referencing types, mutually-recursive containers) without ever
/// clipping legitimate nesting. Hitting it is a diagnostic event, not a
/// normal outcome: the `@Loggable`-generated `logger` on `TypedDumper`
/// (subsystem `com.machoswiftsection.swift-dump`, category
/// `TypedDumper.nestedFieldOffsetExpansion`) carries the `#log` warning
/// emitted when the guard trips.
///
/// `package`-visible so the regression test that pins this invariant can
/// read it without `@testable`.
package let nestedFieldOffsetExpansionDepthLimit = 16

@Loggable(.package, subsystem: "com.machoswiftsection.swift-dump", category: "TypedDumper.nestedFieldOffsetExpansion")
package protocol TypedDumper: NamedDumper where Dumped: TopLevelType, Dumped.Descriptor: TypeContextDescriptorProtocol {
    associatedtype Metadata: MetadataProtocol

    var metadataContext: DumperMetadataContext<Metadata>? { get }

    @SemanticStringBuilder var fields: SemanticString { get async throws }

    init(_ dumped: Dumped, metadataContext: DumperMetadataContext<Metadata>?, using configuration: DumperConfiguration, in machO: MachO)

    /// Resolves a field's mangled type name to a concrete `Any.Type` using
    /// the dumper's specialized metadata, when applicable.
    ///
    /// This lives as a protocol requirement (rather than only as a
    /// constrained extension) so the dispatch is dynamic — `fieldDemangled\
    /// TypeNode(for:)` calls it through `Self` and the constrained variants
    /// in the extensions below win for the matching `Metadata` type. The
    /// default implementation returns `nil` so dumpers without a matching
    /// constraint just skip substitution.
    func resolveFieldMetatype(for mangledTypeName: MangledName, in machOImage: MachOImage) -> Any.Type?

    /// Returns the in-process `Any.Type` of the *dumped* type when the
    /// dumper is operating on a specialized in-process metadata. Used to
    /// drive `boundDumpedTypeNode()`, which substitutes the dumped type's
    /// own generic parameters in `name` / `declaration` rendering.
    ///
    /// Default returns nil; the constrained extensions return the specialized
    /// metatype for value- and class-metadata dumpers.
    func boundDumpedMetatype() -> Any.Type?
}

// Default implementations: no substitution. Specialized types pick up the
// constrained variants further below.
extension TypedDumper {
    package func resolveFieldMetatype(for mangledTypeName: MangledName, in machOImage: MachOImage) -> Any.Type? {
        nil
    }

    package func boundDumpedMetatype() -> Any.Type? {
        nil
    }
}

extension TypedDumper {
    /// Emits `var` or `let` based on the field record's mutability flag.
    @SemanticStringBuilder
    package func fieldMutabilityKeyword(for fieldRecord: FieldRecord) -> SemanticString {
        if fieldRecord.flags.contains(.isVariadic) {
            Keyword(.var)
        } else {
            Keyword(.let)
        }
    }

    /// Emits the full storage-modifier + mutability-keyword prefix for a stored field,
    /// including the trailing space, ready for the field name to follow.
    ///
    /// Handles `weak`, `unowned`, `unowned(unsafe)`, and `lazy`, then delegates to
    /// `fieldMutabilityKeyword(for:)` for the `var`/`let` decision. Swift 5.9+
    /// permits `weak let` / `unowned let`, so the storage modifier composes with
    /// either mutability keyword. `lazy` is the single exception and always pairs
    /// with `var`.
    @SemanticStringBuilder
    package func fieldDeclarationKeywords(
        for fieldRecord: FieldRecord,
        typeNode: Node,
        fieldName: String
    ) -> SemanticString {
        if typeNode.hasWeakNode {
            Keyword(.weak)
            Space()
            fieldMutabilityKeyword(for: fieldRecord)
            Space()
        } else if typeNode.hasUnmanagedNode {
            Keyword(.unowned)
            Standard("(")
            Keyword(.unsafe)
            Standard(")")
            Space()
            fieldMutabilityKeyword(for: fieldRecord)
            Space()
        } else if typeNode.hasUnownedNode {
            Keyword(.unowned)
            Space()
            fieldMutabilityKeyword(for: fieldRecord)
            Space()
        } else if fieldName.hasLazyPrefix {
            Keyword(.lazy)
            Space()
            Keyword(.var)
            Space()
        } else {
            fieldMutabilityKeyword(for: fieldRecord)
            Space()
        }
    }
}

extension TypedDumper {
    package var typeLayout: TypeLayout? {
        get throws {
            try dumped.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).valueWitnessTable(in: machO).typeLayout
        }
    }
}

// MARK: - Field metatype resolution

extension TypedDumper where Metadata: ValueMetadataProtocol {
    /// Constrained override of the protocol requirement: resolves a field's
    /// mangled type name to its concrete `Any.Type` using a specialized
    /// in-process value-type metadata when present.
    ///
    /// For non-generic top-level types the bare runtime entry is enough.
    /// For generic top-level types the field's mangled name can reference
    /// the enclosing generic parameters (e.g. depth/index pairs); we
    /// substitute via the specialized in-process metadata when the dumper
    /// has one. Returns `nil` when the runtime cannot resolve the name —
    /// e.g. a generic field on a generic type with no specialized metadata
    /// context to substitute against.
    package func resolveFieldMetatype(for mangledTypeName: MangledName, in machOImage: MachOImage) -> Any.Type? {
        if !dumped.flags.isGeneric {
            return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machOImage)
        }
        guard let specializedMetadata = metadataContext?.metadata else { return nil }
        return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, specializedFrom: specializedMetadata, in: machOImage)
    }

    package func boundDumpedMetatype() -> Any.Type? {
        guard dumped.flags.isGeneric, let metadata = metadataContext?.metadata else { return nil }
        guard let metadataPointer = try? metadata.asPointer else { return nil }
        // Specialized in-process metadata pointers and `Any.Type` are
        // representationally identical — bitcasting recovers the metatype
        // we'd get from `Foo<Int>.self`.
        return unsafeBitCast(metadataPointer, to: Any.Type.self)
    }
}

extension TypedDumper where Metadata == ClassMetadataObjCInterop {
    /// Class-metadata variant of the protocol requirement. Mirrors the
    /// value-type version but routes through the class-specialized
    /// runtime overload, which handles the resilient/non-resilient
    /// generic-argument-offset branching internally.
    package func resolveFieldMetatype(for mangledTypeName: MangledName, in machOImage: MachOImage) -> Any.Type? {
        if !dumped.flags.isGeneric {
            return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machOImage)
        }
        guard let specializedMetadata = metadataContext?.metadata else { return nil }
        return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, specializedFrom: specializedMetadata, in: machOImage)
    }

    package func boundDumpedMetatype() -> Any.Type? {
        guard dumped.flags.isGeneric, let metadata = metadataContext?.metadata else { return nil }
        guard let metadataPointer = try? metadata.asPointer else { return nil }
        return unsafeBitCast(metadataPointer, to: Any.Type.self)
    }
}

// MARK: - Field demangled-type-node resolution

extension TypedDumper {
    /// Returns a demangled `Node` describing a field's type, with generic
    /// parameters substituted by their concrete arguments when the dumper
    /// is operating on a specialized in-process metadata.
    ///
    /// Strategy:
    ///   - Non-generic dumps fall through to `MetadataReader.demangleType`
    ///     against the binary's raw bytes (the existing path; the result
    ///     contains no generic-param references).
    ///   - Generic dumps with a `metadataContext` use the resolved
    ///     specialized `Any.Type`, fetch its own mangled name via Swift's
    ///     `_mangledTypeName` SPI, and demangle that string. The resulting
    ///     node tree mentions the substituted concrete types instead of
    ///     `dependentGenericParamType` placeholders.
    ///   - Generic dumps without a `metadataContext` fall back to the raw
    ///     bytes (we have nothing to substitute against), which keeps the
    ///     unbound representation.
    package func fieldDemangledTypeNode(for mangledTypeName: MangledName) throws -> Node {
        if let substituted = substitutedFieldNode(for: mangledTypeName) {
            return substituted
        }
        return try MetadataReader.demangleType(for: mangledTypeName, in: machO)
    }

    /// Splits the SwiftStdlib 5.3 availability gate (required for
    /// `_mangledTypeName`) out of the main control flow. Returns `nil` when
    /// the dumper isn't operating on a specialized metadata, when the
    /// runtime resolver fails, when the host runtime predates the
    /// `_mangledTypeName` SPI, or when `demangleAsNode` cannot parse the
    /// resulting string.
    private func substitutedFieldNode(for mangledTypeName: MangledName) -> Node? {
        guard dumped.flags.isGeneric,
              let machOImage = machO.asMachOImage,
              let resolvedMetatype = resolveFieldMetatype(for: mangledTypeName, in: machOImage)
        else {
            return nil
        }
        return demangledNode(forMetatype: resolvedMetatype)
    }

    /// Returns a demangled `Node` for the *dumped* type itself, with its
    /// generic parameters bound to the concrete arguments that came from
    /// the specialized in-process metadata. Returns `nil` when the dumper
    /// isn't operating on a specialized metadata (so callers can fall back
    /// to the existing unbound name path).
    package func boundDumpedTypeNode() -> Node? {
        guard let metatype = boundDumpedMetatype() else { return nil }
        return demangledNode(forMetatype: metatype)
    }

    /// Shared wrapper around `_mangledTypeName` + `demangleAsNode` so the
    /// SwiftStdlib-availability + nil-handling lives in exactly one spot
    /// for both field-type and dumped-type substitution.
    private func demangledNode(forMetatype metatype: Any.Type) -> Node? {
        // `_mangledTypeName` is `SwiftStdlib 5.3` — translates to macOS 11 /
        // iOS 14 / tvOS 14 / watchOS 7. Fall back to nil on older runtimes
        // so callers stay on the unbound representation.
        guard #available(macOS 11, iOS 14, tvOS 14, watchOS 7, *) else { return nil }
        guard let resolvedMangledString = _mangledTypeName(metatype) else { return nil }
        return try? demangleAsNode(resolvedMangledString, isType: true)
    }

    /// Render the bound generic dumped name so that the type's qualified
    /// "spine" (everything that is part of the declaration's own name)
    /// carries declaration styling, while type arguments inside `<...>`
    /// keep regular `.name` styling — matching how every other type
    /// reference (field types, parameter types, …) is rendered in the
    /// dump.
    ///
    /// Why bother: `replacingTypeNameOrOtherToTypeDeclaration()` is a
    /// blanket walk — applied to a whole bound generic node it converts
    /// every nested `.type(_, .name)` into `.type(_, .declaration)`,
    /// including modules, separators, and the inner type names
    /// themselves. For `SwiftUI.HStack<SwiftUI.ColorPickerStyleConfiguration.Label>`
    /// that means the inner `Label` (and its module path) end up tagged
    /// as declarations, which is wrong: only the outer `HStack` is the
    /// declaration. The recursive walk below keeps every typeList
    /// argument subtree on the normal reference path while only the
    /// spine identifiers pick up declaration styling.
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
    @SemanticStringBuilder
    package func resolveBoundDumpedTypeName(_ boundNode: Node) async throws -> SemanticString {
        try await BoundDumpedTypeNameRenderer.render(boundNode, using: configuration.demangleResolver)
    }
}

/// Static home of the recursive walk powering `resolveBoundDumpedTypeName`.
///
/// Lifted off `TypedDumper` because the algorithm only depends on a
/// `DemangleResolver` — no dumper-specific state — so the test suite
/// can exercise it directly with synthetic Node trees without standing
/// up a real `Metadata`/`Dumped`/`MachO` triple. A case-less enum (vs.
/// a free function) keeps the namespacing tight: callers must say
/// `BoundDumpedTypeNameRenderer.render(...)`, which is the same shape
/// every other dumper helper here uses.
///
/// Doc & shape contract live on `TypedDumper.resolveBoundDumpedTypeName(_:)`
/// above; keep this implementation behaviorally identical to its prose
/// description.
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

