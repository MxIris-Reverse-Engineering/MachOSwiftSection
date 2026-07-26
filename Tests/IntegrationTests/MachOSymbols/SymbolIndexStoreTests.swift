import Foundation
import Testing
import MachO
@_spi(Internals) @testable import MachOSymbols
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
enum SymbolIndexStoreTests {
    @Suite
    final class SwiftUITests: MachOImageTests {
        override class var imageName: MachOImageName {
            .SwiftUI
        }

        @Test func main() async throws {
            ContinuousClock().measure {
                SymbolIndexStore.shared.prepare(in: machOImage)
            }.print()
            
            ProcessMemory.report()
        }
    }
    
    @Suite
    final class SwiftUICoreTests: MachOImageTests {
        override class var imageName: MachOImageName {
            .SwiftUICore
        }

        @Test func main() async throws {
            ContinuousClock().measure {
                SymbolIndexStore.shared.prepare(in: machOImage)
            }.print()
            ProcessMemory.report()
        }
    }
}
