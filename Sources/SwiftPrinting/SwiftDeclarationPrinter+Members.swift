import SwiftDeclaration
import SwiftDeclarationRendering
import MachOSwiftSection
import Semantic
import Demangling

/// Per-member stored-field / enum-case rendering primitives, shared by the
/// full-interface printer (`renderModelFields`) and the diffable-interface
/// renderer (which needs each member as a *standalone* `SemanticString` so it can
/// prefix every line with a `+`/`-`/` ` marker). They render straight from the
/// (Mach-O-free, post-index) `SwiftDeclaration` model, so they need no dumper.
///
/// The diff-only header / `deinit` / `associatedtype` entry points live with the
/// diff renderer in `SwiftInterface`, not here.
@_spi(Support)
extension SwiftDeclarationPrinter {
    /// Renders a single stored field (`weak var name: Type`) from its model
    /// `FieldDefinition`. The storage / mutability keywords come from `flags`;
    /// the type comes from `typeNode` printed by `TypeNodePrinter`, which
    /// transparently unwraps `.weak` / `.unowned` / `.unmanaged` reference-
    /// storage wrappers (so the prefix is emitted once, from the keyword, not
    /// twice).
    ///
    /// `substitutedTypeNode` overrides the model's `typeNode` for specialized
    /// definitions: the caller (`renderModelFields`) resolves the field's
    /// mangled name against the specialized runtime metadata so generic
    /// parameters print as their bound arguments (`var value: Int`, not
    /// `var value: A`).
    @SemanticStringBuilder
    public func printField(_ field: FieldDefinition, level: Int, substitutedTypeNode: Node? = nil) async -> SemanticString {
        // A stored field is reported as `.variable` — the event vocabulary has
        // no separate field kind, and a stored property is what it renders as.
        await printCatchedThrowing(
            dispatchingTo: eventDispatcher,
            context: .init(name: field.name, kind: .variable)
        ) {
            try await printThrowingField(field, level: level, substitutedTypeNode: substitutedTypeNode)
        }
    }

    @SemanticStringBuilder
    func printThrowingField(_ field: FieldDefinition, level: Int, substitutedTypeNode: Node? = nil) async throws -> SemanticString {
        if field.isFinal {
            Keyword(.final)
            Space()
        }
        fieldDeclarationKeywords(for: field.flags)
        MemberDeclaration(field.name)
        Standard(":")
        Space()
        try await printThrowingType(fieldTypeNode(for: field, substitutedTypeNode: substitutedTypeNode), isProtocol: false, level: level)
    }

    /// The node the field's declared type renders from. A lazy field prefers
    /// the getter's caller-facing type over the record's `Optional` storage
    /// type (evolution proposal 0006); a specialized definition's substituted
    /// node still wins, because it resolves generic parameters, which the
    /// accessor symbol's node does not. When no getter symbol joined, the
    /// storage type renders unchanged — the honest fallback.
    private func fieldTypeNode(for field: FieldDefinition, substitutedTypeNode: Node?) -> Node {
        if let substitutedTypeNode {
            return substitutedTypeNode
        }
        if field.flags.contains(.isLazy), let accessorTypeNode = field.accessorTypeNode {
            return accessorTypeNode.materialize()
        }
        return field.typeNode.materialize()
    }

