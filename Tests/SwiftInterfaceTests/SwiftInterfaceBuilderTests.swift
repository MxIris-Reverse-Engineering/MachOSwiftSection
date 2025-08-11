import Foundation
import Testing
@testable import MachOTestingSupport
@testable import SwiftInterface

class SwiftInterfaceBuilderTests: DyldCacheTests {
    @Test func index() async throws {
        let builder = try SwiftInterfaceBuilder(machO: machOFileInMainCache)
        try builder.index()
        dump(builder)
    }
}
