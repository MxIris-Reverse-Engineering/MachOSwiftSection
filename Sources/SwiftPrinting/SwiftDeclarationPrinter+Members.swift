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
    @SemanticStringBuilder
    public func printField(_ field: FieldDefinition, level: Int) async -> SemanticString {
        await printCatchedThrowing {
            try await printThrowingField(field, level: level)
        }
    }

    @SemanticStringBuilder
    func printThrowingField(_ field: FieldDefinition, level: Int) async throws -> SemanticString {
        fieldDeclarationKeywords(for: field.flags)
        MemberDeclaration(field.name)
        Standard(":")
        Space()
        try await printThrowingType(field.typeNode.materialize(), isProtocol: false, level: level)
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
    public func printEnumCase(_ field: FieldDefinition, level: Int) async -> SemanticString {
        var result = SemanticString {
            if field.flags.contains(.isIndirectCase) {
                Keyword(.indirect)
                Space()
            }
            Keyword(.case)
            Space()
            MemberDeclaration(field.name)
        }

        let payload = await printType(field.typeNode.materialize(), isProtocol: false, level: level)
        let payloadText = payload.string
        if !payloadText.isEmpty, payloadText != "()" {
            if field.typeNode.children.first?.isKind(of: .tuple) ?? false {
                result.append(payload)
            } else {
                result.append(SemanticString { Standard("(") })
                result.append(payload)
                result.append(SemanticString { Standard(")") })
            }
        }
        return result
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