    /// Renders a single enum case (`case name`, `case name(Payload)`, or
    /// `indirect case name(Payload)`). Tuple payloads already print their own
    /// parentheses, so they are emitted verbatim; every other payload is wrapped
    /// in `(...)` — mirroring `EnumDumper.fields`.
    ///
    /// Payload presence is decided on the *rendered* payload string (empty or
    /// `()` means no payload), not a guess at the demangled node shape, so an
    /// empty case prints as bare `case name` regardless of how its empty type
    /// name demangled.
    public func printEnumCase(_ field: FieldDefinition, level: Int, substitutedTypeNode: Node? = nil) async -> SemanticString {
        var result = SemanticString {
            if field.flags.contains(.isIndirectCase) {
                Keyword(.indirect)
                Space()
            }
            Keyword(.case)
            Space()
            MemberDeclaration(field.name)
        }

        let payloadTypeNode = substitutedTypeNode ?? field.typeNode.materialize()
        let payload = await printType(payloadTypeNode, isProtocol: false, level: level)
        let payloadText = payload.string
        if !payloadText.isEmpty, payloadText != "()" {
            if payloadTypeNode.firstChild?.isKind(of: .tuple) ?? false {
                result.append(payload)
            } else {
                result.append(SemanticString { Standard("(") })
                result.append(payload)
                result.append(SemanticString { Standard(")") })
            }
        }
        return result
    }

    /// Renders a single enum case for the **main interface path** with the
    /// pre-refactor `EnumDumper.fields` contract, which differs from the
    /// diff renderer's `printEnumCase` in two restored ways:
    ///
    /// - **Payload gating**: payload presence follows the field record's
    ///   mangled type name (the model's `.hasMangledTypeName` flag, captured
    ///   at index time), not the rendered payload text — so a `Void` payload
    ///   prints as `case name()` exactly like the dump path instead of
    ///   collapsing to a bare `case name`.
    /// - **Error propagation**: a payload type that fails to print throws to
    ///   the caller (failing the whole type's rendering) instead of being
    ///   swallowed into an empty line.
    ///
    /// A payload whose node renders as an *empty string* (a `Node.Kind` the
    /// interface printers don't cover) degrades to the bare `case name` — the
    /// parentheses are suppressed rather than emitted around nothing, because
    /// `case name()` is not valid Swift.
    @SemanticStringBuilder
    func printThrowingEnumCase(_ field: FieldDefinition, level: Int, substitutedTypeNode: Node? = nil) async throws -> SemanticString {
        if field.flags.contains(.isIndirectCase) {
            Keyword(.indirect)
            Space()
        }
        Keyword(.case)
        Space()
        MemberDeclaration(field.name)

        if field.flags.contains(.hasMangledTypeName) {
            let payloadTypeNode = substitutedTypeNode ?? field.typeNode.materialize()
            let payload = try await printThrowingType(payloadTypeNode, isProtocol: false, level: level)
            if !payload.string.isEmpty {
                if payloadTypeNode.firstChild?.isKind(of: .tuple) ?? false {
                    payload
                } else {
                    Standard("(")
                    payload
                    Standard(")")
                }
            }
        }
    }

    /// Emits the storage-modifier + mutability-keyword prefix for a stored field
    /// (trailing space included), derived from the model `FieldFlags`. Mirrors
    /// `TypedDumper.fieldDeclarationKeywords` but reads the model flags instead
    /// of inspecting the type node, since indexing already folded the
    /// `weak` / `unowned` / `lazy` signal into `flags`.
    @SemanticStringBuilder
    private func fieldDeclarationKeywords(for flags: FieldFlags) -> SemanticString {
        if flags.contains(.isWeak) {
            Keyword(.weak)
            Space()
            fieldMutabilityKeyword(for: flags)
            Space()
        } else if flags.contains(.isUnownedUnsafe) {
            Keyword(.unowned)
            Standard("(")
            Keyword(.unsafe)
            Standard(")")
            Space()
            fieldMutabilityKeyword(for: flags)
            Space()
        } else if flags.contains(.isUnowned) {
            Keyword(.unowned)
            Space()
            fieldMutabilityKeyword(for: flags)
            Space()
        } else if flags.contains(.isLazy) {
            Keyword(.lazy)
            Space()
            Keyword(.var)
            Space()
        } else {
            fieldMutabilityKeyword(for: flags)
            Space()
        }
    }

    @SemanticStringBuilder
    private func fieldMutabilityKeyword(for flags: FieldFlags) -> SemanticString {
        if flags.contains(.isVariable) {
            Keyword(.var)
        } else {
            Keyword(.let)
        }
    }
}
