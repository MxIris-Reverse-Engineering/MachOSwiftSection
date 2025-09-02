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

    case libswiftCoreFoundation
    
    var path: String {
        "/\(rawValue)"
    }
}
