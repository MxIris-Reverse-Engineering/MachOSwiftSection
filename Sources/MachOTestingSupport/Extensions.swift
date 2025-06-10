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

package enum DyldSharedCachePath: String {
    case current = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e"
    case macOS_26_0 = "/Volumes/Code/Dump/DyldSharedCaches/macOS/26.0/25A5279m/dyld_shared_cache_arm64e"
}

package func loadFromFile(named: MachOFileName) throws -> File {
    let url = URL(fileURLWithPath: named.rawValue)
    return try File.loadFromFile(url: url)
}

extension MachOImage {
    package init?(named: MachOImageName) {
        self.init(name: named.rawValue)
    }
}

extension DyldCache {
    
    package convenience init(path: DyldSharedCachePath) throws {
        try self.init(url: URL(fileURLWithPath: path.rawValue))
    }
    
    package func machOFile(named: MachOImageName) -> MachOFile? {
        machOFile(by: .name(named.rawValue))
    }
}
