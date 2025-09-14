import Foundation
import Testing
@testable import MachOTestingSupport
@testable import TypeIndexing

struct SourceKitManagerTests {
    @Test func iOSInterface() async throws {
        let manager = SourceKitManager()
        let file = try await manager.interface(for: "Foundation", in: .iOS)
        print(file.contents)
    }
}
