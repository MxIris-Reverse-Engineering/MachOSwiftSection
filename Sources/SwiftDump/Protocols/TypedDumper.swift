import Foundation
import FoundationToolbox
import Semantic
import MachOSwiftSection
import MachOKit
import Demangling
@_spi(Internals) import SwiftInspection

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

    /// Render the bound generic dumped name so that only the *outer* unbound
    /// type carries declaration styling. Type arguments inside `<...>` keep
    /// regular `.name` styling, matching how every other type reference
    /// (e.g. field types) is rendered.
    ///
    /// Why bother: `replacingTypeNameOrOtherToTypeDeclaration()` is a
    /// blanket walk — applied to a whole bound generic node it converts
    /// every nested `.type(_, .name)` into `.type(_, .declaration)`,
    /// including modules, separators, and the inner type names themselves.
    /// For `SwiftUI.HStack<SwiftUI.ColorPickerStyleConfiguration.Label>`
    /// that means the inner `Label` (and its module path) end up tagged as
    /// declarations, which is wrong: only the outer `HStack` is the
    /// declaration. Splitting the rendering keeps the inner argument tree
    /// semantically identical to a regular type reference printed
    /// elsewhere in the dump output.
    ///
    /// Expected `boundNode` shape (produced by
    /// `demangleAsNode(_mangledTypeName(specializedMetatype), isType: true)`):
    /// ```
    /// Type
    /// └── BoundGenericStructure | BoundGenericClass | BoundGenericEnum
    ///     ├── Type            ← unbound name
    ///     └── TypeList
    ///         └── Type, …    ← type arguments
    /// ```
    @SemanticStringBuilder
    package func resolveBoundDumpedTypeName(_ boundNode: Node) async throws -> SemanticString {
        let resolver = configuration.demangleResolver
        if let boundGenericNode = boundNode.firstChild,
           boundGenericNode.kind == .boundGenericStructure
            || boundGenericNode.kind == .boundGenericClass
            || boundGenericNode.kind == .boundGenericEnum,
           boundGenericNode.children.count >= 2 {
            let unboundType = boundGenericNode.children[0]
            let typeList = boundGenericNode.children[1]
            // Outer unbound name → declaration styling, mirroring the
            // unbound `_name` code path.
            try await resolver.resolve(for: unboundType).replacingTypeNameOrOtherToTypeDeclaration()
            Standard("<")
            for (argumentIndex, argumentType) in typeList.children.enumerated() {
                if argumentIndex > 0 {
                    Standard(", ")
                }
                // Inner argument → regular `.name` styling, same as field
                // type references rendered via the demangle resolver.
                try await resolver.resolve(for: argumentType)
            }
            Standard(">")
        } else {
            // Unexpected shape (sugar already collapsed at the top, etc.).
            // Fall back to whole-tree replacement so the head still picks
            // up declaration styling; the inner pieces lose their
            // granularity but it's a graceful degradation rather than a
            // hard failure.
            try await resolver.resolve(for: boundNode).replacingTypeNameOrOtherToTypeDeclaration()
        }
    }
}

