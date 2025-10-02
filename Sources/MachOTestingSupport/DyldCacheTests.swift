import Foundation
import Testing
import MachOKit
import MachOMacro
import MachOFoundation

package class DyldCacheTests {
    package let mainCache: DyldCache

    package let subCache: DyldCache

    package let fullCache: FullDyldCache
    
    package let machOFileInMainCache: MachOFile

    package let machOFileInSubCache: MachOFile

    package let machOFileInCache: MachOFile

    package class var platform: MachOKit.Platform { .macOS }
    
    package class var mainCacheImageName: MachOImageName { .SwiftUI }
    
    package class var cacheImageName: MachOImageName { .AttributeGraph }
    
    package class var cachePath: DyldSharedCachePath { .current }
    
    package init() async throws {
        self.mainCache = try DyldCache(path: Self.cachePath)
        self.subCache = try required(mainCache.subCaches?.first?.subcache(for: mainCache))
        self.fullCache = try FullDyldCache(path: Self.cachePath)
        self.machOFileInCache = try #require(mainCache.machOFile(named: Self.cacheImageName))
        self.machOFileInMainCache = try #require(mainCache.machOFile(named: Self.mainCacheImageName))
        self.machOFileInSubCache = try #require(subCache.machOFiles().first(where: { _ in true }))
    }
}
