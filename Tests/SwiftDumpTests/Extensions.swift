import MachOKit
import Foundation

enum MachOImageName: String {
    case AppKit
    case UIKit
    case UIKitCore
    case SwiftUI
    case SwiftUICore
    case AttributeGraph
    case Foundation
    case CoreFoundation
    case CodableSwiftUI
    case AAAFoundationSwift

    var path: String {
        "/\(rawValue)"
    }
}

enum MachOFileName: String {
    case Finder = "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"
    case ScreenContinuityUI = "/System/Applications/iPhone Mirroring.app/Contents/Frameworks/ScreenContinuityUI.framework/Versions/A/ScreenContinuityUI"
    case SwiftUICore = "/Library/Developer/CoreSimulator/Volumes/iOS_22E238/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore"
    case SourceEditor = "/Applications/SourceEdit.app/Contents/Frameworks/SourceEditor.framework/Versions/A/SourceEditor"
}

func loadFromFile(named: MachOFileName) throws -> File {
    try MachOKit.loadFromFile(url: URL(fileURLWithPath: named.rawValue))
}

extension MachOImage {
    init?(named: MachOImageName) {
        self.init(name: named.rawValue)
    }
}

extension DyldCache {
    func machOFile(named: MachOImageName) -> MachOFile? {
        if let found = machOFiles().first(where: { $0.imagePath.contains(named.path) }) {
            return found
        }

        guard let mainCache else { return nil }

        if let found = mainCache.machOFiles().first(where: { $0.imagePath.contains(named.path) }) {
            return found
        }

        if let subCaches {
            for subCacheEntry in subCaches {
                if let subCache = try? subCacheEntry.subcache(for: mainCache), let found = subCache.machOFiles().first(where: { $0.imagePath.contains(named.path) }) {
                    return found
                }
            }
        }
        return nil
    }
}
