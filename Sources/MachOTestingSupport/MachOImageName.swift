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
    
    var path: String {
        "/\(rawValue)"
    }
}
