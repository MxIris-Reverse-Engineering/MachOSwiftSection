import SwiftDeclaration
import MemberwiseInit
import SwiftIndexing
import SwiftPrinting

@MemberwiseInit(.public)
public struct SwiftInterfaceBuilderConfiguration: Equatable, Sendable {
    public var indexConfiguration: SwiftDeclarationIndexConfiguration = .init()
    public var printConfiguration: SwiftDeclarationPrintConfiguration = .init()

    /// When set, `printRoot()` renders this as the leading
    /// `InterfaceHeaderBlock` comment block, ahead of the imports (evolution
    /// proposal 0008). `nil` (the default) keeps the output byte-identical
    /// to before. Callers typically build it with the
    /// `InterfaceHeaderInfo(machO:generatorName:generatorVersion:...)`
    /// factory and may override any field.
    public var interfaceHeaderInfo: InterfaceHeaderInfo? = nil
}
