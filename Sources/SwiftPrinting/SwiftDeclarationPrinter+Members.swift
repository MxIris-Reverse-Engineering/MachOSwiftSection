import SwiftDeclaration
import SwiftAttributeInference
import SwiftDump
import MachOSwiftSection
import Semantic
import Demangling

/// Per-member rendering primitives used by the diffable-interface renderer.
///
/// `printTypeDefinition` renders a whole type by composing several sources, and
/// its stored fields / enum cases come from `SwiftDump`'s dumpers as one blob.
/// The diff renderer needs every member as a *standalone* `SemanticString` so it
/// can prefix each member's line(s) with a `+`/`-`/` ` marker. The symbol-backed
/// members already have per-member entry points (`printVariable` / `printFunction`
/// / `printSubscript`); these add the missing ones — stored fields, enum cases,
/// `deinit`, and associated types — rendered straight from the (Mach-O-free,
/// post-index) `SwiftDeclaration` model so they need no dumper.
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
        try await printThrowingType(field.typeNode, isProtocol: false, level: level)
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

        let payload = await printType(field.typeNode, isProtocol: false, level: level)
        let payloadText = payload.string
        if !payloadText.isEmpty, payloadText != "()" {
            if field.typeNode.firstChild?.isKind(of: .tuple) ?? false {
                result.append(payload)
            } else {
                result.append(SemanticString { Standard("(") })
                result.append(payload)
                result.append(SemanticString { Standard(")") })
            }
        }
        return result
    }

    /// Renders the `deinit` keyword line.
    @SemanticStringBuilder
    public func printDeinit() -> SemanticString {
        Keyword(.deinit)
    }

    /// Renders a single protocol associated-type requirement
    /// (`associatedtype Name`).
    @SemanticStringBuilder
    public func printAssociatedType(_ name: String) -> SemanticString {
        Keyword(.associatedtype)
        Space()
        MemberDeclaration(name)
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

// MARK: - Declaration headers (header line only, no `{` / body)

/// Header-only renderers for the diff renderer, which composes a type's lines
/// itself (so it can interleave `+`/`-` members) instead of going through
/// `printTypeDefinition`. Each returns just the declaration header — attributes
/// + the `struct Foo<A> : Bar` line — with no opening brace, body, or trailing
/// newline. They intentionally mirror the header portion of the matching
/// `print*Definition` method; keep them in sync.
@_spi(Support)
extension SwiftDeclarationPrinter {
    @SemanticStringBuilder
    public func printTypeHeader(_ typeDefinition: TypeDefinition, level: Int, displayParentName: Bool = false) async throws -> SemanticString {
        if !typeDefinition.isIndexed {
            try await typeDefinition.index(in: machO)
        }

        let typeAttributeInferrer = TypeAttributeInferrer()
        typeDefinition.attributes = typeAttributeInferrer.infer(for: typeDefinition)

        let dumper = typeDefinition.type.dumper(
            using: .init(demangleResolver: typeDemangleResolver, indentation: level, displayParentName: displayParentName),
            metadata: typeDefinition.metadata,
            in: machO
        )

        // Attributes each on their own line; the diff renderer adds indentation
        // when it marks the lines, so none is emitted here.
        for attribute in typeDefinition.attributes {
            Keyword(attribute.keyword)
            BreakLine()
        }

        try await dumper.declaration
    }

    @SemanticStringBuilder
    public func printProtocolHeader(_ protocolDefinition: ProtocolDefinition, level: Int, displayParentName: Bool = false) async throws -> SemanticString {
        if !protocolDefinition.isIndexed {
            try await protocolDefinition.index(in: machO)
        }

        let dumper = ProtocolDumper(
            protocolDefinition.protocol,
            using: .init(demangleResolver: typeDemangleResolver, indentation: level, displayParentName: displayParentName),
            in: machO
        )

        try await dumper.declaration
    }
}
