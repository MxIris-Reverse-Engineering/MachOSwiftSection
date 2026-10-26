import Semantic
import MachOKitExtensions
import MachOSwiftSection
import SwiftLayout
@_spi(Internals) import SwiftInspection

/// A wrapper renders its field-layout comments the way the reader it wraps
/// does: a host's `MachOReaderWrapper` declares `FieldLayoutRenderable` with an
/// empty body and renders through `Base`'s backend — from live metadata when it
/// wraps a `MachOImage`, statically when it wraps a `MachOFile`.
extension FieldLayoutRenderable where Self: MachOReaderWrapper, Base: FieldLayoutRenderable {
    public static func makeStaticFieldLayoutProvider(machO: Self, resolution: StaticLayoutDependencyResolution) -> (any StaticFieldLayoutProvider)? {
        Base.makeStaticFieldLayoutProvider(machO: machO.base, resolution: resolution)
    }

    public static func precomputedStaticAggregateFieldLayout(for type: TypeContextWrapper, genericArgumentBinding: GenericArgumentBinding?, machO: Self, configuration: DeclarationRenderConfiguration) -> AggregateFieldLayout? {
        Base.precomputedStaticAggregateFieldLayout(for: type, genericArgumentBinding: genericArgumentBinding, machO: machO.base, configuration: configuration)
    }

    public static func renderFieldOffsets(_ state: FieldLayoutRenderState, machO: Self) -> [Int]? {
        Base.renderFieldOffsets(state, machO: machO.base)
    }

    public static func renderStoredFieldComments(_ state: FieldLayoutRenderState, machO: Self, forFieldAtIndex index: Int, mangledTypeName: MangledName, fieldOffsets: [Int]?) async throws -> SemanticString {
        try await Base.renderStoredFieldComments(state, machO: machO.base, forFieldAtIndex: index, mangledTypeName: mangledTypeName, fieldOffsets: fieldOffsets)
    }

    public static func renderEnumLayout(_ state: FieldLayoutRenderState, machO: Self) async -> EnumLayoutCalculator.LayoutResult? {
        await Base.renderEnumLayout(state, machO: machO.base)
    }

    public static func renderEnumPrefixComments(_ state: FieldLayoutRenderState, machO: Self, enumLayout: EnumLayoutCalculator.LayoutResult?) async -> SemanticString {
        await Base.renderEnumPrefixComments(state, machO: machO.base, enumLayout: enumLayout)
    }

    public static func renderEnumCaseComments(_ state: FieldLayoutRenderState, machO: Self, forCaseAtIndex index: Int, mangledTypeName: MangledName, enumLayout: EnumLayoutCalculator.LayoutResult?) async throws -> SemanticString {
        try await Base.renderEnumCaseComments(state, machO: machO.base, forCaseAtIndex: index, mangledTypeName: mangledTypeName, enumLayout: enumLayout)
    }
}
