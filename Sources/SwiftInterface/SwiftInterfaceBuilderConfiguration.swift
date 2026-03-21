import MemberwiseInit
import Semantic
import SwiftDump
import MachOSwiftSection

@MemberwiseInit(.public)
public struct SwiftInterfaceBuilderConfiguration: Sendable {
    public var indexConfiguration: SwiftInterfaceIndexConfiguration = .init()
    public var printConfiguration: SwiftInterfacePrintConfiguration = .init()
}

@MemberwiseInit(.public)
public struct SwiftInterfaceIndexConfiguration: Equatable, Sendable {
    public var showCImportedTypes: Bool = false
}

public enum MemberSortOrder: Equatable, Sendable {
    /// Group members by category: allocators, variables, functions, subscripts, then static members.
    case byCategory
    /// Sort members by binary layout offset (vtable/PWT/MachO offset depending on context).
    case byOffset
}

@MemberwiseInit(.public)
public struct SwiftInterfacePrintConfiguration: Equatable, Sendable {
    public var printStrippedSymbolicItem: Bool = true
    public var printFieldOffset: Bool = false
    public var printMemberAddress: Bool = false
    public var printVTableOffset: Bool = false
    public var memberSortOrder: MemberSortOrder = .byCategory
    public var printTypeLayout: Bool = false
    public var printEnumLayout: Bool = false
    public var memberAddressTransformer: MemberAddressTransformer? = nil
    public var vtableOffsetTransformer: VTableOffsetTransformer? = nil
    public var fieldOffsetTransformer: FieldOffsetTransformer? = nil
    public var typeLayoutTransformer: TypeLayoutTransformer? = nil
    public var enumLayoutTransformer: EnumLayoutTransformer? = nil
    public var enumLayoutCaseTransformer: EnumLayoutCaseTransformer? = nil
}
