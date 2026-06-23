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

/// The reader-independent state a `FieldLayoutRenderer` carries, passed to the
/// reader-specialized rendering witnesses (see `FieldLayoutRenderable`).
///
/// It exists so those static witnesses can take the renderer's state *without*
/// naming `FieldLayoutRenderer<Self>` — a `Self` nested in a generic type is not
/// allowed in a protocol requirement satisfied by a non-final class (and
/// `MachOFile` / `MachOImage` are non-final). The reader itself is passed
/// separately as `machO: Self` (a plain parameter position, which *is* allowed).
public struct FieldLayoutRenderState {
    public let type: TypeContextWrapper
    public let metadata: MetadataWrapper?
    public let configuration: DeclarationRenderConfiguration
    public let isGeneric: Bool
    public let staticAggregateFieldLayout: AggregateFieldLayout?

    /// The dumped type as an `Enum`, or `nil` for struct/class.
    public var enumValue: Enum? {
        if case .enum(let enumType) = type { return enumType }
        return nil
    }
}

/// A Mach-O reader that knows how to render a nominal type's metadata-derived
/// field comments — `// Field offset:`, `// Type Layout:`, the expanded
/// nested-offset tree, and the enum `Enum Layout` / spare-bit comments.
///
/// The reader **type** selects the rendering strategy at compile time (no
/// runtime `as?`): `MachOImage` renders from in-process runtime metadata, while
/// `MachOFile` renders statically through the `SwiftLayout` engine. The generic
/// `FieldLayoutRenderer<MachO>` is a thin facade that forwards each entry point
/// to the matching `MachO.render…` witness; the actual logic lives in the
/// internal `RuntimeFieldLayoutBackend` / `StaticFieldLayoutBackend`.
///
/// Only `MachOFile` and `MachOImage` conform (in `SwiftDeclarationRendering`).
/// These witnesses are an implementation detail surfaced only so the type system
/// can pick the backend — callers use `FieldLayoutRenderer`, never them.
public protocol FieldLayoutRenderable: MachOSwiftSectionRepresentableWithCache {
    /// Builds the static (offline) field-layout provider for this reader, or
    /// `nil` for the in-process (`MachOImage`) path. Lets a session root pick a
    /// provider by reader type at compile time, without a runtime cast.
    static func makeStaticFieldLayoutProvider(machO: Self, resolution: StaticLayoutDependencyResolution) -> (any StaticFieldLayoutProvider)?

    /// Precompute (once per type, at renderer init) the static aggregate layout
    /// the offline path reads field offsets / type layouts from. `nil` for the
    /// runtime path or when no static provider was injected.
    static func precomputedStaticAggregateFieldLayout(for type: TypeContextWrapper, machO: Self, configuration: DeclarationRenderConfiguration) -> AggregateFieldLayout?

    static func renderFieldOffsets(_ state: FieldLayoutRenderState, machO: Self) -> [Int]?

    static func renderStoredFieldComments(_ state: FieldLayoutRenderState, machO: Self, forFieldAtIndex index: Int, mangledTypeName: MangledName, fieldOffsets: [Int]?) async -> SemanticString

    static func renderEnumLayout(_ state: FieldLayoutRenderState, machO: Self) async -> EnumLayoutCalculator.LayoutResult?

    static func renderEnumPrefixComments(_ state: FieldLayoutRenderState, machO: Self, enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString

    static func renderEnumCaseComments(_ state: FieldLayoutRenderState, machO: Self, forCaseAtIndex index: Int, mangledTypeName: MangledName, enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString
}

/// Shared renderer for the *metadata-derived* field comments of a nominal type.
/// Lifted out of `SwiftDump`'s `StructDumper` / `ClassDumper` / `EnumDumper` so
/// the model-driven `SwiftDeclarationPrinter` can emit the same comments without
/// depending on `SwiftDump` — both now route through this type.
///
/// This generic value is a thin facade: each entry point forwards to the
/// reader-specialized backend selected at compile time by the `MachO`
/// conformance to `FieldLayoutRenderable`.
package struct FieldLayoutRenderer<MachO: FieldLayoutRenderable> {
    package let type: TypeContextWrapper
    package let metadata: MetadataWrapper?
    package let machO: MachO
    package let configuration: DeclarationRenderConfiguration

    /// Whether the *dumped* type is generic. Drives the substitution policy in
    /// the runtime path's `resolveFieldMetatype` — generic types substitute
    /// against `metadata`, non-generic types resolve the bare mangled name.
    package let isGeneric: Bool

    /// Precomputed once per type for the static (`MachOFile`) path: the field
    /// offsets plus each field type's own layout from `SwiftLayout`. `nil` for
    /// the runtime (`MachOImage`) path, for enums (no field-offset vector), or
    /// when no static provider was injected.
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

        self.staticAggregateFieldLayout = MachO.precomputedStaticAggregateFieldLayout(for: type, machO: machO, configuration: configuration)
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

    /// The dumped type as an `Enum`, or `nil` for struct/class.
    package var enumValue: Enum? {
        if case .enum(let enumType) = type { return enumType }
        return nil
    }

    /// The reader-independent state handed to the rendering witnesses.
    private var renderState: FieldLayoutRenderState {
        FieldLayoutRenderState(type: type, metadata: metadata, configuration: configuration, isGeneric: isGeneric, staticAggregateFieldLayout: staticAggregateFieldLayout)
    }

    // MARK: - Compile-time-dispatched entry points (forward to the reader's backend)

    package var fieldOffsets: [Int]? {
        MachO.renderFieldOffsets(renderState, machO: machO)
    }

    package func storedFieldComments(forFieldAtIndex index: Int, mangledTypeName: MangledName, fieldOffsets: [Int]?) async -> SemanticString {
        await MachO.renderStoredFieldComments(renderState, machO: machO, forFieldAtIndex: index, mangledTypeName: mangledTypeName, fieldOffsets: fieldOffsets)
    }

    package var enumLayout: EnumLayoutCalculator.LayoutResult? {
        get async { await MachO.renderEnumLayout(renderState, machO: machO) }
    }

    package func enumPrefixComments(enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString {
        await MachO.renderEnumPrefixComments(renderState, machO: machO, enumLayout: enumLayout)
    }

    package func enumCaseComments(forCaseAtIndex index: Int, mangledTypeName: MangledName, enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString {
        await MachO.renderEnumCaseComments(renderState, machO: machO, forCaseAtIndex: index, mangledTypeName: mangledTypeName, enumLayout: enumLayout)
    }
}
