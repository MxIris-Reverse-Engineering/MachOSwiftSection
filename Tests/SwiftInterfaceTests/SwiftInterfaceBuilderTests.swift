import Foundation
import Testing
@testable import MachOTestingSupport
@testable import SwiftInterface
import MachOKit

class SwiftInterfaceBuilderTests: DyldCacheTests {
    @Test func build() async throws {
        let builder = try SwiftInterfaceBuilder(machO: machOFileInMainCache)
        try await builder.prepare()
        try builder.build().string.print()
    }
    
    @Test func buildFile() async throws {
        let machO = machOFileInMainCache
        let builder = try SwiftInterfaceBuilder(machO: machO)
        builder.setDependencyPaths([.usesSystemDyldSharedCache])
        try await builder.prepare()
        try builder.build().string.write(to: .desktopDirectory.appending(path: "\(machO.imagePath.lastPathComponent)-Dump.swiftinterface"), atomically: true, encoding: .utf8)
    }
}