extension TypedDumper {
    // MARK: - Previous (pre-substitution) implementation, kept here for
    //         reference while reading the new walker. Deleting it does not
    //         change behavior — the new `expandedFieldOffsets(...)` plus
    //         `walkNestedExpandedFieldOffsets(of:...)` cover every case
    //         this one did and additionally handle specialized generics.
    //
    // ```swift
    // extension TypedDumper {
    //     @SemanticStringBuilder
    //     func expandedFieldOffsets(for mangledTypeName: MangledName, baseOffset: Int, baseIndentation: Int, ancestors: [Bool], in machO: MachOImage?) -> SemanticString {
    //         let metatype: Any.Type?
    //         if let machO {
    //             metatype = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machO)
    //         } else {
    //             metatype = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName)
    //         }
    //         if let metatype,
    //            let metadata = try? Metadata.createInProcess(metatype).asMetadataWrapper().struct,
    //            let descriptor = try? metadata.descriptor().struct, !descriptor.isGeneric,
    //            let nestedFieldOffsets = try? metadata.fieldOffsets(for: descriptor),
    //            let nestedFieldRecords = try? descriptor.fieldDescriptor().records() {
    //             let fieldEntries = Array(zip(nestedFieldRecords, nestedFieldOffsets))
    //             for (fieldIndex, (nestedFieldRecord, nestedRelativeOffset)) in fieldEntries.enumerated() {
    //                 if let fieldName = try? nestedFieldRecord.fieldName() {
    //                     let absoluteOffset = baseOffset + Int(nestedRelativeOffset)
    //                     let isLastField = fieldIndex == fieldEntries.count - 1
    //                     let nestedMangledTypeName = try? nestedFieldRecord.mangledTypeName()
    //                     let typeName = nestedMangledTypeName.flatMap { try? MetadataReader.demangleType(for: $0).printSemantic(using: .default).string } ?? ""
    //                     configuration.expandedFieldOffsetComment(fieldName: fieldName, typeName: typeName, offset: absoluteOffset, baseIndentation: baseIndentation, ancestors: ancestors, isLast: isLastField)
    //
    //                     if let nestedMangledTypeName {
    //                         expandedFieldOffsets(for: nestedMangledTypeName, baseOffset: absoluteOffset, baseIndentation: baseIndentation, ancestors: ancestors + [isLastField], in: nil)
    //                     }
    //                 }
    //             }
    //         }
    //     }
    // }
    // ```
    //
    // Diff against the new implementation, point-by-point:
    //
    //   1. Resolution at the *top* hop ignored `metadataContext` —
    //      `getTypeByMangledNameInContext(mangledTypeName, in: machO)` cannot
    //      substitute generic parameters. For a specialized
    //      `Box<Int>` dumper, a field `let inner: SingleParameterBox<A>`
    //      mangled name still references `A`; resolution returned nil and
    //      the whole expansion was skipped. The new entry calls
    //      `resolveFieldMetatype(for:in:)` first so the dumper's specialized
    //      metadata performs the substitution.
    //
    //   2. The `!descriptor.isGeneric` guard rejected *every* generic
    //      descriptor — including the legitimately specialized
    //      `SingleParameterBox<Int>` we now want to recurse into. The new
    //      walker drops that guard because the metadata it holds is already
    //      a specialized in-process metadata, so `fieldOffsets(for:)` and
    //      friends are well-defined.
    //
    //   3. The recursive call passed `in: nil` (in-process resolution) but
    //      again with no substitution context. Nested fields whose mangled
    //      names referenced *their parent's* generic parameters could not
    //      resolve. The new `walkNestedExpandedFieldOffsets(of:...)` threads
    //      the just-resolved struct metadata as substitution context for
    //      the next hop, mirroring how Swift's runtime walks
    //      generic-arguments arrays through nested specializations.
    //
    //   4. `Metadata.createInProcess(metatype).asMetadataWrapper().struct`
    //      acted as a kind check: it returned nil for non-struct metatypes
    //      (class / enum / builtin / function …) so recursion never
    //      entered them. The new walker performs the same kind check
    //      inside `walkNestedExpandedFieldOffsets(of: Any.Type, ...)` —
    //      its switch dispatches `.struct` / `.enum` / `.optional` into
    //      dedicated walkers and falls through to a `default` no-op for
    //      every other kind, so class / builtin / function metatypes
    //      never reach an unsafe `StructMetadata.createInProcess`-style
    //      cast. An earlier draft of this refactor *lost* that guard by
    //      replacing the chain with a bare
    //      `StructMetadata.createInProcess(metatype)` — the latter reads
    //      16 bytes of the metadata blindly, so a class metatype
    //      produced a misaligned `StructMetadata` whose
    //      `structDescriptor()` then trapped on its internal
    //      `descriptor().struct!` force-unwrap. `try?` does not catch a
    //      forced-unwrap trap, hence the visible `Fatal error: Unexpectedly
    //      found nil` you'd see when dumping a struct with a class field.

