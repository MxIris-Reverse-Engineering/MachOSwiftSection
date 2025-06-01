import Foundation
import Testing
@testable import MachOSwiftSection

@Suite
struct TypeContextDescriptorFlagsTests {
    @Test func create() async throws {
        let flag = TypeContextDescriptorFlags(rawValue: 0b0000_0000_0000_0010)
        #expect(flag.hasSingletonMetadataInitialization == false)
        #expect(flag.hasForeignMetadataInitialization == true)
    }
}
