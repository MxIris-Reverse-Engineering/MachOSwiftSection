package enum MachOImageName: String {
    // MainCache
    case AppKit
    case SwiftUI
    case SwiftUICore
    case AttributeGraph
    case Foundation
    case Combine
    // SubCache
    case CodableSwiftUI
    case AAAFoundationSwift
    case UIKitCore
    case HomeKit

    var path: String {
        "/\(rawValue)"
    }
}
