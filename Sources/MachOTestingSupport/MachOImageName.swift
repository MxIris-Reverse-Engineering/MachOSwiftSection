package enum MachOImageName: String {
    case AppKit
    case SwiftUI
    case SwiftUICore
    case AttributeGraph
    case Foundation
    case Combine
    case DeveloperToolsSupport
    case CodableSwiftUI
    case AAAFoundationSwift
    case UIKitCore
    case HomeKit
    case Network
    case ScreenContinuityServices
    case Sharing
    case FeatureFlags
    case ScreenSharingKit
    case DesignLibrary
    case SFSymbols

    case SymbolTests = "../../Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTests.framework/Versions/A/SymbolTests"
    case SymbolTestsCore = "../../Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore"

    var path: String {
        "/\(rawValue)"
    }
}
