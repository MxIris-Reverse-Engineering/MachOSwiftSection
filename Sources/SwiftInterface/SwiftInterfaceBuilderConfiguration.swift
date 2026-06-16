import SwiftDeclaration
import MemberwiseInit
import SwiftIndexing
import SwiftPrinting

@MemberwiseInit(.public)
public struct SwiftInterfaceBuilderConfiguration: Equatable, Sendable {
    public var indexConfiguration: SwiftDeclarationIndexConfiguration = .init()
    public var printConfiguration: SwiftDeclarationPrintConfiguration = .init()
}
