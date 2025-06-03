import MachOKit
import Foundation
import UniformTypeIdentifiers

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
    case Finder = "/System/Library/CoreServices/Finder.app"
    case iPhoneMirroring = "/System/Applications/iPhone Mirroring.app"
    case ScreenContinuityUI = "/System/Applications/iPhone Mirroring.app/Contents/Frameworks/ScreenContinuityUI.framework"
    case iOS_22E238_Simulator_SwiftUICore = "/Library/Developer/CoreSimulator/Volumes/iOS_22E238/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUICore.framework"
    case SourceEdit = "/Applications/SourceEdit.app"
    case SourceEditor = "/Applications/SourceEdit.app/Contents/Frameworks/SourceEditor.framework"
}

func loadFromFile(named: MachOFileName) throws -> File {
    var url = URL(fileURLWithPath: named.rawValue)
    
    if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
        if contentType.conforms(to: .bundle), let executableURL = Bundle(url: url)?.executableURL {
            url = executableURL
        }
    }
    return try MachOKit.loadFromFile(url: url)
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
