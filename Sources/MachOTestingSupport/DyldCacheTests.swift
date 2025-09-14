import Foundation
import Testing
import MachOKit
import MachOMacro
import MachOFoundation

package class DyldCacheTests {
    package let mainCache: DyldCache

    package let subCache: DyldCache

    package let machOFileInMainCache: MachOFile

    package let machOFileInSubCache: MachOFile

    package let machOFileInCache: MachOFile

    package class var platform: MachOKit.Platform {
        return .macOS
    }
    
    package class var mainCacheImageName: MachOImageName { .SwiftUI }
    
    package class var subCacheImageName: MachOImageName {
        if platform == .macOS {
            if #available(macOS 15.5, *) {
                return .CodableSwiftUI
            } else {
                return .UIKitCore
            }
        } else if platform == .iOS {
            return .Network
        } else {
            return .Foundation
        }
    }
    
    package class var cacheImageName: MachOImageName { .AttributeGraph }
    
    package class var cachePath: DyldSharedCachePath { .current }
    
    package init() async throws {
        self.mainCache = try DyldCache(path: Self.cachePath)
        self.subCache = try required(mainCache.subCaches?.first?.subcache(for: mainCache))
        self.machOFileInMainCache = try #require(mainCache.machOFile(named: Self.mainCacheImageName))
        self.machOFileInSubCache = try #require(subCache.machOFiles().first(where: { _ in true }))
        self.machOFileInCache = try #require(mainCache.machOFile(named: Self.cacheImageName))
    }
}
