import SwiftDeclaration
import MemberwiseInit
import Semantic
import SwiftDeclarationRendering
import MachOSwiftSection

public enum SwiftDeclarationMemberSortOrder: Hashable, Codable, Sendable, CaseIterable {
    /// Group members by category: allocators, variables, functions, subscripts, then static members.
    case byCategory
    /// Sort members by binary layout offset (vtable/PWT/MachO offset depending on context).
    case byOffset
}

@MemberwiseInit(.public)
public struct SwiftDeclarationPrintConfiguration: Equatable, Sendable {
    public var printStrippedSymbolicItem: Bool = true
    public var printFieldOffset: Bool = false
    public var printExpandedFieldOffsets: Bool = false
    public var printMemberAddress: Bool = false
    public var printVTableOffset: Bool = false
    public var printPWTOffset: Bool = false
    public var memberSortOrder: SwiftDeclarationMemberSortOrder = .byCategory
    public var printTypeLayout: Bool = false
    public var printEnumLayout: Bool = false

    /// How the static (`MachOFile`) field-layout path resolves cross-module
    /// types when a layout-bearing flag is on. Defaults to the full transitive
    /// dependency closure over the system dyld shared cache; set `.singleImage`
    /// to restrict resolution to the binary being printed.
    public var staticLayoutDependencyResolution: StaticLayoutDependencyResolution = .default

    public var memberAddressTransformer: MemberAddressTransformer? = nil
    public var vtableOffsetTransformer: VTableOffsetTransformer? = nil
    public var fieldOffsetTransformer: FieldOffsetTransformer? = nil
    public var expandedFieldOffsetTransformer: ExpandedFieldOffsetTransformer? = nil
    public var typeLayoutTransformer: TypeLayoutTransformer? = nil
    public var enumLayoutTransformer: EnumLayoutTransformer? = nil
    public var enumLayoutCaseTransformer: EnumLayoutCaseTransformer? = nil
}
