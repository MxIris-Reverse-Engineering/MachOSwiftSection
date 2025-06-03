import MachOKit

enum FrameworkNamed: String {
    case AppKit
    case UIKit
    case SwiftUI
    case SwiftUICore
    case AttributeGraph
    case Foundation
    case CoreFoundation
    case CodableSwiftUI
    case AAAFoundationSwift

    var stringValue: String {
        "/\(rawValue)"
    }
}

extension DyldCache {
    func machOFile(named: FrameworkNamed) -> MachOFile? {
        if let found = machOFiles().first(where: { $0.imagePath.contains(named.stringValue) }) {
            return found
        }

        guard let mainCache else { return nil }

        if let found = mainCache.machOFiles().first(where: { $0.imagePath.contains(named.stringValue) }) {
            return found
        }

        if let subCaches {
            for subCacheEntry in subCaches {
                if let subCache = try? subCacheEntry.subcache(for: mainCache), let found = subCache.machOFiles().first(where: { $0.imagePath.contains(named.stringValue) }) {
                    return found
                }
            }
        }
        return nil
    }
}