    /// Top-level entry: walks the dumper-owned struct's nested struct
    /// fields, emitting `expandedFieldOffsetComment` lines.
    ///
    /// Substitution flows in two phases:
    ///   - Top hop: the field's mangled name comes from the dumper's
    ///     descriptor; specialization (if any) lives in `metadataContext`.
    ///     Use `resolveFieldMetatype` so generic field types like `let x: A`
    ///     resolve to the bound concrete type.
    ///   - Recursive hops: the just-resolved nested struct's metadata is
    ///     itself a specialized in-process metadata, and any further nested
    ///     mangled names that mention *its* generic parameters need to
    ///     substitute against it. `walkNestedExpandedFieldOffsets(of:...)`
    ///     threads that context through the recursion.
    @SemanticStringBuilder
    func expandedFieldOffsets(for mangledTypeName: MangledName, baseOffset: Int, baseIndentation: Int, ancestors: [Bool], in machO: MachOImage?) -> SemanticString {
        let topMetatype: Any.Type?
        if let machO {
            topMetatype = resolveFieldMetatype(for: mangledTypeName, in: machO)
                ?? (try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machO))
        } else {
            topMetatype = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName)
        }
        if let topMetatype {
            walkNestedExpandedFieldOffsets(of: topMetatype, baseOffset: baseOffset, baseIndentation: baseIndentation, ancestors: ancestors)
        }
    }

    /// Dispatches recursive expansion by metadata kind. Structs expose their
    /// stored fields directly; Optional and other enum wrappers expose payload
    /// case records that can themselves carry specialized struct payloads.
    @SemanticStringBuilder
    private func walkNestedExpandedFieldOffsets(of metatype: Any.Type, baseOffset: Int, baseIndentation: Int, ancestors: [Bool], depth: Int = 0) -> SemanticString {
        if depth >= nestedFieldOffsetExpansionDepthLimit {
            emitNestedFieldOffsetDepthLimitWarning(for: metatype)
        } else if let wrapper = try? Metadata.createInProcess(metatype).asMetadataWrapper() {
            switch wrapper {
            case .struct(let metadata):
                walkNestedStructFieldOffsets(of: metadata, baseOffset: baseOffset, baseIndentation: baseIndentation, ancestors: ancestors, depth: depth)
            case .enum(let metadata),
                 .optional(let metadata):
                walkNestedEnumPayloadFieldOffsets(of: metadata, baseOffset: baseOffset, baseIndentation: baseIndentation, ancestors: ancestors, depth: depth)
            default:
                SemanticString()
            }
        }
    }

    /// Plain (non-builder) helper so the result-builder body of
    /// `walkNestedExpandedFieldOffsets` stays valid — the `#log` macro
    /// expands to a `Void`-typed closure invocation, which the builder
    /// accepts via `buildPartialBlock(first: Void)`, but keeping the
    /// diagnostics out of the builder body avoids surprising callers
    /// reading the walker.
    private func emitNestedFieldOffsetDepthLimitWarning(for metatype: Any.Type) {
        #log(.info, "walkNestedExpandedFieldOffsets reached nested field-offset depth limit \(nestedFieldOffsetExpansionDepthLimit, privacy: .public) — truncating expansion of \(metatype, privacy: .public)")
    }

    /// Recursive walk over a nested struct's fields. Every mangled name
    /// read here came from in-process descriptor memory, so substitution
    /// uses the no-`MachOImage` overload of `getTypeByMangledNameInContext`
    /// (the one that treats `mangledTypeName.startOffset` as an absolute
    /// in-process pointer).
    @SemanticStringBuilder
    private func walkNestedStructFieldOffsets(of metadata: StructMetadata, baseOffset: Int, baseIndentation: Int, ancestors: [Bool], depth: Int) -> SemanticString {
        if let descriptor = try? metadata.structDescriptor(),
           let nestedFieldOffsets = try? metadata.fieldOffsets(for: descriptor),
           let nestedFieldRecords = try? descriptor.fieldDescriptor().records() {
            let fieldEntries = Array(zip(nestedFieldRecords, nestedFieldOffsets))
            for (fieldIndex, (nestedFieldRecord, nestedRelativeOffset)) in fieldEntries.enumerated() {
                if let fieldName = try? nestedFieldRecord.fieldName() {
                    let absoluteOffset = baseOffset + Int(nestedRelativeOffset)
                    let isLastField = fieldIndex == fieldEntries.count - 1
                    let nestedMangledTypeName = try? nestedFieldRecord.mangledTypeName()
                    let typeName = nestedTypeName(for: nestedMangledTypeName, parentMetadata: metadata)
                    configuration.expandedFieldOffsetComment(fieldName: fieldName, typeName: typeName, offset: absoluteOffset, baseIndentation: baseIndentation, ancestors: ancestors, isLast: isLastField)

                    if let nestedMangledTypeName,
                       let resolvedMetatype = resolveNestedMetatype(for: nestedMangledTypeName, parentMetadata: metadata) {
                        walkNestedExpandedFieldOffsets(of: resolvedMetatype, baseOffset: absoluteOffset, baseIndentation: baseIndentation, ancestors: ancestors + [isLastField], depth: depth + 1)
                    }
                }
            }
        }
    }

    /// Recursive walk over payload cases for Optional and enum wrappers.
    /// Payloads all begin at the enum payload area, offset 0 relative to the
    /// enum value, so the child offset starts at `baseOffset`.
    @SemanticStringBuilder
    private func walkNestedEnumPayloadFieldOffsets(of metadata: EnumMetadata, baseOffset: Int, baseIndentation: Int, ancestors: [Bool], depth: Int) -> SemanticString {
        if let descriptor = try? metadata.enumDescriptor(),
           descriptor.hasPayloadCases,
           let records = try? descriptor.fieldDescriptor().records() {
            let payloadRecords = Array(records.prefix(descriptor.numberOfPayloadCases))
            for (payloadIndex, payloadRecord) in payloadRecords.enumerated() {
                if let mangledTypeName = try? payloadRecord.mangledTypeName(),
                   !mangledTypeName.isEmpty,
                   let resolvedMetatype = resolveNestedMetatype(for: mangledTypeName, parentMetadata: metadata) {
                    let fieldName = (try? payloadRecord.fieldName()) ?? "payload"
                    let typeName = nestedTypeName(for: mangledTypeName, parentMetadata: metadata)
                    let isLastPayload = payloadIndex == payloadRecords.count - 1
                    configuration.expandedFieldOffsetComment(fieldName: fieldName, typeName: typeName, offset: baseOffset, baseIndentation: baseIndentation, ancestors: ancestors, isLast: isLastPayload)
                    walkNestedExpandedFieldOffsets(of: resolvedMetatype, baseOffset: baseOffset, baseIndentation: baseIndentation, ancestors: ancestors + [isLastPayload], depth: depth + 1)
                }
            }
        }
    }

    /// Resolves a nested field's mangled name to its concrete `Any.Type`,
    /// substituting generic parameters via the parent struct's specialized
    /// metadata. Falls back to the bare resolver for fully-resolved names.
    private func resolveNestedMetatype<M: ValueMetadataProtocol>(for mangledTypeName: MangledName, parentMetadata: M) -> Any.Type? {
        if let substituted = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, specializedFrom: parentMetadata) {
            return substituted
        }
        return try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName)
    }

    /// Renders the human-readable type name used in the
    /// `expandedFieldOffsetComment` line. When substitution succeeds we
    /// print the bound type via `_mangledTypeName` round-trip; otherwise
    /// we fall through to the unbound demangling, which keeps the legacy
    /// behavior for non-generic / unresolvable names.
    private func nestedTypeName<M: ValueMetadataProtocol>(for mangledTypeName: MangledName?, parentMetadata: M) -> String {
        guard let mangledTypeName else { return "" }
        if #available(macOS 11, iOS 14, tvOS 14, watchOS 7, *),
           let resolvedMetatype = resolveNestedMetatype(for: mangledTypeName, parentMetadata: parentMetadata),
           let mangledString = _mangledTypeName(resolvedMetatype),
           let node = try? demangleAsNode(mangledString, isType: true) {
            return node.printSemantic(using: .default).string
        }
        return (try? MetadataReader.demangleType(for: mangledTypeName).printSemantic(using: .default).string) ?? ""
    }
}
