import Foundation
import MachOKit
import MachOExtensions
import UniformTypeIdentifiers

package enum MachOImageName: String {
    // MainCache
    case AppKit
    case SwiftUI
    case SwiftUICore
    case AttributeGraph
    case Foundation
    // SubCache
    case CodableSwiftUI
    case AAAFoundationSwift
    case UIKitCore
    case HomeKit

    var path: String {
        "/\(rawValue)"
    }
}

package enum MachOFileName: String {
    case Finder = "/System/Library/CoreServices/Finder.app"
    case iPhoneMirroring = "/System/Applications/iPhone Mirroring.app"
    case ScreenContinuityUI = "/System/Applications/iPhone Mirroring.app/Contents/Frameworks/ScreenContinuityUI.framework"
    case iOS_22E238_Simulator_SwiftUICore = "/Library/Developer/CoreSimulator/Volumes/iOS_22E238/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUICore.framework"
    case SourceEdit = "/Applications/SourceEdit.app"
    case SourceEditor = "/Applications/SourceEdit.app/Contents/Frameworks/SourceEditor.framework"
    case ControlCenter = "/System/Library/CoreServices/ControlCenter.app"
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
package func loadFromFile(named: MachOFileName) throws -> File {
    var url = URL(fileURLWithPath: named.rawValue)

    if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
        if contentType.conforms(to: .bundle), let executableURL = Bundle(url: url)?.executableURL {
            url = executableURL
        }
    }
    return try MachOKit.loadFromFile(url: url)
}

extension MachOImage {
    package init?(named: MachOImageName) {
        self.init(name: named.rawValue)
    }
}

extension DyldCache {
    package func machOFile(named: MachOImageName) -> MachOFile? {
        machOFile(by: .name(named.rawValue))
    }
}
