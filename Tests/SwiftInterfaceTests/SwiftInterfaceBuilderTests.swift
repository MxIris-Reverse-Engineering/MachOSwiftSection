import Foundation
import Testing
import MachOKit
@testable import MachOTestingSupport
@testable import SwiftInterface

class SwiftInterfaceBuilderTests: DyldCacheTests {
    
    override class var cacheImageName: MachOImageName { .SwiftUICore }
    
    @Test func build() async throws {
        let builder = try SwiftInterfaceBuilder(in: machOFileInCache)
        try await builder.prepare()
        try builder.build().string.print()
    }
    
    @Test func buildFile() async throws {
        let machO = machOFileInCache
        let builder = try SwiftInterfaceBuilder(configuration: .init(isEnabledTypeIndexing: true), in: machO)
        builder.setDependencyPaths([.usesSystemDyldSharedCache])
        try await builder.prepare()
        try builder.build().string.write(to: .desktopDirectory.appending(path: "\(machO.imagePath.lastPathComponent)-Dump.swiftinterface"), atomically: true, encoding: .utf8)
    }
}
