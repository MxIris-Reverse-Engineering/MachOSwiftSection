import MemberwiseInit

@MemberwiseInit(.public)
public struct SwiftInterfaceBuilderConfiguration: Sendable {
    public var indexConfiguration: SwiftInterfaceIndexConfiguration = .init()
    public var printConfiguration: SwiftInterfacePrintConfiguration = .init()
}

@MemberwiseInit(.public)
public struct SwiftInterfaceIndexConfiguration: Sendable {
    public var showCImportedTypes: Bool = false
}

@MemberwiseInit(.public)
public struct SwiftInterfacePrintConfiguration: Sendable {
    public var printStrippedSymbolicItem: Bool = true
    public var emitOffsetComments: Bool = false
    public var printTypeLayout: Bool = false
    public var printEnumLayout: Bool = false
}
