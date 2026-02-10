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

@MemberwiseInit(.public)
public struct SwiftInterfacePrintConfiguration: Equatable, Sendable {
    public var printStrippedSymbolicItem: Bool = true
    public var printFieldOffset: Bool = false
    public var printTypeLayout: Bool = false
    public var printEnumLayout: Bool = false
    public var fieldOffsetTransformer: FieldOffsetTransformer? = nil
    public var typeLayoutTransformer: TypeLayoutTransformer? = nil
    public var enumLayoutTransformer: EnumLayoutTransformer? = nil
    public var enumLayoutCaseTransformer: EnumLayoutCaseTransformer? = nil
}
