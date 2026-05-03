import Foundation
import Testing
import MachOKit
import Demangling
import MachOFoundation
@testable import MachOTestingSupport
import MachOFixtureSupport
@testable import MachOSwiftSection
@testable import SwiftDump
@testable @_spi(Internals) import SwiftInspection

@Suite
final class PrimitiveTypeMappingTests: DyldCacheTests, @unchecked Sendable {
    override class var cacheImageName: MachOImageName { .AttributeGraph }

    @Test func mappingInSwiftUI() async throws {
        let mapping = try PrimitiveTypeMapping(machO: machOFileInCache)
        mapping.dump()
    }
}
