import Foundation
import Testing
import MachOKit
import Demangling
import MachOFoundation
@testable import MachOTestingSupport
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import SwiftInspection

@Suite
final class PrimitiveTypeMappingTests: DyldCacheTests, @unchecked Sendable {
    override class var cacheImageName: MachOImageName { .AttributeGraph }

    @Test func mappingInSwiftUI() async throws {
        let mapping = try PrimitiveTypeMapping(machO: machOFileInCache)
        mapping.dump()
    }
}
