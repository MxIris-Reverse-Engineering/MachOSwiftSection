import Foundation
import Testing
@testable import Demangle
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import Dependencies

@Suite
final class DyldCacheSymbolRemangleTests: DyldCacheSymbolTests {
    @MainActor
    @Test func symbols() throws {
        let allSwiftSymbols = try symbols(for: .SwiftUI, .SwiftUICore)
        "Total Swift Symbols: \(allSwiftSymbols.count)".print()
        for symbol in allSwiftSymbols {
            let swiftStdlibDemangledName = stdlib_demangleName(symbol.stringValue)
            do {
                let node = try demangleAsNode(symbol.stringValue)
                let swiftSectionDemanlgedName = node.print()
                #expect(swiftStdlibDemangledName == swiftSectionDemanlgedName, "\(symbol.stringValue)")
                let remangledString = try Demangle.mangle(node)
                #expect(remangledString == symbol.stringValue)
            } catch {
                symbol.stringValue.print()
                if symbol.stringValue != swiftStdlibDemangledName {
                    Issue.record(error)
                }
            }
        }
    }
    
    @Test func remangle() async throws {
        let node = try demangleAsNode("_$s10Foundation14AttributeScopePAAE13attributeKeysQrvpZQOyAA0B6ScopesO7SwiftUIE0G12UIAttributesV_Qo_ML")
        try Demangle.mangle(node).print()
//        node.description.print()
    }
}
