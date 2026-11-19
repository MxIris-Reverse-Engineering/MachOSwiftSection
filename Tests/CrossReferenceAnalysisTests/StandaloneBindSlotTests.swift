import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
@_spi(Internals) import MachOCodeReferences
@_spi(Internals) import ObjCCodeReferences
@_spi(Internals) import MachOAddressResolution

/// MachOKitExtensions' `SlotResolver` on a standalone file, the one of its
/// tests that needs this package's SymbolTestsCore fixture; the rest live
/// with it (`MachOAddressResolutionTests`).
@Suite
struct StandaloneBindSlotTests {
    /// A standalone file's GOT binds by name: the fixture links the Swift
    /// runtime and Foundation.
    @Test func slotResolverResolvesStandaloneBinds() throws {
        guard case .machO(let machO) = try loadFromFile(named: .SymbolTestsCore) else {
            Issue.record("the SymbolTestsCore fixture is no thin Mach-O")
            return
        }
        let resolver = SlotResolver(machO: machO)
        var boundNames: [String] = []
        for section in machO.sections64 where section.sectionName == "__got" || section.sectionName == "__auth_got" {
            for slotIndex in 0 ..< section.size / 8 {
                let slot = UInt64(section.address) &+ UInt64(slotIndex * 8)
                if case .boundSymbol(let name)? = resolver.content(ofSlotAt: slot) { boundNames.append(name) }
            }
        }
        #expect(boundNames.count > 10)
        #expect(boundNames.contains { $0.hasPrefix("_swift_") || $0.hasPrefix("_$s") })
    }
}
