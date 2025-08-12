package enum MachOImageName: String {
    // MainCache
    case AppKit
    case SwiftUI
    case SwiftUICore
    case AttributeGraph
    case Foundation
    case Combine
    case DeveloperToolsSupport
    // SubCache
    case CodableSwiftUI
    case AAAFoundationSwift
    case UIKitCore
    case HomeKit

    var path: String {
        "/\(rawValue)"
    }
}
