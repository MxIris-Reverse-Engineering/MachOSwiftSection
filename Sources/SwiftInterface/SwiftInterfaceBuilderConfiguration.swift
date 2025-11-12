import MemberwiseInit

@MemberwiseInit(.public)
public struct SwiftInterfaceBuilderConfiguration: Sendable {
    public var showCImportedTypes: Bool = false
    public var printStrippedSymbolicItem: Bool = true
    public var emitOffsetComments: Bool = false
}
