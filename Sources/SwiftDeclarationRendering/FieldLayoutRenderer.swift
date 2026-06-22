import Foundation
import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import SwiftLayout
import Utilities
@_spi(Internals) import SwiftInspection

/// Maximum recursion depth that the nested expanded-field-offset walk will
/// descend before bailing out. Mirrors the bound formerly hosted on
/// `SwiftDump.TypedDumper`; kept in `SwiftDeclarationRendering` so both the
/// raw-descriptor dump path and the model-driven interface path share one
/// implementation (single source of truth).
package let nestedFieldOffsetExpansionDepthLimit = 16

/// Shared renderer for the *metadata-derived* field comments of a nominal type —
/// `// Field offset:`, `// Type Layout:`, the expanded nested-field-offset tree,
/// and the enum `Enum Layout` / spare-bit comments. The logic was lifted out of
/// `SwiftDump`'s `StructDumper` / `ClassDumper` / `EnumDumper` so the
/// model-driven `SwiftDeclarationPrinter` can emit the same comments without
/// depending on `SwiftDump` — both now route through this type.
///
/// It deliberately avoids the generic `Metadata` parameter the dumpers carry:
/// the field-offset vector is read from the supplied (already-typed) metadata
/// wrapper, and per-field metatype resolution is parameterised by the type's
/// generic-ness + the optional specialized metadata, so a single concrete type
/// serves struct, class, value, and class-metadata callers alike.
///
/// # Reader specialization
///
/// The actual computation is split by Mach-O reader (this generic type is a thin
/// dispatching facade):
///
/// - **`MachOImage`** (in-process, e.g. RuntimeViewer) — the *runtime* path:
///   materializes metadata in-process (`StructMetadata.createInProcess`,
///   value-witness tables, `RuntimeFunctions.getTypeByMangledNameInContext`).
///   See `FieldLayoutRenderer+MachOImage.swift`.
/// - **`MachOFile`** (offline dump / interface) — the *static* path: computes
///   field offsets / type layouts / the expanded tree / enum layouts from the
///   binary via the `SwiftLayout` engine, never loading the process. Backed by an
///   injected `StaticFieldLayoutProvider`. See `FieldLayoutRenderer+MachOFile.swift`.
///
/// Each public entry point below dispatches to the matching reader-specialized
/// implementation; with no provider (and no in-process metadata) the static path
/// simply emits nothing, exactly as before SwiftLayout was wired in.
package struct FieldLayoutRenderer<MachO: MachOSwiftSectionRepresentableWithCache> {
    package let type: TypeContextWrapper
    package let metadata: MetadataWrapper?
    package let machO: MachO
    package let configuration: DeclarationRenderConfiguration

    /// Whether the *dumped* type is generic. Drives the substitution policy in
    /// the MachOImage path's `resolveFieldMetatype` — generic types substitute
    /// against `metadata`, non-generic types resolve the bare mangled name.
    package let isGeneric: Bool

    /// Precomputed once per type for the MachOFile static path: the field offsets
    /// plus each field type's own layout from `SwiftLayout`. `nil` for the
    /// MachOImage (runtime) path, for enums (no field-offset vector), or when no
    /// static provider was injected.
    package let staticAggregateFieldLayout: AggregateFieldLayout?

    /// - Parameters:
    ///   - providedMetadata: a caller-supplied (typically specialized) metadata
    ///     to read field offsets / drive substitution from.
    ///   - autoResolveAccessorMetadata: when `true` and no metadata is supplied,
    ///     a *non-generic* type's runtime metadata is resolved through its
    ///     accessor function (only succeeds in-process / for MachOImage) — this
    ///     mirrors `TypeContextWrapper.dumper(using:metadata:in:)` and is what
    ///     the model-driven printer wants. When `false` (the raw-descriptor dump
    ///     path), a `nil` metadata stays `nil` so the bare dumper keeps its "no
    ///     metadata context ⇒ no offsets" contract.
    package init(type: TypeContextWrapper, metadata providedMetadata: MetadataWrapper?, machO: MachO, configuration: DeclarationRenderConfiguration, autoResolveAccessorMetadata: Bool = true) {
        self.type = type
        self.machO = machO
        self.configuration = configuration

        let isGeneric: Bool
        switch type {
        case .struct(let structType):
            isGeneric = structType.descriptor.isGeneric
        case .enum(let enumType):
            isGeneric = enumType.descriptor.isGeneric
        case .class(let classType):
            isGeneric = classType.descriptor.isGeneric
        }
        self.isGeneric = isGeneric

        if let providedMetadata {
            self.metadata = providedMetadata
        } else if isGeneric || !autoResolveAccessorMetadata {
            self.metadata = nil
        } else {
            self.metadata = try? FieldLayoutRenderer.resolveAccessorMetadata(for: type, in: machO)
        }

        self.staticAggregateFieldLayout = FieldLayoutRenderer.precomputeStaticAggregateFieldLayout(for: type, machO: machO, configuration: configuration)
    }

    private static func resolveAccessorMetadata(for type: TypeContextWrapper, in machO: MachO) throws -> MetadataWrapper? {
        switch type {
        case .struct(let structType):
            return try structType.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO)
        case .enum(let enumType):
            return try enumType.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO)
        case .class(let classType):
            return try classType.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO)
        }
    }

    /// Computes the static aggregate layout once per type for the MachOFile path.
    /// Only runs for a `MachOFile`, when a layout-bearing flag is on, and when a
    /// provider was injected; enums (which carry no field-offset vector) are
    /// skipped — their layout is computed lazily by the enum path instead.
    private static func precomputeStaticAggregateFieldLayout(for type: TypeContextWrapper, machO: MachO, configuration: DeclarationRenderConfiguration) -> AggregateFieldLayout? {
        guard machO is MachOFile,
              configuration.printFieldOffset || configuration.printTypeLayout || configuration.printExpandedFieldOffsets,
              let provider = configuration.staticFieldLayoutProvider else {
            return nil
        }
        let descriptorWrapper: TypeContextDescriptorWrapper
        switch type {
        case .struct(let structType):
            descriptorWrapper = .struct(structType.descriptor)
        case .class(let classType):
            descriptorWrapper = .class(classType.descriptor)
        case .enum:
            return nil
        }
        return provider.aggregateFieldLayout(forDescriptor: descriptorWrapper)
    }

    /// The dumped type as an `Enum`, or `nil` for struct/class. Shared by both
    /// reader-specialized enum implementations.
    package var enumValue: Enum? {
        if case .enum(let enumType) = type { return enumType }
        return nil
    }

    // MARK: - Reader-dispatched entry points

    /// The resolved field-offset vector for a struct or class, or `nil` when
    /// offsets are disabled, unavailable, or the type is not a stored-field
    /// aggregate. Dispatches to the runtime (MachOImage) or static (MachOFile)
    /// implementation.
    package var fieldOffsets: [Int]? {
        if let imageRenderer = self as? FieldLayoutRenderer<MachOImage> {
            return imageRenderer.runtimeFieldOffsets
        }
        if let fileRenderer = self as? FieldLayoutRenderer<MachOFile> {
            return fileRenderer.staticFieldOffsets
        }
        return nil
    }

    /// Renders the comment block that precedes a single stored field of a struct
    /// or class — the `// Field offset:` line (with end offset), the expanded
    /// nested-offset tree, and the `// Type Layout:` block. `fieldOffsets` is
    /// passed in so the caller computes it once per type.
    @SemanticStringBuilder
    package func storedFieldComments(
        forFieldAtIndex index: Int,
        mangledTypeName: MangledName,
        fieldOffsets: [Int]?
    ) async -> SemanticString {
        if let imageRenderer = self as? FieldLayoutRenderer<MachOImage> {
            await imageRenderer.imageStoredFieldComments(forFieldAtIndex: index, mangledTypeName: mangledTypeName, fieldOffsets: fieldOffsets)
        } else if let fileRenderer = self as? FieldLayoutRenderer<MachOFile> {
            fileRenderer.fileStoredFieldComments(forFieldAtIndex: index, mangledTypeName: mangledTypeName, fieldOffsets: fieldOffsets)
        }
    }

    /// Renders the comment block that precedes a single enum case — the
    /// `// Type Layout:` block for the case's payload, then (when an `enumLayout`
    /// projection is supplied) the per-case `Enum Layout` comment.
    @SemanticStringBuilder
    package func enumCaseComments(
        forCaseAtIndex index: Int,
        mangledTypeName: MangledName,
        enumLayout: EnumLayoutCalculator.LayoutResult?
    ) async -> SemanticString {
        if let imageRenderer = self as? FieldLayoutRenderer<MachOImage> {
            await imageRenderer.imageEnumCaseComments(forCaseAtIndex: index, mangledTypeName: mangledTypeName, enumLayout: enumLayout)
        } else if let fileRenderer = self as? FieldLayoutRenderer<MachOFile> {
            fileRenderer.fileEnumCaseComments(forCaseAtIndex: index, mangledTypeName: mangledTypeName, enumLayout: enumLayout)
        }
    }

    /// Computes the enum's layout strategy projection, or `nil` when layout
    /// printing is disabled, the type is generic, or the enum is neither single-
    /// nor multi-payload.
    package var enumLayout: EnumLayoutCalculator.LayoutResult? {
        get async {
            if let imageRenderer = self as? FieldLayoutRenderer<MachOImage> {
                return await imageRenderer.imageEnumLayout
            }
            if let fileRenderer = self as? FieldLayoutRenderer<MachOFile> {
                return fileRenderer.fileEnumLayout
            }
            return nil
        }
    }

    /// Type-level enum comments emitted once before the case list: the
    /// `Enum Layout` strategy line and the spare-bit summary.
    @SemanticStringBuilder
    package func enumPrefixComments(enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString {
        if let imageRenderer = self as? FieldLayoutRenderer<MachOImage> {
            await imageRenderer.imageEnumPrefixComments(enumLayout: enumLayout)
        } else if let fileRenderer = self as? FieldLayoutRenderer<MachOFile> {
            fileRenderer.fileEnumPrefixComments(enumLayout: enumLayout)
        }
    }
}
