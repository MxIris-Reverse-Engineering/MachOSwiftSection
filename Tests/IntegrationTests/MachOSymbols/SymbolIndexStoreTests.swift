import Foundation
import Testing
import MachO
@_spi(Internals) @testable import MachOSymbols
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
final class SymbolIndexStoreTests: MachOImageTests {
    override class var imageName: MachOImageName {
        .SwiftUI
    }

    @Test func main() async throws {
        SymbolIndexStore.shared.prepare(in: machOImage)
        ProcessMemory.report()
    }
}
