import Foundation
import Testing
import MachOKit
import Demangle
import MachOFoundation
@testable import MachOTestingSupport
@testable import MachOSwiftSection

@Suite
final class PrimitiveTypeMappingTests: DyldCacheTests {
    
    override class var cacheImageName: MachOImageName { .SwiftUI }
    
    @Test func mappingInSwiftUI() async throws {
        let mapping = try PrimitiveTypeMapping(machO: machOFileInCache)
        mapping.dump()
    }
}
