import Foundation
import Testing
import MachOKit
@testable import MachOTestingSupport
@testable import SwiftInterface

class SwiftInterfaceBuilderDyldCacheTests: DyldCacheTests {
    
    override class var platform: Platform { .macOS }
    
    override class var cacheImageName: MachOImageName { .AppKit }

    override class var cachePath: DyldSharedCachePath { .current }
    
    @Test func build() async throws {
        let builder = try SwiftInterfaceBuilder(in: machOFileInCache)
        try await builder.prepare()
        try builder.build().string.print()
    }

    @Test func buildFile() async throws {
        let machO = machOFileInCache
        let builder = try SwiftInterfaceBuilder(configuration: .init(isEnabledTypeIndexing: true), eventHandlers: [OSLogEventHandler()], in: machO)
        builder.setDependencyPaths([.usesSystemDyldSharedCache])
        try await builder.prepare()
        let result = try builder.build()
        try result.string.write(to: .desktopDirectory.appending(path: "\(machO.imagePath.lastPathComponent)-Dump.swiftinterface"), atomically: true, encoding: .utf8)
    }
}


